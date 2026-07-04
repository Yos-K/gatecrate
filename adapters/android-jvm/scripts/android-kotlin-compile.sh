#!/bin/sh
# [Android-JVMアダプタ] Kotlin+Java 混在コンパイルヘルパー（JVM直接・Android SDK不要・sourced）
#
# なぜ: android-jvm の run-unit-tests.sh / run-mutation-tests.sh は javac のみ＝Java限定で、
# AGP+Kotlin プロジェクトの .kt ロジック層を JVM 直接実行（Gradle/AGP 非依存）でテスト/変異
# できなかった（gatecrate#25 Gap1）。.kt 対応ロジックを1箇所へ集約し、2スクリプト間の
# ドリフト（= kit が防ごうとしている当のもの）を防ぐ。両スクリプトが本ファイルを source する。
#
# 公開関数:
#   ak_compile OUT_DIR KT_LIST_FILE JAVA_LIST_FILE CLASSPATH [FRIEND_DIR]
#     FRIEND_DIR を渡すと kotlinc に -Xfriend-paths=FRIEND_DIR を付け、その出力（通常は main classes）の
#     internal 宣言を可視にする。test コンパイル時に MAIN_CLASSES を渡すこと（Kotlin の internal は
#     モジュールスコープで、Gradle も同じ friend-paths 機構で test に main の internal を見せている）。
#     KT があれば kotlinc で .kt をコンパイル（解決用に .java も渡すが .class は出さない）→
#     その後 javac で .java をコンパイル。どちらの言語が欠けても動く。PITest/JUnit は
#     生成された JVM バイトコードをそのまま扱える。
#     KT があった場合のみグローバル変数 AK_STDLIB_JAR に kotlin-stdlib の jar パスを設定する
#     （呼び出し側は実行時クラスパスにこれを追加すること）。KT が無ければ AK_STDLIB_JAR="".
#
# 環境変数（呼び出し側 harness.config.sh で上書き可）:
#   KOTLIN_VERSION     — kotlinc ディストリのバージョン（default: 2.0.21）
#   KOTLIN_JVM_TARGET  — kotlinc の -jvm-target（default: 17 / CI の JDK と一致させる）
#
# 前提: 呼び出し側が LIB（jar/dist 置き場・永続キャッシュ可）を export 済み。curl と unzip が必要。

KOTLIN_VERSION="${KOTLIN_VERSION:-2.0.21}"
KOTLIN_JVM_TARGET="${KOTLIN_JVM_TARGET:-17}"

# kotlin-compiler は GitHub リリースの zip（top-level に kotlinc/ ディレクトリを含む）。
# Maven Central には CLI 一式が無いため、ここだけ curl 先が repo1 でなく GitHub になる。
ak_ensure_kotlinc() {
  AK_KOTLINC_BIN="$LIB/kotlinc/bin/kotlinc"
  AK_STDLIB_JAR="$LIB/kotlinc/lib/kotlin-stdlib.jar"
  [ -x "$AK_KOTLINC_BIN" ] && return 0
  zip="$LIB/kotlin-compiler-$KOTLIN_VERSION.zip"
  if [ ! -f "$zip" ]; then
    echo "Downloading kotlin-compiler $KOTLIN_VERSION..."
    curl -sL \
      "https://github.com/JetBrains/kotlin/releases/download/v$KOTLIN_VERSION/kotlin-compiler-$KOTLIN_VERSION.zip" \
      -o "$zip"
  fi
  rm -rf "$LIB/kotlinc"
  unzip -q -o "$zip" -d "$LIB"
}

ak_compile() {
  out="$1"
  ktlist="$2"
  javalist="$3"
  cp="$4"
  friend="${5:-}"
  AK_STDLIB_JAR=""

  if [ -s "$ktlist" ]; then
    ak_ensure_kotlinc
    kt_cp="$AK_STDLIB_JAR"
    [ -n "$cp" ] && kt_cp="$cp:$kt_cp"
    # Kotlin の internal はモジュールスコープ。test を別 kotlinc 呼び出しで compile すると main の
    # internal が見えないため、Gradle と同じく -Xfriend-paths で main 出力を「同一モジュール扱い」にする。
    set -- -jvm-target "$KOTLIN_JVM_TARGET" -classpath "$kt_cp" -d "$out"
    [ -n "$friend" ] && set -- "$@" "-Xfriend-paths=$friend"
    # .java を解決用に渡す（.class は emit されない）。java があるかで argfile 渡しを分岐。
    if [ -s "$javalist" ]; then
      "$AK_KOTLINC_BIN" "$@" @"$ktlist" @"$javalist"
    else
      "$AK_KOTLINC_BIN" "$@" @"$ktlist"
    fi
  fi

  if [ -s "$javalist" ]; then
    jcp="$out"
    [ -n "$cp" ] && jcp="$jcp:$cp"
    [ -n "$AK_STDLIB_JAR" ] && jcp="$jcp:$AK_STDLIB_JAR"
    javac -source 8 -target 8 -cp "$jcp" -d "$out" @"$javalist"
  fi
}
