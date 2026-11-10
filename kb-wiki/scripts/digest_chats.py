#!/usr/bin/env python3
"""Digest chat transcripts into short markdown files for triage and distillation.

Inputs (files or directories, searched recursively):
  - Claude Code transcripts: ~/.claude/projects/*/*.jsonl
  - claude.ai data export: conversations.json
Per turn keeps: user message, commands run, files written, errors with the next
successful command, and the final assistant answer. Tool output bodies are dropped.
Also writes chats_index.csv (one row per conversation) for triage.
"""
import argparse, csv, json, os, re, sys

MAX_USER, MAX_ANSWER, MAX_CMD, MAX_ERR = 1500, 1200, 200, 300
NOISE = re.compile(r"^\s*<(local-command-stdout|local-command-stderr|system-reminder|command-message|command-args)")
CMD_TOOLS = {"Bash", "bash", "shell", "run_command"}
WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit", "create_file", "str_replace"}


def clip(s, n):
    s = (s or "").strip()
    return s if len(s) <= n else s[:n].rstrip() + " [...]"


def text_of(content):
    if isinstance(content, str):
        return content
    out = []
    for b in content or []:
        if isinstance(b, dict) and b.get("type") == "text":
            out.append(b.get("text", ""))
        elif isinstance(b, str):
            out.append(b)
    return "\n".join(out)


def slug(s, n=50):
    s = re.sub(r"[^A-Za-z0-9]+", "-", s or "").strip("-").lower()
    return s[:n] or "untitled"


# ---------- Claude Code JSONL ----------
def parse_jsonl(path):
    turns, cur, pending = [], None, {}
    meta = {"cwd": "", "started": "", "session": os.path.splitext(os.path.basename(path))[0]}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            if e.get("isSidechain") or e.get("isMeta"):
                continue
            meta["cwd"] = meta["cwd"] or e.get("cwd", "")
            meta["started"] = meta["started"] or (e.get("timestamp") or "")[:19]
            msg = e.get("message") or {}
            content = msg.get("content")
            if e.get("type") == "user":
                blocks = content if isinstance(content, list) else []
                results = [b for b in blocks if isinstance(b, dict) and b.get("type") == "tool_result"]
                if results and cur:
                    for r in results:
                        cmd = pending.pop(r.get("tool_use_id"), None)
                        if r.get("is_error"):
                            cur["errors"].append({"cmd": cmd or "", "err": clip(text_of(r.get("content")), MAX_ERR), "fix": None})
                        elif cmd and cur["errors"] and cur["errors"][-1]["fix"] is None:
                            cur["errors"][-1]["fix"] = cmd
                    continue
                t = text_of(content)
                if not t.strip() or NOISE.match(t):
                    continue
                cur = {"time": (e.get("timestamp") or "")[:16], "user": t, "cmds": [], "files": [], "errors": [], "answer": ""}
                turns.append(cur)
            elif e.get("type") == "assistant" and cur is not None:
                for b in content if isinstance(content, list) else []:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "text" and b.get("text", "").strip():
                        cur["answer"] = b["text"]
                    elif b.get("type") == "tool_use":
                        name, inp = b.get("name", ""), b.get("input") or {}
                        if name in CMD_TOOLS and inp.get("command"):
                            c = clip(inp["command"], MAX_CMD)
                            cur["cmds"].append(c)
                            pending[b.get("id")] = c
                        elif name in WRITE_TOOLS and (inp.get("file_path") or inp.get("path")):
                            fp = inp.get("file_path") or inp.get("path")
                            if fp not in cur["files"]:
                                cur["files"].append(fp)
    title = clip(turns[0]["user"].splitlines()[0], 80) if turns else meta["session"]
    return [(title, "claude-code", meta, turns)]


# ---------- claude.ai export ----------
def parse_export(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    convs = []
    for c in data if isinstance(data, list) else []:
        turns, cur = [], None
        for m in c.get("chat_messages", []):
            t = m.get("text") or text_of(m.get("content"))
            if m.get("sender") == "human":
                cur = {"time": (m.get("created_at") or "")[:16], "user": t, "cmds": [], "files": [], "errors": [], "answer": ""}
                turns.append(cur)
            elif cur is not None and t.strip():
                cur["answer"] = t
        if turns:
            meta = {"cwd": "", "started": (c.get("created_at") or "")[:19], "session": c.get("uuid", "")}
            convs.append((c.get("name") or clip(turns[0]["user"], 80), "claude.ai", meta, turns))
    return convs


def render(title, kind, meta, turns, src):
    nerr = sum(len(t["errors"]) for t in turns)
    out = ["---", f"source: {src}", f"kind: {kind}", f"session: {meta['session']}",
           f"started: {meta['started']}", f"cwd: {meta['cwd']}", f"turns: {len(turns)}", f"errors: {nerr}",
           "decision: ", "---", f"# {title}", ""]
    for i, t in enumerate(turns, 1):
        out.append(f"## Turn {i} ({t['time']})")
        out.append("**User:** " + clip(t["user"], MAX_USER))
        if t["cmds"]:
            shown = t["cmds"][:15]
            out.append(f"**Commands ({len(t['cmds'])}):**")
            out += [f"- `{c.replace(chr(10), ' ; ')}`" for c in shown]
            if len(t["cmds"]) > 15:
                out.append(f"- ... {len(t['cmds']) - 15} more")
        if t["files"]:
            out.append("**Files written:** " + ", ".join(f"`{p}`" for p in t["files"][:20]))
        for e in t["errors"]:
            line = f"- ERROR `{e['cmd'].replace(chr(10), ' ; ')}`: {e['err'].replace(chr(10), ' ')}"
            if e["fix"]:
                line += f"\n  - next OK: `{e['fix'].replace(chr(10), ' ; ')}`"
            out.append(line)
        if t["answer"]:
            out.append("**Result:** " + clip(t["answer"], MAX_ANSWER))
        out.append("")
    return "\n".join(out), nerr


def collect(paths):
    for p in paths:
        p = os.path.expanduser(p)
        if os.path.isdir(p):
            for d, _, fs in os.walk(p):
                for fn in fs:
                    if fn.endswith(".jsonl") or fn == "conversations.json":
                        yield os.path.join(d, fn)
        elif os.path.isfile(p):
            yield p


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--min-turns", type=int, default=1, help="skip conversations with fewer turns")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    index = []
    for src in collect(a.inputs):
        try:
            convs = parse_export(src) if src.endswith(".json") else parse_jsonl(src)
        except Exception as ex:  # keep going on malformed files
            print(f"skip {src}: {ex}", file=sys.stderr)
            continue
        for title, kind, meta, turns in convs:
            if len(turns) < a.min_turns:
                continue
            md, nerr = render(title, kind, meta, turns, src)
            date = (meta["started"] or "0000-00-00")[:10]
            name = f"{date}_{slug(title)}_{(meta['session'] or '')[:8]}.md"
            with open(os.path.join(a.out, name), "w", encoding="utf-8") as f:
                f.write(md)
            index.append([name, kind, date, title, len(turns), nerr, len(md), meta["cwd"], src])
    with open(os.path.join(a.out, "chats_index.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["digest", "kind", "date", "title", "turns", "errors", "chars", "cwd", "source", "decision", "reason"])
        w.writerows(sorted(index, key=lambda r: r[2], reverse=True))
    print(f"{len(index)} conversations -> {a.out} (index: chats_index.csv)")


if __name__ == "__main__":
    main()
