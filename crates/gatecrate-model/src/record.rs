//! 源泉ファイル共通の行レコード文法。
//!
//! `.es` / `.cmap` / `.cld` はすべて同じ形の行でできている:
//!
//! ```text
//! TAG id [kind] ラベル | key=value | key=value ...
//! ```
//!
//! 属性の区切りは「`|` の後に ASCII 英字のキーと `=` が続く」こと。値の中に現れる
//! ただの `|`（例: `states=閉|開`）は区切りではない。ラベルは最初の `|` まで。

/// 1行ぶんの解析結果。
pub struct Record<'a> {
    pub tag: &'a str,
    /// タグ直後の語（最大2つまで読む。各形式が id / kind として解釈する）。
    pub words: Vec<&'a str>,
    /// 語のあとのラベル本文（属性の手前まで・末尾空白なし）。
    pub label: &'a str,
    attributes: Vec<(&'a str, &'a str)>,
}

impl<'a> Record<'a> {
    /// 属性値（`key=value`）。同じキーが複数回現れたら最後の値。
    pub fn attribute(&self, key: &str) -> Option<&'a str> {
        self.attributes
            .iter()
            .rev()
            .find(|(k, _)| *k == key)
            .map(|(_, v)| *v)
    }

    pub fn attribute_or_empty(&self, key: &str) -> &'a str {
        self.attribute(key).unwrap_or("")
    }
}

/// コメント行(`#`)と空行を除いた行を返す。
pub fn records(source: &str) -> impl Iterator<Item = &str> {
    source.lines().filter(|line| {
        let t = line.trim_start();
        !(t.is_empty() || t.starts_with('#'))
    })
}

/// 行を「タグ + 語 word_count 個 + ラベル + 属性」として読む。
/// タグが一致しない行・語が足りない行は None。
pub fn parse<'a>(line: &'a str, tag: &str, word_count: usize) -> Option<Record<'a>> {
    let mut rest = line.strip_prefix(tag)?;
    if !rest.starts_with(|c: char| c.is_ascii_whitespace()) {
        return None; // "BCx" のような別トークンを弾く
    }
    let mut words = Vec::with_capacity(word_count);
    for _ in 0..word_count {
        rest = rest.trim_start_matches(|c: char| c.is_ascii_whitespace());
        let end = rest
            .find(|c: char| c.is_ascii_whitespace())
            .unwrap_or(rest.len());
        if end == 0 {
            return None;
        }
        words.push(&rest[..end]);
        rest = &rest[end..];
    }
    let body = rest.trim_start_matches(|c: char| c.is_ascii_whitespace());

    let (label, attr_text) = match body.find('|') {
        Some(i) => (body[..i].trim_end(), &body[i..]),
        None => (body.trim_end(), ""),
    };
    Some(Record {
        tag: &line[..tag.len()],
        words,
        label,
        attributes: parse_attributes(attr_text),
    })
}

/// `| key=value` 列。値は次の属性境界の手前まで。
fn parse_attributes(text: &str) -> Vec<(&str, &str)> {
    let mut out = Vec::new();
    let mut cursor = text;
    while let Some(boundary) = attribute_boundary(cursor) {
        let value_and_rest = &cursor[boundary.value_start..];
        let value_end = attribute_boundary(value_and_rest)
            .map(|b| b.separator)
            .unwrap_or(value_and_rest.len());
        out.push((boundary.key, value_and_rest[..value_end].trim()));
        cursor = value_and_rest;
    }
    out
}

struct Boundary<'a> {
    separator: usize,
    value_start: usize,
    key: &'a str,
}

/// 属性境界 `|[ \t]*key=` の最左位置。
fn attribute_boundary(s: &str) -> Option<Boundary<'_>> {
    let bytes = s.as_bytes();
    let mut from = 0;
    while let Some(offset) = s[from..].find('|') {
        let pipe = from + offset;
        let mut i = pipe + 1;
        while i < bytes.len() && (bytes[i] == b' ' || bytes[i] == b'\t') {
            i += 1;
        }
        let key_start = i;
        while i < bytes.len() && (bytes[i].is_ascii_alphabetic() || bytes[i] == b'-') {
            i += 1;
        }
        if i > key_start && i < bytes.len() && bytes[i] == b'=' {
            return Some(Boundary {
                separator: pipe,
                value_start: i + 1,
                key: &s[key_start..i],
            });
        }
        from = pipe + 1;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 値の中の縦棒は属性の区切りにならない() {
        let r = parse("N a aggregate タブ | states=閉|開 | invariant=一意", "N", 2).unwrap();
        assert_eq!(r.label, "タブ");
        assert_eq!(r.attribute("states"), Some("閉|開"));
        assert_eq!(r.attribute("invariant"), Some("一意"));
    }

    #[test]
    fn ラベルは最初の縦棒まで() {
        let r = parse("BC bc_a 閲覧BC | kind=core", "BC", 1).unwrap();
        assert_eq!(r.words, vec!["bc_a"]);
        assert_eq!(r.label, "閲覧BC");
        assert_eq!(r.attribute("kind"), Some("core"));
    }

    #[test]
    fn 同じキーは最後の値が勝つ() {
        let r = parse("N a event X | note=a | note=b", "N", 2).unwrap();
        assert_eq!(r.attribute("note"), Some("b"));
    }
}
