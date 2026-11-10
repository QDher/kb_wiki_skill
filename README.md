# kb_wiki_skill

Claude Code skills that build and maintain a markdown knowledge wiki: inventory sources, convert PDFs, images and chat transcripts to markdown, triage duplicate/outdated/failed material, distill pages, index, lint. Claude reads the wiki through a short `INDEX.md` and opens only the pages a task needs.

| Folder | Skill | Runtime | Use on |
| --- | --- | --- | --- |
| `kb-wiki/` | `/kb-wiki` | Python 3.8+ (standard library) | Nibi |
| `kb-wiki-shell/` | `/kb-wiki-shell` | bash, standard Unix tools, `jq`; `pdftotext` optional | Linux, macOS, WSL, Git Bash |

Both produce the same wiki layout and use the same page template. Inventories and indexes are `.csv` (Python) or `.tsv` (shell).

## Install

```bash
git clone https://github.com/QDher/kb_wiki_skill.git
mkdir -p ~/.claude/skills

# Python version (Nibi)
cp -r kb_wiki_skill/kb-wiki ~/.claude/skills/
chmod +x ~/.claude/skills/kb-wiki/scripts/*

# Shell version (other machines)
cp -r kb_wiki_skill/kb-wiki-shell ~/.claude/skills/
chmod +x ~/.claude/skills/kb-wiki-shell/scripts/*.sh
```

Then set the variables and create the wiki:

```bash
export KB_ROOT=$HOME/kb
export SKILL_DIR=$HOME/.claude/skills/kb-wiki          # or kb-wiki-shell
bash $SKILL_DIR/scripts/init_kb.sh $KB_ROOT
echo "@$KB_ROOT/CLAUDE.md" >> ~/.claude/CLAUDE.md
```

In Claude Code, run `/kb-wiki` or `/kb-wiki-shell`. Each `SKILL.md` describes the modes: `init`, `ingest`, `update`, `search`, `lint`.

## Layout of a wiki

```
kb/  CLAUDE.md  INDEX.md  README.md  log.md
     rules/ workflows/ projects/ knowledge/ reference/ archive/
     raw/   (originals and converted files; not committed, not loaded)
```

## Notes

- Scripts were tested on sample data only (Linux). macOS and bash 3.2 are untested for the shell version.
- The wiki content belongs in a separate private repository; this repository holds only the skills.
