//! 第4層 — 判定の結果。観測と期待の差だけを持ち、出力形式は知らない。

/// 1件の違反。「どこが」「何を期待し」「何を観測したか」「どう直すか」を必ず揃える。
#[derive(Clone, Debug)]
pub struct Finding {
    pub location: String,
    pub expected: String,
    pub observed: String,
    pub remedy: Option<String>,
}

impl Finding {
    pub fn new(
        location: impl Into<String>,
        expected: impl Into<String>,
        observed: impl Into<String>,
    ) -> Self {
        Self {
            location: location.into(),
            expected: expected.into(),
            observed: observed.into(),
            remedy: None,
        }
    }

    pub fn remedy(mut self, remedy: impl Into<String>) -> Self {
        self.remedy = Some(remedy.into());
        self
    }
}

/// 母集団も基準も評価できない状態。違反ではなく「検査が成立しなかった」。
/// これを違反と混同すると、設定ミスが「違反0＝健全」に化けて黙って穴が空く。
#[derive(Clone, Debug)]
pub struct Unverifiable {
    pub reason: String,
    pub remedy: Option<String>,
}

impl Unverifiable {
    pub fn new(reason: impl Into<String>) -> Self {
        Self {
            reason: reason.into(),
            remedy: None,
        }
    }

    pub fn remedy(mut self, remedy: impl Into<String>) -> Self {
        self.remedy = Some(remedy.into());
        self
    }
}

/// 検査が成立し、対象が存在しなかった場合の扱い。
/// 「対象0＝合格」と「対象0＝設定ミス」はゲートごとに違うので明示させる。
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum WhenNoSubjects {
    Pass,
    Unverifiable,
}
