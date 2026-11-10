#!/usr/bin/env python3
"""Inventory files under one or more roots into a CSV (read-only).

Columns: source,path,type,size_kb,modified,project,sha256,duplicate_of,decision,reason
"""
import argparse, csv, hashlib, os, sys, time

TYPES = {
    ".md": "markdown", ".txt": "text", ".rst": "text",
    ".pdf": "pdf", ".png": "image", ".jpg": "image", ".jpeg": "image", ".gif": "image", ".webp": "image",
    ".jsonl": "transcript", ".json": "json",
    ".sh": "script", ".sbatch": "script", ".slurm": "script", ".py": "code", ".r": "code", ".ipynb": "notebook",
    ".docx": "docx", ".pptx": "pptx", ".xlsx": "xlsx", ".csv": "table", ".out": "log", ".log": "log",
}
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "env", "site-packages",
             ".cache", ".conda", "miniconda3", "anaconda3", ".ipynb_checkpoints", "_to_delete"}


def sha256(path, limit_bytes):
    if os.path.getsize(path) > limit_bytes:
        return ""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("roots", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--source", default=os.uname().nodename.split(".")[0], help="label for the source column")
    ap.add_argument("--max-mb", type=float, default=50, help="skip files larger than this")
    ap.add_argument("--all-types", action="store_true", help="include extensions not in the type table")
    a = ap.parse_args()

    limit = int(a.max_mb * 1024 * 1024)
    rows, seen = [], {}
    for root in a.roots:
        root = os.path.abspath(os.path.expanduser(root))
        if not os.path.isdir(root):
            print(f"skip (not a directory): {root}", file=sys.stderr)
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fn in filenames:
                p = os.path.join(dirpath, fn)
                ext = os.path.splitext(fn)[1].lower()
                ftype = TYPES.get(ext)
                if ftype is None and not a.all_types:
                    continue
                if fn.startswith("slurm-") and ext == ".out":
                    ftype = "slurm-log"
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                if st.st_size > limit or st.st_size == 0:
                    continue
                rel = os.path.relpath(p, root)
                project = rel.split(os.sep)[0] if os.sep in rel else ""
                digest = sha256(p, limit)
                dup = seen.get(digest, "") if digest else ""
                if digest and not dup:
                    seen[digest] = p
                rows.append([a.source, p, ftype or ext.lstrip("."), round(st.st_size / 1024, 1),
                             time.strftime("%Y-%m-%d", time.localtime(st.st_mtime)), project, digest, dup, "", ""])

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["source", "path", "type", "size_kb", "modified", "project", "sha256", "duplicate_of", "decision", "reason"])
        w.writerows(sorted(rows, key=lambda r: (r[2], r[1])))

    counts = {}
    for r in rows:
        counts[r[2]] = counts.get(r[2], 0) + 1
    print(f"{len(rows)} files -> {a.out}")
    print("by type: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    print(f"exact duplicates: {sum(1 for r in rows if r[7])}")


if __name__ == "__main__":
    main()
