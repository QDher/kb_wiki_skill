#!/bin/bash
# Bulk conversion for the wiki. Submit: sbatch --account=$PROJECT kb_convert.sbatch
#SBATCH --job-name=kb-convert
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --output=%x-%j.out
set -euo pipefail

KB="${KB_ROOT:-$HOME/kb}"
SKILL_DIR="${SKILL_DIR:-$HOME/.claude/skills/kb-wiki}"

module load python 2>/dev/null || true
# Optional better PDF output (create once on a login node):
#   python -m venv ~/kb-venv && ~/kb-venv/bin/pip install pymupdf4llm
[ -f "$HOME/kb-venv/bin/activate" ] && source "$HOME/kb-venv/bin/activate"

python3 "$SKILL_DIR/scripts/convert_docs.py" --inventory "$KB/raw/inventory.csv" --out "$KB/raw/converted/docs"
python3 "$SKILL_DIR/scripts/digest_chats.py" "$HOME/.claude/projects" --out "$KB/raw/converted/chats"
