#!/usr/bin/env bash
# Convert PDFs to markdown (pdftotext) and create stubs for images (transcribed later by Claude).
# Usage: convert_docs.sh --out DIR [--inventory inventory.tsv] [--force] [FILE...]
# Inventory mode converts rows of type pdf/image that are not duplicates and not marked drop.
# Without pdftotext, PDFs are listed in pdf_todo.txt for Claude Code to read directly.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

OUT=""; INV=""; FORCE=0; FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --inventory) INV="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) FILES+=("$1"); shift ;;
  esac
done
[ -n "$OUT" ] || { sed -n '3p' "$0"; exit 1; }
mkdir -p "$OUT"
HAVE_PDF=0; command -v pdftotext >/dev/null 2>&1 && HAVE_PDF=1

LIST="$(mktemp)"; trap 'rm -f "$LIST"' EXIT
[ ${#FILES[@]} -gt 0 ] && printf '%s\n' "${FILES[@]}" > "$LIST"
if [ -n "$INV" ]; then
  awk -F'\t' 'NR > 1 && ($3 == "pdf" || $3 == "image") && $8 == "" && $9 != "drop" { print $2 }' "$INV" >> "$LIST"
fi

done_n=0; img_n=0; scan_n=0; fail_n=0; todo_n=0
while IFS= read -r src; do
  [ -n "$src" ] || continue
  base="$(basename "$src")"; parent="$(basename "$(dirname "$src")")"
  dst="$OUT/${parent}__${base%.*}.md"
  [ -e "$dst" ] && [ "$FORCE" -eq 0 ] && continue
  ext="$(printf '%s' "${src##*.}" | tr 'A-Z' 'a-z')"
  case "$ext" in
    pdf)
      if [ "$HAVE_PDF" -eq 0 ]; then
        printf '%s\t%s\n' "$src" "$dst" >> "$OUT/pdf_todo.txt"; todo_n=$((todo_n + 1)); continue
      fi
      if body="$(pdftotext -layout "$src" - 2>/dev/null)"; then
        pages=$(printf '%s' "$body" | tr -cd '\f' | wc -c | tr -d ' '); pages=$((pages + 1))
        chars=$(printf '%s' "$body" | tr -d '[:space:]' | wc -c | tr -d ' ')
        status=ok
        if [ $((chars / pages)) -lt 100 ]; then status="scanned: needs OCR"; echo "$src" >> "$OUT/scanned_pdfs.txt"; scan_n=$((scan_n + 1)); fi
        { printf -- '---\nsource: %s\nconverter: pdftotext\nstatus: %s\n---\n\n' "$src" "$status"
          printf '%s\n' "$body" | awk '{ gsub("\f", "\n\n---\n\n"); print }'; } > "$dst"
        done_n=$((done_n + 1))
      else
        printf '%s\tpdftotext failed\n' "$src" >> "$OUT/failed.txt"; fail_n=$((fail_n + 1))
      fi ;;
    png|jpg|jpeg|gif|webp)
      printf -- '---\nsource: %s\nconverter: stub\nstatus: todo: vision transcription\n---\n\nTODO: transcribe visible text; describe the figure in 2-5 lines; state if the image must be kept in assets/.\n' "$src" > "$dst"
      printf '%s\t%s\n' "$src" "$dst" >> "$OUT/images_todo.txt"; img_n=$((img_n + 1)); done_n=$((done_n + 1)) ;;
  esac
done < "$LIST"

echo "converted $done_n; images to transcribe $img_n; scanned PDFs $scan_n; PDFs for Claude to read $todo_n; failed $fail_n"
