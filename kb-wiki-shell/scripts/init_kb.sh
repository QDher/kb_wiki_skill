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
  git -C "$KB" commit -qm "init wiki" || true
fi
echo "wiki ready at $KB"
