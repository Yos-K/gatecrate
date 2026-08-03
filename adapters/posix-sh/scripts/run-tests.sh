#!/bin/sh
# [POSIX shアダプタ] 挙動テストゲート — スタック非依存のシェルハーネス向け
#
# WHY: 既存8アダプタは全て言語スタック向け（テストランナ＋カバレッジ）だが、ハーネス自身のように
# **アプリケーションコードを持たず POSIX sh とモデルファイルだけで構成される消費者**が存在する
# （組織・仕様・ドキュメントの層を回すリポジトリ）。そこでの「テスト」は言語のテストランナでなく
# `tests/test-*.sh` の挙動テストであり、カバレッジ計測の対象になるプロダクトコードが無い。
# 本スクリプトはその形の消費者に、他アダプタと同じ入口（run-tests.sh）を与える。
#
# 各テストは独立した sh プロセスで実行し、非0を失敗として数える。1本でも落ちれば非0で終了する。
# 失敗したテストの出力は字下げして全文を出す（どのアサートが落ちたかを追えるようにする）。
#
# Config (optional, from harness.config.sh):
#   SH_TESTS_DIR      — テストの在処（既定: tests。無ければ scripts）
#   SH_TESTS_GLOB     — テストファイルのグロブ（既定: test-*.sh）
#
# Usage: sh adapters/posix-sh/scripts/run-tests.sh
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
SH_TESTS_GLOB="${SH_TESTS_GLOB:-test-*.sh}"
if [ -z "${SH_TESTS_DIR:-}" ]; then
  if [ -d "$ROOT/tests" ]; then SH_TESTS_DIR="tests"; else SH_TESTS_DIR="scripts"; fi
fi

cd "$ROOT"
[ -d "$SH_TESTS_DIR" ] || { echo "run-tests: no test directory ($SH_TESTS_DIR) — nothing to run." >&2; exit 1; }

pass=0; fail=0
for t in "$SH_TESTS_DIR"/$SH_TESTS_GLOB; do
  [ -f "$t" ] || continue
  if out="$(sh "$t" 2>&1)"; then
    echo "  PASS: $t"; pass=$((pass + 1))
  else
    echo "  FAIL: $t"; printf '%s\n' "$out" | sed 's/^/    /'; fail=$((fail + 1))
  fi
done

# 発見ゼロは「全部通った」ではない。グロブ不一致やディレクトリ移動で無言に蒸発するのを緑にしない
if [ "$((pass + fail))" -eq 0 ]; then
  echo "run-tests: FAIL — no test matched $SH_TESTS_DIR/$SH_TESTS_GLOB (a silent zero is not a pass)." >&2
  exit 1
fi
echo "run-tests: PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
