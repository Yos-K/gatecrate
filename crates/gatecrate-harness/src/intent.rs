//! 第1層 — このハーネスは何を検出したいのか。

use std::fmt;

/// 発火の意味づけ。二階ループ（ROI 剪定・生存証明）はこの型で価値の測り方を変える。
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum GateKind {
    /// 違反の混入を止める。発火0が健全。壊れても発火0なので生存証明を要する。
    Prevention,
    /// 既にある事実を見つける。発火が価値。発火0が続けば剪定候補。
    Detection,
    /// 信号を出すがマージは止めない。価値は「信号が消費されるか」で測る。
    Advisory,
}

impl GateKind {
    pub fn blocks_merge(self) -> bool {
        !matches!(self, GateKind::Advisory)
    }

    /// 発火0の解釈。同じ観測値が型で逆の意味になる（反事実の罠の回避）。
    pub fn silence_means_healthy(self) -> bool {
        matches!(self, GateKind::Prevention)
    }
}

impl fmt::Display for GateKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            GateKind::Prevention => "prevention",
            GateKind::Detection => "detection",
            GateKind::Advisory => "advisory",
        })
    }
}

/// 検出したい欠陥の宣言。実装より先にこれが決まる。
#[derive(Clone, Copy, Debug)]
pub struct Intent {
    /// サブコマンド名（`gatecrate check <name>`）。
    pub name: &'static str,
    pub kind: GateKind,
    /// 何を検出するか。失敗報告の見出しに出る。
    pub detects: &'static str,
    /// なぜ検出するか（この欠陥が通ると何が起きるか）。
    pub because: &'static str,
    /// 意図的に検出しないこと。ここに書かれた期待で責めない、という契約。
    pub does_not_detect: &'static [&'static str],
}
