#!/bin/bash
# One-shot: init (if needed), commit, push Blitz to GitHub as branch miao.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARENT="$(cd "$ROOT/.." && pwd)"
cd "$ROOT"

# Parent Reverse_dir is never a git project
if [[ -d "$PARENT/.git" ]]; then
  echo "Removing $PARENT/.git (parent is not versioned)"
  rm -rf "$PARENT/.git"
fi
rm -rf "$PARENT/.github" 2>/dev/null || true

if [[ ! -d .git ]]; then
  git init
fi

git add -A
if git diff --cached --quiet && git rev-parse HEAD >/dev/null 2>&1; then
  echo "Nothing new to commit"
else
  git commit -m "$(cat <<'EOF'
Initial public release of Blitz.

Clean-room macOS launcher and clipboard manager (AppKit), MIT licensed.
EOF
)" || git commit --allow-empty -m "Initial public release of Blitz."
fi

git branch -M miao

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin https://github.com/godlockin/Blitz.git
else
  git remote add origin https://github.com/godlockin/Blitz.git
fi

# Create remote if missing
if ! gh repo view godlockin/Blitz >/dev/null 2>&1; then
  gh repo create godlockin/Blitz --public --source=. --remote=origin --push=false \
    --description "Clean-room open-source macOS launcher + clipboard manager — Raycast-shaped workflows, Clipy-depth clipboard. MIT."
fi

# Push (force only if remote has trivial single-commit bootstrap)
if git ls-remote --heads origin miao | grep -q miao; then
  COUNT=$(gh api repos/godlockin/Blitz/commits?sha=miao --jq 'length' 2>/dev/null || echo 99)
  if [[ "$COUNT" == "1" ]] || [[ "$COUNT" == "0" ]]; then
    git push -u origin miao --force-with-lease || git push -u origin miao --force
  else
    git push -u origin miao
  fi
else
  git push -u origin miao
fi

gh repo edit godlockin/Blitz \
  --description "Clean-room open-source macOS launcher + clipboard manager — Raycast-shaped workflows, Clipy-depth clipboard. MIT." \
  --add-topic macos \
  --add-topic clipboard \
  --add-topic clipboard-manager \
  --add-topic launcher \
  --add-topic productivity \
  --add-topic swift \
  --add-topic appkit \
  --add-topic open-source \
  --add-topic mit-license \
  --add-topic snippets \
  --add-topic menubar \
  --add-topic window-management

gh api repos/godlockin/Blitz -X PATCH \
  -f has_issues=true \
  -f has_wiki=false \
  -f has_projects=false \
  -f homepage='https://github.com/godlockin/Blitz' >/dev/null

echo "---"
gh repo view godlockin/Blitz
echo "Done: https://github.com/godlockin/Blitz/tree/miao"
