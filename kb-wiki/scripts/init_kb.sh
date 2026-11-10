#!/usr/bin/env bash
# Create the wiki skeleton. Usage: init_kb.sh [KB_ROOT]  (default $HOME/kb). Existing files are not overwritten.
set -euo pipefail
KB="${1:-$HOME/kb}"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$KB"/{rules,workflows,projects,knowledge,reference/assets,archive,raw/converted,raw/_to_delete}
for f in CLAUDE.md INDEX.md README.md; do
  [ -e "$KB/$f" ] || cp "$SKILL_DIR/templates/$f" "$KB/$f"
done
[ -e "$KB/log.md" ] || printf '# Log (newest first)\n\n- %s init wiki\n' "$(date +%F)" > "$KB/log.md"
[ -e "$KB/.gitignore" ] || printf 'raw/\n*.pdf\n*.jsonl\n.DS_Store\n' > "$KB/.gitignore"

if [ ! -d "$KB/.git" ]; then
  git -C "$KB" init -q
  git -C "$KB" add -A
  # use a placeholder identity for this first commit only if git has none configured
  if [ -z "$(git -C "$KB" config user.email 2>/dev/null)" ]; then
    export GIT_AUTHOR_NAME=kb-wiki GIT_AUTHOR_EMAIL=kb-wiki@localhost GIT_COMMITTER_NAME=kb-wiki GIT_COMMITTER_EMAIL=kb-wiki@localhost
  fi
  git -C "$KB" commit -qm "init wiki" || echo "note: first commit skipped; set git user.name and user.email, then commit" >&2
fi
echo "wiki ready at $KB"
