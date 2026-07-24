//! 生きたモデルの源泉（.es / .cmap / .cld / .spec）の型と読み取り。
//!
//! 4形式は同じ行レコード文法（record）を共有する。文法違反の検出は es-lint 系の
//! ゲートの仕事で、この crate は「読める行を型にする」ことだけを担う。

pub mod cld;
pub mod cmap;
pub mod es;
pub mod record;
pub mod spec;
