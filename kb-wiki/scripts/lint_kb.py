#!/usr/bin/env python3
"""Lint the wiki: frontmatter, sizes, staleness, index consistency, links, duplicates, secrets.

Exit code 1 if errors. Usage: lint_kb.py KB_ROOT [--stale-days 180]
"""
import argparse, datetime as dt, os, re, sys

SKIP = {"raw", "archive", ".git", ".claude"}
TOP = {"CLAUDE.md", "INDEX.md", "README.md", "log.md"}
REQUIRED = ["title", "type", "status", "scope", "tags", "sources", "last_verified"]
ENUMS = {"type": {"rule", "workflow", "project", "knowledge", "reference"},
         "status": {"active", "deprecated"}, "scope": {"portable", "account-specific"}}
LIMITS = {"CLAUDE.md": 60, "INDEX.md": 150}
PAGE_MAX = 300
SECRETS = [re.compile(p) for p in (
    r"AKIA[0-9A-Z]{16}", r"-----BEGIN [A-Z ]*PRIVATE KEY-----", r"ghp_[A-Za-z0-9]{36}",
    r"sk-[A-Za-z0-9_-]{20,}", r"xox[bap]-[A-Za-z0-9-]{10,}", r"(?i)(password|passwd|api[_-]?key|token)\s*[:=]\s*\S{6,}")]
LINK = re.compile(r"\[[^\]]*\]\(([^)#\s]+)")


def frontmatter(text):
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end < 0:
        return None
    fm = {}
    for line in text[3:end].splitlines():
        if ":" in line and not line.startswith(" "):
            k, v = line.split(":", 1)
            fm[k.strip()] = v.split("#", 1)[0].strip()
    return fm


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--stale-days", type=int, default=180)
    a = ap.parse_args()
    root = os.path.abspath(os.path.expanduser(a.root))
    errors, warns, titles, pages = [], [], {}, []
    today = dt.date.today()

    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in SKIP]
        for fn in files:
            if fn.endswith(".md"):
                pages.append(os.path.relpath(os.path.join(d, fn), root))

    for rel in sorted(pages):
        path = os.path.join(root, rel)
        text = open(path, encoding="utf-8", errors="replace").read()
        n = text.count("\n") + 1
        if rel in LIMITS and n > LIMITS[rel]:
            errors.append(f"{rel}: {n} lines > {LIMITS[rel]}")
        for rx in SECRETS:
            if rx.search(text):
                errors.append(f"{rel}: possible secret ({rx.pattern[:25]})")
        for target in LINK.findall(text):
            if re.match(r"^[a-z]+:", target):
                continue
            if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(path), target))):
                errors.append(f"{rel}: broken link {target}")
        if rel in TOP:
            continue
        if n > PAGE_MAX:
            warns.append(f"{rel}: {n} lines > {PAGE_MAX}, consider splitting")
        fm = frontmatter(text)
        if fm is None:
            errors.append(f"{rel}: missing frontmatter")
            continue
        for k in REQUIRED:
            if not fm.get(k):
                errors.append(f"{rel}: missing '{k}'")
        for k, allowed in ENUMS.items():
            if fm.get(k) and fm[k] not in allowed:
                errors.append(f"{rel}: {k}='{fm[k]}' not in {sorted(allowed)}")
        try:
            age = (today - dt.date.fromisoformat(fm.get("last_verified", ""))).days
            if age > a.stale_days and fm.get("status") == "active":
                warns.append(f"{rel}: last_verified {age} days ago")
        except ValueError:
            errors.append(f"{rel}: last_verified not YYYY-MM-DD")
        t = fm.get("title", "").lower()
        if t:
            titles.setdefault(t, []).append(rel)

    for t, rels in titles.items():
        if len(rels) > 1:
            errors.append(f"duplicate title '{t}': {', '.join(rels)}")

    idx_path = os.path.join(root, "INDEX.md")
    if os.path.exists(idx_path):
        idx = open(idx_path, encoding="utf-8").read()
        content_pages = [p for p in pages if p not in TOP]
        for p in content_pages:
            if p not in idx:
                warns.append(f"not in INDEX.md: {p}")
        for ref in re.findall(r"^\s*[-*]?\s*`?([\w./-]+\.md)`?\s*\|", idx, re.M):
            if not os.path.exists(os.path.join(root, ref)):
                errors.append(f"INDEX.md lists missing page: {ref}")
    else:
        errors.append("INDEX.md missing")

    for e in errors:
        print("ERROR", e)
    for w in warns:
        print("WARN ", w)
    print(f"{len(pages)} files checked: {len(errors)} errors, {len(warns)} warnings")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
