# gatecrate × cc-sdd — spec-test-loop を各フェーズに注入する custom steering

> これは **cc-sdd の custom steering**（`/kiro:steering-custom` 相当）。消費者が自分のリポの
> `.kiro/steering/` に置くと、cc-sdd の各コマンドが「Load entire `.kiro/steering/` as project memory」で
> これを読み、**cc-sdd のコマンド本体を一切改変せずに** gatecrate の spec-test-loop を流れに参加させる。
> 法的根拠: cc-sdd は MIT（gotalab/cc-sdd）。本ファイルは gatecrate 自身の成果物で、cc-sdd のソースは含まない。
>
> インストール: このファイルを `.kiro/steering/gatecrate-spec-test-loop.md` にコピー。gatecrate の
> 計測スクリプト（run-mutation / check-test-compiles 等）と persona（domain-modeler / spec-author /
> coverage-deepener / coverage-scout）が手元にあること。persona は `spec-author` のみ
> `templates/takt/personas/` に同梱、残り3つは `gatecrate-evaluate` スキル同梱
> （`.claude/skills/gatecrate-evaluate/takt/personas/`）から取得する。モードは `harness.config.sh SPEC_LOOP_MODE`。

## 大原則: 二方向が「仕様モデル層」で出会う

- **cc-sdd**（前進）= 意図 → 概念 → 仕様 → 実装。仕様は人間が著す authoritative。
- **spec-test-loop**（逆行）= 実装 → 発見仕様 → 概念**仮説** → ROI 技法 → mutation。
- 両者の**差分が金脈**: authored 仕様 vs discovered 仕様が食い違えば drift（バグ or 仕様が古い）、
  discovered に在って authored に無ければ欠落概念、規則に在ってテストに無ければ未テスト。

cc-sdd 仕様が在るか否かでモードを合わせる: **在る → expert-gated**（"expert" = `.kiro/specs/`）、
**無い（greenfield/legacy）→ autonomous**（発見仕様で `.kiro/specs/` を bootstrap）。

## フェーズ別の注入（各コマンドの中でこう振る舞う）

- **`/kiro:steering` / `/kiro:validate-gap`**: domain-modeler を逆行で使う。対象コードが構造的に体現する
  制約から「在るかもしれない概念・**欠落概念**」を提示し、既存の概念モデルが新要件に十分かの照合材料にする。
  （cc-sdd の「既存概念モデルの再検証」を、コード側の証拠で裏取り）

- **`/kiro:spec-design`（概念モデル先行）**: domain-modeler の entity/value/policy 分類を供給。設計の
  概念モデルと、コードが示唆する概念の差分を design.md の discovery に記録。

- **`/kiro:spec-impl`**: 実装したクラスタごとに spec-test-loop の **reflect → measure** を回す。
  各規則の技法を **ROI で選定**（不変条件→PBT / 状態→ステートフルPBT+Alloy / 小空間→例示 / 境界→探索的）して
  `docs/spec/<area>.md` に記録し、**survivor-strict mutation を変更クラスタにスコープ**して回す。
  生存があれば「その規則は十分テストされていない」＝殺すテストを足す（coverage-deepener）。

- **`/kiro:validate-impl`**: 検証の証拠に **mutation clean ＋ 仕様↔テストのトレーサビリティ** を要求する。
  「テストが緑」だけを合格条件にしない——緑でも mutation 生存があれば仕様は未検証（実証済みの罠）。
  さらに **discovered 仕様 vs `.kiro/specs/` の design/requirements を照合し drift を報告**する。
  **機械的裏打ち（prompt 注入だけに頼らない）**: validate-impl の冒頭で Bash で
  `touch .kiro/.gatecrate-mutation-pending` を実行して mutation gate を **arm** する。すると
  Stop hook（`templates/hooks/spec-test-mutation-gate.sh`）が survivor-strict mutation を機械実行し、
  生存があれば**エージェントの停止をブロック**してフィードバックする＝緑だけでは validate-impl を終えられない。
  marker は transient なので `.gitignore` に `.kiro/.gatecrate-mutation-pending` を追加すること。

## モード（SPEC_LOOP_MODE）と cc-sdd ゲートの関係

- **expert-gated**（cc-sdd 仕様あり）: ループは `.kiro/specs/` に従う。drift・欠落概念は**提案として
  cc-sdd の承認フロー（requirements/design の次反復）に還流**。canonize は cc-sdd のフェーズ承認が担う。
- **autonomous**（cc-sdd 仕様なし/バイブコーディング）: エージェントが機能から判断して規則を canon 化＋
  ACTIVE テスト。ただしビジネスポリシー型は `DECIDED AUTONOMOUSLY (policy)` を明示し、発見仕様は
  `.kiro/specs/<feature>/requirements.md` のドラフトとして起き、**人間が cc-sdd ゲートで確定**する。

## 正直な限界（このファイルは steering＝prompt 注入であってハードゲートではない）

steering はエージェントへの**指示（規約）**であり、cc-sdd コマンドが本ファイルを読んで従うかは判断層。
**機械的に保証される部分は gatecrate のゲートスクリプト**（survivor-strict mutation・check-test-compiles・
traceability）が担い、概念確定・意図の承認は cc-sdd のフェーズ承認（人間）が担う。＝「機械化できる検証は
ゲート、判断は人間」を cc-sdd の前進フローと統合する、というのが本統合の設計。
