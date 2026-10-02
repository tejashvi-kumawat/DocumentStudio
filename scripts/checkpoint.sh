#!/usr/bin/env bash
# Local checkpoint commit of project source. Never pushes, never deletes
# working-tree files, never switches branches.
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

MAX_BYTES=$((20 * 1024 * 1024))

PATHS=(
  lib packages test assets scripts docs features .ai
  linux android ios macos windows web l10n .github
  pubspec.yaml pubspec.lock analysis_options.yaml l10n.yaml
  Makefile README.md .gitignore .metadata
  LICENSE PRIVACY.md TERMS.md THIRD_PARTY_NOTICES.md THIRD_PARTY_LICENSES
)

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "Detached HEAD; refusing to commit." >&2
  exit 1
fi

for p in "${PATHS[@]}"; do
  [[ -e "$p" ]] && git add -- "$p"
done

if git diff --cached --quiet; then
  echo "Nothing to commit on $branch."
  exit 0
fi

bad=0
while IFS= read -r -d '' f; do
  [[ -f "$f" ]] || continue
  size=$(stat -c%s -- "$f" 2>/dev/null || stat -f%z -- "$f")
  if (( size > MAX_BYTES )); then
    echo "Refusing: $f is $size bytes (> 20MB)." >&2
    bad=1
  fi
  case "$f" in
    *.jks|*.keystore|*.p12|*.pfx|*.p8|*.mobileprovision|*key.properties|*KEYSTORE_BACKUP.txt|*.AppImage|*.deb)
      echo "Refusing: $f looks like a secret or binary artifact." >&2
      bad=1
      ;;
  esac
done < <(git diff --cached --name-only --diff-filter=AM -z)

if (( bad )); then
  echo "Unstage the files above (git restore --staged <file>) and fix .gitignore." >&2
  exit 1
fi

git commit -q -m "Checkpoint: $(date '+%Y-%m-%d %H:%M:%S %z')"
git log --oneline -1
