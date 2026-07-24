//! 分析ドキュメント（Markdown）→ HTML の決定論変換。
//!
//! 対応記法: 見出し・表・箇条書き・番号付き・コードフェンス・太字・インラインコード・
//! リンク・段落（ハードラップは1段落に吸収）。ビューアの「分析レポート」タブが読む。

use std::fmt::Write as _;

fn escape(text: &str) -> String {
    text.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

/// 行内の装飾。エスケープ後に 太字 → コード → リンク の順で置換する。
fn inline(text: &str) -> String {
    let bolded = replace_span(&escape(text), "**", "**", |mid| !mid.contains('*'), |mid| {
        format!("<b>{mid}</b>")
    });
    let coded = replace_span(&bolded, "`", "`", |_| true, |mid| format!("<code>{mid}</code>"));
    replace_links(&coded)
}

/// `open .. close` に挟まれた区間を置換する（区間は1文字以上・accept を満たすもの）。
fn replace_span(
    text: &str,
    open: &str,
    close: &str,
    accept: impl Fn(&str) -> bool,
    replace: impl Fn(&str) -> String,
) -> String {
    let mut out = String::new();
    let mut rest = text;
    while let Some(start) = rest.find(open) {
        let after = &rest[start + open.len()..];
        let Some(end) = after.find(close) else { break };
        let mid = &after[..end];
        if mid.is_empty() || !accept(mid) {
            break;
        }
        out.push_str(&rest[..start]);
        out.push_str(&replace(mid));
        rest = &after[end + close.len()..];
    }
    out + rest
}

/// `[text](url)` → `<u>text</u>`（自己完結 HTML なので外部リンクは張らない）。
fn replace_links(text: &str) -> String {
    let mut out = String::new();
    let mut rest = text;
    while let Some(start) = rest.find('[') {
        let candidate = &rest[start..];
        let Some(close) = candidate.find(']') else { break };
        let linked = close > 1
            && candidate[close + 1..].starts_with('(')
            && candidate[close + 1..].contains(')');
        if !linked {
            break;
        }
        let paren = candidate[close + 1..].find(')').unwrap();
        out.push_str(&rest[..start]);
        let _ = write!(out, "<u>{}</u>", &candidate[1..close]);
        rest = &candidate[close + 1 + paren + 1..];
    }
    out + rest
}

/// ブロック構造の変換器。行を順に食べ、開いた構造（リスト・表・段落）を状態に持つ。
#[derive(Default)]
struct Converter {
    out: String,
    paragraph: String,
    in_list_item: bool,
    in_ul: bool,
    in_ol: bool,
    in_table: bool,
    in_table_head: bool,
    in_fence: bool,
}

impl Converter {
    fn flush_paragraph(&mut self) {
        if self.paragraph.is_empty() {
            return;
        }
        let body = inline(&self.paragraph);
        let tag = if self.in_list_item { "li" } else { "p" };
        let _ = writeln!(self.out, "<{tag}>{body}</{tag}>");
        self.paragraph.clear();
        self.in_list_item = false;
    }

    fn close_lists(&mut self) {
        self.flush_paragraph();
        if self.in_ul {
            self.out.push_str("</ul>\n");
            self.in_ul = false;
        }
        if self.in_ol {
            self.out.push_str("</ol>\n");
            self.in_ol = false;
        }
    }

    fn close_table(&mut self) {
        if self.in_table {
            if self.in_table_head {
                self.out.push_str("</thead><tbody>\n");
            }
            self.out.push_str("</tbody></table>\n");
            self.in_table = false;
            self.in_table_head = false;
        }
    }

    fn feed(&mut self, line: &str) {
        if line.starts_with("```") {
            self.close_lists();
            self.close_table();
            self.out
                .push_str(if self.in_fence { "</pre>\n" } else { "<pre class=\"code\">\n" });
            self.in_fence = !self.in_fence;
            return;
        }
        if self.in_fence {
            let _ = writeln!(self.out, "{}", escape(line));
            return;
        }
        if line.trim().is_empty() {
            self.close_lists();
            self.close_table();
            return;
        }
        if let Some((level, text)) = heading_of(line) {
            self.close_lists();
            self.close_table();
            let _ = writeln!(self.out, "<h{level}>{}</h{level}>", inline(text));
            return;
        }
        if line.starts_with('|') {
            self.feed_table_row(line);
            return;
        }
        self.close_table();
        if let Some(item) = line.strip_prefix("- ") {
            self.open_list_item(item, ListStyle::Unordered);
            return;
        }
        if let Some(item) = ordered_item_of(line) {
            self.open_list_item(item, ListStyle::Ordered);
            return;
        }
        // 段落。ハードラップされた続きの行は空白1つで繋ぐ。
        let text = line.trim_start();
        if self.paragraph.is_empty() {
            self.paragraph = text.to_string();
        } else {
            self.paragraph.push(' ');
            self.paragraph.push_str(text);
        }
    }

    fn feed_table_row(&mut self, line: &str) {
        self.close_lists();
        if is_table_separator(line) {
            if self.in_table && self.in_table_head {
                self.out.push_str("</thead><tbody>\n");
                self.in_table_head = false;
            }
            return;
        }
        if !self.in_table {
            self.out.push_str("<table>\n<thead>\n");
            self.in_table = true;
            self.in_table_head = true;
        }
        let tag = if self.in_table_head { "th" } else { "td" };
        self.out.push_str("<tr>");
        let cells: Vec<&str> = line.split('|').collect();
        for cell in &cells[1..cells.len().saturating_sub(1)] {
            let _ = write!(self.out, "<{tag}>{}</{tag}>", inline(cell.trim()));
        }
        self.out.push_str("</tr>\n");
    }

    fn open_list_item(&mut self, item: &str, style: ListStyle) {
        self.flush_paragraph();
        match style {
            ListStyle::Unordered => {
                if self.in_ol {
                    self.out.push_str("</ol>\n");
                    self.in_ol = false;
                }
                if !self.in_ul {
                    self.out.push_str("<ul>\n");
                    self.in_ul = true;
                }
            }
            ListStyle::Ordered => {
                if self.in_ul {
                    self.out.push_str("</ul>\n");
                    self.in_ul = false;
                }
                if !self.in_ol {
                    self.out.push_str("<ol>\n");
                    self.in_ol = true;
                }
            }
        }
        self.paragraph = item.to_string();
        self.in_list_item = true;
    }

    fn finish(mut self) -> String {
        self.close_lists();
        self.close_table();
        if self.in_fence {
            self.out.push_str("</pre>\n");
        }
        self.out
    }
}

enum ListStyle {
    Unordered,
    Ordered,
}

/// `#{1,6} テキスト`。ビューアの見出し階層は h3 まで。
fn heading_of(line: &str) -> Option<(usize, &str)> {
    let level = line.chars().take_while(|c| *c == '#').count();
    if (1..=6).contains(&level) && line[level..].starts_with(' ') {
        Some((level.min(3), &line[level + 1..]))
    } else {
        None
    }
}

fn ordered_item_of(line: &str) -> Option<&str> {
    let digits = line.chars().take_while(char::is_ascii_digit).count();
    (digits > 0 && line[digits..].starts_with(". ")).then(|| &line[digits + 2..])
}

/// `|---|:--|` のような区切り行。ヘッダと本体の境界を示す。
fn is_table_separator(line: &str) -> bool {
    line.contains('-')
        && line[1..]
            .chars()
            .all(|c| c == '-' || c == ':' || c == '|' || c.is_ascii_whitespace())
}

pub fn to_html(source: &str) -> String {
    let mut converter = Converter::default();
    for line in source.lines() {
        converter.feed(line);
    }
    converter.finish()
}
