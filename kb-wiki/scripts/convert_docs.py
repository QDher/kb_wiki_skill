#!/usr/bin/env python3
"""Convert PDFs to markdown and create stubs for images (transcribed later by Claude).

PDF: pymupdf4llm if installed, else `pdftotext -layout`. Pages with almost no text
are flagged as scanned (run ocrmypdf, then convert again).
Images: a .md stub per image + images_todo.txt listing them for vision transcription.
Input: --inventory CSV (rows of type pdf/image; skips rows with decision=drop) and/or paths.
"""
import argparse, csv, os, shutil, subprocess, sys

IMG = {".png", ".jpg", ".jpeg", ".gif", ".webp"}


def pdf_to_md(path):
    try:
        import pymupdf4llm  # type: ignore
        return pymupdf4llm.to_markdown(path), "pymupdf4llm"
    except ImportError:
        pass
    if shutil.which("pdftotext"):
        r = subprocess.run(["pdftotext", "-layout", path, "-"], capture_output=True, text=True, timeout=300)
        if r.returncode == 0:
            return r.stdout, "pdftotext"
        raise RuntimeError(r.stderr.strip()[:200])
    raise RuntimeError("no PDF converter: pip install pymupdf4llm, or module load poppler")


def page_count(text):
    return max(1, text.count("\f") + 1)


def out_path(out_dir, src):
    base = os.path.splitext(os.path.basename(src))[0]
    parent = os.path.basename(os.path.dirname(src))
    return os.path.join(out_dir, f"{parent}__{base}.md")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--inventory")
    ap.add_argument("--out", required=True)
    ap.add_argument("--force", action="store_true", help="overwrite existing outputs")
    a = ap.parse_args()

    items = list(a.paths)
    if a.inventory:
        with open(a.inventory, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                if r.get("type") in ("pdf", "image") and r.get("decision", "") != "drop" and not r.get("duplicate_of"):
                    items.append(r["path"])
    os.makedirs(a.out, exist_ok=True)
    todo, scanned, failed, done = [], [], [], 0

    for src in items:
        ext = os.path.splitext(src)[1].lower()
        dst = out_path(a.out, src)
        if os.path.exists(dst) and not a.force:
            continue
        try:
            if ext == ".pdf":
                text, tool = pdf_to_md(src)
                chars_per_page = len(text.strip()) / page_count(text)
                flag = "scanned: needs OCR" if chars_per_page < 100 else "ok"
                if flag != "ok":
                    scanned.append(src)
                body = text.replace("\f", "\n\n---\n\n")
            elif ext in IMG:
                tool, flag = "stub", "todo: vision transcription"
                body = "TODO: transcribe visible text; describe the figure in 2-5 lines; state if the image must be kept in assets/."
                todo.append(f"{src}\t{dst}")
            else:
                continue
            with open(dst, "w", encoding="utf-8") as f:
                f.write(f"---\nsource: {src}\nconverter: {tool}\nstatus: {flag}\n---\n\n{body}\n")
            done += 1
        except Exception as ex:
            failed.append(f"{src}\t{ex}")

    for name, lines in (("images_todo.txt", todo), ("scanned_pdfs.txt", scanned), ("failed.txt", failed)):
        if lines:
            with open(os.path.join(a.out, name), "a", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")
    print(f"converted {done}; images to transcribe {len(todo)}; scanned PDFs {len(scanned)}; failed {len(failed)}")


if __name__ == "__main__":
    main()
