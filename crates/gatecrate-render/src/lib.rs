//! 源泉モデル → 図・ビューアへの決定論射影（Projection 原型）。
//!
//! Gate 原型（gatecrate-harness）と違い、何も検出しない。「.es が source、図は射影、
//! AI は座標を書かない」という原則の実装で、同じ入力からは常に同じ HTML が出る。

pub mod data;
pub mod markdown;
pub mod mermaid;
pub mod viewer;

pub use viewer::{render, Materials};
