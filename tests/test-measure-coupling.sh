#!/bin/sh
# tests/test-measure-coupling.sh — core/scripts/measure-coupling.sh の挙動テスト（多言語エッジ抽出）
#
# 文脈: import ベースのエッジ抽出が JVM（package 宣言 + import PREFIX）専用で、Balanced Coupling /
# modularity の import 半分が他言語で空だった。COUPLING_LANG で python/go/typescript/rust の抽出器を
# 追加する（モジュール=ディレクトリ・ドット表記に正規化＝pkgdist/modularity がそのまま効く）。
# 本テストは各言語の「内部 import → エッジ」規則と後方互換（既定 java）を回帰固定する。
#
# 検証する性質（各 fixture は git repo・消費モデル通り scripts/ にコピーして実行）:
#   1. java（既定・後方互換）: package+import PREFIX から edges.tsv が出る
#   2. python: from a.b import c → <ファイルのdir> -> a.b（dir がモジュール）
#   3. go: import "PREFIX/x/y" → <ファイルのdir> -> x.y（PKG_PREFIX=モジュールパス必須）
#   4. typescript: 相対 import '../lib/util' をファイル位置から解決し dir モジュールへ
#   5. rust: use crate::a::b::Type → <ファイルのdir> -> a.b（小文字セグメントまで）
#   6. 同一モジュール内 import は自己エッジとして除外
#   7. 非JVM でも measure-modularity が動く（エッジ+距離が modularity-all.tsv に載る）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

# mkrepo <name>: fixture git repo に measure-coupling / measure-modularity を消費形で配置
mkrepo() {
  R="$D/$1"; mkdir -p "$R/scripts"
  git -C "$R" init -q 2>/dev/null || git -c init.defaultBranch=main -C "$R" init -q
  cp "$ROOT/core/scripts/measure-coupling.sh" "$R/scripts/"
  cp "$ROOT/core/scripts/measure-modularity.sh" "$R/scripts/"
}
commit_all() { git -C "$1" add -A >/dev/null; git -C "$1" -c user.email=t@t -c user.name=t commit -qm x; }

echo "property 1: java (default) — package + import PREFIX"
mkrepo j; R="$D/j"
mkdir -p "$R/src/main/java/com/ex/app" "$R/src/main/java/com/ex/db"
printf 'package com.ex.app;\nimport com.ex.db.Conn;\nclass A {}\n' > "$R/src/main/java/com/ex/app/A.java"
printf 'package com.ex.db;\nclass Conn {}\n' > "$R/src/main/java/com/ex/db/Conn.java"
commit_all "$R"
( cd "$R" && COUPLING_PKG_PREFIX=com.ex sh scripts/measure-coupling.sh >/dev/null 2>&1 )
grep -q "com.ex.app	com.ex.db" "$R/build/quality/edges.tsv" \
  && pass "java edge extracted" || fail "java edge missing: $(cat "$R/build/quality/edges.tsv" 2>/dev/null)"

echo "property 2: python — from a.b import c（モジュール=dir）"
mkrepo p; R="$D/p"
mkdir -p "$R/src/app" "$R/src/core/db"
printf 'from core.db import conn\nimport os\n' > "$R/src/app/main.py"
printf 'conn = 1\n' > "$R/src/core/db/conn.py"
commit_all "$R"
( cd "$R" && COUPLING_LANG=python COUPLING_SRC=src COUPLING_FILE_GLOB='*.py' sh scripts/measure-coupling.sh >/dev/null 2>&1 )
grep -q "app	core.db" "$R/build/quality/edges.tsv" \
  && pass "python edge extracted (dir module)" || fail "python edge missing: $(cat "$R/build/quality/edges.tsv" 2>/dev/null)"
grep -q "os" "$R/build/quality/edges.tsv" && fail "external import (os) leaked" || pass "external import excluded"

