#!/bin/sh
# [汎用コア] コミット済みシークレット検出 — スタック非依存
# Lightweight guard for a public repository: real signing material and
# credentials must never be tracked by git (they are listed in .gitignore).
#
# Fails if either of these is found in the tracked tree:
#   1. a secret / keystore-like file (by name or extension)
#   2. PEM private key material inside any tracked text file
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

SELF="scripts/check-no-committed-secrets.sh"
status=0

# 1. Secret / keystore-like files must never be tracked, at any directory depth.
#    :(glob)**/ matches zero or more leading directories, so a nested
#    app/key.properties or config/.env is caught as well as root-level files.
bad_files="$(git ls-files \
  ':(glob)**/*.jks' ':(glob)**/*.keystore' ':(glob)**/*.p12' ':(glob)**/*.pfx' \
  ':(glob)**/*.pem' ':(glob)**/*.key' \
  ':(glob)**/key.properties' ':(glob)**/secrets.properties' ':(glob)**/.env' \
  ':(glob)**/*service-account*.json' ':(glob)**/play-console-*.json' 2>/dev/null || true)"
if [ -n "$bad_files" ]; then
  echo "Committed secret/keystore-like files detected:" >&2
  printf '  %s\n' $bad_files >&2
  status=1
fi

# 2. PEM private key material must never be committed. Skip this guard file,
#    which legitimately contains the marker pattern.
key_hits="$(git grep -lI -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' -- . ":(exclude)$SELF" 2>/dev/null || true)"
if [ -n "$key_hits" ]; then
  echo "Files containing PEM private key material detected:" >&2
  printf '  %s\n' $key_hits >&2
  status=1
fi

if [ "$status" -ne 0 ]; then
  echo "Remove the secret from the repository (and git history) and rotate it immediately." >&2
  exit 1
fi

echo "No committed secrets detected"
