#!/usr/bin/env bash
# Inventory files under one or more roots into a TSV (read-only).
# Usage: inventory.sh --out FILE.tsv [--source LABEL] [--max-mb 50] ROOT...
# Columns: source path type size_kb modified project sha256 duplicate_of decision reason
set -euo pipefail
. "$(dirname "$0")/lib.sh"

OUT=""; SRC="$(hostname | cut -d. -f1)"; MAXMB=50; ROOTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --source) SRC="$2"; shift 2 ;;
    --max-mb) MAXMB="$2"; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) ROOTS+=("$1"); shift ;;
  esac
done
[ -n "$OUT" ] && [ ${#ROOTS[@]} -gt 0 ] || { sed -n '3p' "$0"; exit 1; }
mkdir -p "$(dirname "$OUT")"
MAXB=$((MAXMB * 1024 * 1024))
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

type_of() {
  case "$(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z')" in
    md) echo markdown ;; txt|rst) echo text ;; pdf) echo pdf ;;
    png|jpg|jpeg|gif|webp) echo image ;; jsonl) echo transcript ;; json) echo json ;;
    sh|sbatch|slurm) echo script ;; py|r) echo code ;; ipynb) echo notebook ;;
    docx) echo docx ;; pptx) echo pptx ;; xlsx) echo xlsx ;; csv|tsv) echo table ;;
    out|log) case "$(basename "$1")" in slurm-*) echo slurm-log ;; *) echo log ;; esac ;;
    *) echo "" ;;
  esac
}

for ROOT in "${ROOTS[@]}"; do
  [ -d "$ROOT" ] || { echo "skip (not a directory): $ROOT" >&2; continue; }
  ROOT="$(cd "$ROOT" && pwd)"
  find "$ROOT" \( -name .git -o -name node_modules -o -name __pycache__ -o -name .venv -o -name venv \
       -o -name site-packages -o -name .cache -o -name .conda -o -name miniconda3 -o -name anaconda3 \
       -o -name .ipynb_checkpoints -o -name _to_delete \) -prune -o -type f -print |
  while IFS= read -r p; do
    t="$(type_of "$p")"; [ -n "$t" ] || continue
    s=$(wc -c < "$p" | tr -d ' ')
    [ "$s" -gt 0 ] && [ "$s" -le "$MAXB" ] || continue
    rel="${p#"$ROOT"/}"; proj=""; case "$rel" in */*) proj="${rel%%/*}" ;; esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$SRC" "$p" "$t" \
      "$(awk -v s="$s" 'BEGIN{printf "%.1f", s/1024}')" "$(mdate_of "$p")" "$proj" "$(sha256_of "$p")"
  done
done > "$TMP"

{
  printf 'source\tpath\ttype\tsize_kb\tmodified\tproject\tsha256\tduplicate_of\tdecision\treason\n'
  # first path seen per sha256 is the original; later ones get duplicate_of
  awk -F'\t' 'BEGIN{OFS="\t"} { d = ($7 in first) ? first[$7] : ""; if (!($7 in first)) first[$7]=$2; print $0, d, "", "" }' "$TMP" |
    sort -t "$(printf '\t')" -k3,3 -k2,2
} > "$OUT"

N=$(($(wc -l < "$OUT") - 1))
echo "$N files -> $OUT"
echo "by type: $(tail -n +2 "$OUT" | cut -f3 | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}')"
echo "exact duplicates: $(tail -n +2 "$OUT" | awk -F'\t' '$8!=""' | wc -l | tr -d ' ')"