echo "property 3: go — import \"PREFIX/x/y\""
mkrepo g; R="$D/g"
mkdir -p "$R/src/svc" "$R/src/store/kv"
printf 'package svc\nimport (\n\t"github.com/ex/repo/store/kv"\n\t"fmt"\n)\n' > "$R/src/svc/svc.go"
printf 'package kv\n' > "$R/src/store/kv/kv.go"
commit_all "$R"
( cd "$R" && COUPLING_LANG=go COUPLING_SRC=src COUPLING_FILE_GLOB='*.go' COUPLING_PKG_PREFIX=github.com/ex/repo \
    sh scripts/measure-coupling.sh >/dev/null 2>&1 )
grep -q "svc	store.kv" "$R/build/quality/edges.tsv" \
  && pass "go edge extracted" || fail "go edge missing: $(cat "$R/build/quality/edges.tsv" 2>/dev/null)"
grep -q "fmt" "$R/build/quality/edges.tsv" && fail "stdlib import (fmt) leaked" || pass "stdlib excluded"

echo "property 4: typescript — 相対 import をファイル位置から解決"
mkrepo t; R="$D/t"
mkdir -p "$R/src/app" "$R/src/lib"
printf "import { util } from '../lib/util'\nimport fs from 'fs'\n" > "$R/src/app/main.ts"
printf 'export const util = 1\n' > "$R/src/lib/util.ts"
commit_all "$R"
( cd "$R" && COUPLING_LANG=typescript COUPLING_SRC=src COUPLING_FILE_GLOB='*.ts' sh scripts/measure-coupling.sh >/dev/null 2>&1 )
grep -q "app	lib" "$R/build/quality/edges.tsv" \
  && pass "typescript relative import resolved" || fail "ts edge missing: $(cat "$R/build/quality/edges.tsv" 2>/dev/null)"
grep -q "fs" "$R/build/quality/edges.tsv" && fail "package import (fs) leaked" || pass "package imports excluded"

echo "property 5: rust — use crate::a::b::Type"
mkrepo r; R="$D/r"
mkdir -p "$R/src/api" "$R/src/domain/order"
printf 'use crate::domain::order::Order;\npub fn f() {}\n' > "$R/src/api/handler.rs"
printf 'pub struct Order;\n' > "$R/src/domain/order/mod.rs"
commit_all "$R"
( cd "$R" && COUPLING_LANG=rust COUPLING_SRC=src COUPLING_FILE_GLOB='*.rs' sh scripts/measure-coupling.sh >/dev/null 2>&1 )
grep -q "api	domain.order" "$R/build/quality/edges.tsv" \
  && pass "rust use-path extracted (lowercase segments)" || fail "rust edge missing: $(cat "$R/build/quality/edges.tsv" 2>/dev/null)"

echo "property 6: 同一モジュール内 import は自己エッジとして出ない"
R="$D/p"
printf 'from core.db import conn2\n' > "$R/src/core/db/user.py"
commit_all "$R"
( cd "$R" && COUPLING_LANG=python COUPLING_SRC=src COUPLING_FILE_GLOB='*.py' sh scripts/measure-coupling.sh >/dev/null 2>&1 )
grep -q "core.db	core.db" "$R/build/quality/edges.tsv" && fail "self edge leaked" || pass "self edge excluded"

echo "property 7: 非JVM で measure-modularity が動く（距離つきでエッジ評価）"
R="$D/p"
( cd "$R" && COUPLING_LANG=python COUPLING_SRC=src COUPLING_FILE_GLOB='*.py' sh scripts/measure-modularity.sh >/dev/null 2>&1 ) \
  && pass "measure-modularity runs on python" || fail "modularity failed on python"
grep -q "app	core.db" "$R/build/quality/modularity-all.tsv" \
  && pass "edge evaluated in modularity-all.tsv" || fail "edge not in modularity: $(cat "$R/build/quality/modularity-all.tsv" 2>/dev/null)"

echo "---- test-measure-coupling: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
