# kb_wiki_skill

Claude Code skills that build and maintain a markdown knowledge wiki: inventory sources, convert PDFs, images and chat transcripts to markdown, triage duplicate/outdated/failed material, distill pages, index, lint, audit and de-duplicate existing pages. Claude reads the wiki through a short `INDEX.md` and opens only the pages a task needs.

| Folder | Skill (plugin command) | Runtime | Use on |
| --- | --- | --- | --- |
| `kb-wiki/` | `/kb-wiki:kb-wiki` | Python 3.8+ (standard library) | Nibi |
| `kb-wiki-shell/` | `/kb-wiki-shell:kb-wiki-shell` | bash, standard Unix tools, `jq`; `pdftotext` optional | Linux, macOS, WSL, Git Bash |

Both produce the same wiki layout and use the same page template. Inventories and indexes are `.csv` (Python) or `.tsv` (shell).

## Install

Both skills are Claude Code plugins from this repository (marketplace `kb-wiki-skills`). One command installs the plugin, turns on auto-update, and creates or clones the wiki. After that, new versions arrive without any action: Claude Code checks GitHub during a session and loads the new version at the next start.

| Where | Command (once) | Updates |
| --- | --- | --- |
| Nibi (Python version) | `module load python`, then `curl -fsSL https://raw.githubusercontent.com/QDher/kb_wiki_skill/main/install.sh \| bash -s -- --python` | automatic |
| Own computer (shell version) | `curl -fsSL https://raw.githubusercontent.com/QDher/kb_wiki_skill/main/install.sh \| bash` | automatic |
| Claude Code on the web (claude.ai/code) | none: a SessionStart hook in the wiki repository installs the plugin in each session (see below) | automatic (fresh install per session) |
| Claude app (claude.ai chats, Projects) | no skill: put `CLAUDE.md` in the Project instructions and `INDEX.md` + needed pages in Project knowledge | re-upload changed pages |

Installer options: `--python` (plugin `kb-wiki` instead of `kb-wiki-shell`), `--kb-root DIR` (default `$KB_ROOT` or `~/kb`), `--wiki-repo URL` (clone an existing wiki instead of creating one), `--no-wiki`, `--dry-run`. It is safe to run again. It also:
- sets `"autoUpdate": true` for the marketplace in `~/.claude/settings.json` (third-party marketplaces do not auto-update by default);
- moves an older copy in `~/.claude/skills/<skill>` (from earlier installers) to `~/.claude/<skill>.old-<date>`, so it does not shadow the plugin;
- adds `@<wiki>/CLAUDE.md` to `~/.claude/CLAUDE.md` once.

Add to your shell profile (`~/.bashrc`):

```bash
export KB_ROOT=$HOME/kb
export SKILL_DIR="$(ls -td ~/.claude/plugins/cache/kb-wiki-skills/kb-wiki/*/kb-wiki | head -n 1)"   # Nibi; for the shell version: kb-wiki-shell/*/kb-wiki-shell
```

`SKILL_DIR` is computed at each login because the plugin folder name changes with each version. In Claude Code, the skill is `/kb-wiki:kb-wiki` or `/kb-wiki-shell:kb-wiki-shell`. Each `SKILL.md` describes the modes: `init`, `ingest`, `update`, `search`, `clean`, `lint`.

**Without the installer** (two commands, then enable auto-update in `/plugin` > Marketplaces > kb-wiki-skills):

```bash
claude plugin marketplace add QDher/kb_wiki_skill
claude plugin install kb-wiki@kb-wiki-skills          # or kb-wiki-shell@kb-wiki-skills
```

**Update now** instead of waiting: `claude plugin marketplace update kb-wiki-skills && claude plugin update kb-wiki@kb-wiki-skills`, then restart Claude Code.

**Claude Code on the web.** Add to the wiki repository `.claude/hooks/session-start.sh`:

```bash
#!/bin/bash
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
claude plugin list 2>/dev/null | grep -q "kb-wiki-shell@kb-wiki-skills" && exit 0
claude plugin marketplace add QDher/kb_wiki_skill >/dev/null 2>&1
claude plugin install kb-wiki-shell@kb-wiki-skills >/dev/null 2>&1 || echo "kb-wiki: plugin install failed" >&2
exit 0
```

and register it under `hooks.SessionStart` in `.claude/settings.json` with the command `$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh`. Cloud sessions ignore plugin settings in a repository's `.claude/settings.json`, so the hook is needed.

**Claude app, optional.** A skill can be uploaded as a zip (Settings > Capabilities > Skills, code execution on): `zip -r kb-wiki-shell.zip kb-wiki-shell`. It does not update itself, has no access to your computer, Nibi or git, and is only useful for `lint` and conversion of uploaded files.

## Layout of a wiki

```
kb/  CLAUDE.md  INDEX.md  README.md  log.md
     rules/ workflows/ projects/ knowledge/ reference/ archive/
     raw/   (originals and converted files; not committed, not loaded)
```

## Documentation

- [docs/tutorial-nibi-python.md](docs/tutorial-nibi-python.md): step-by-step tutorial for the Python version on Nibi.
- [docs/tutorial-shell.md](docs/tutorial-shell.md): step-by-step tutorial for the shell version.

## Cloning a private wiki repository over HTTPS

The wiki repository is private, so `git clone`, `pull` and `push` of the wiki need a GitHub credential. Set it up once per machine with `gh auth login` and `gh auth setup-git`, or an SSH key. For a single clone, enter a GitHub personal access token (read access) without storing it in the shell history or in `.git/config`:

```bash
read -rsp "GitHub token: " GHT; echo; export GHT
H='!f() { echo "username=<github-user>"; echo "password=$GHT"; }; f'
git -c credential.helper="$H" clone https://github.com/<owner>/<repo>.git
unset GHT
```

## Notes

- Scripts were tested on sample data only (Linux). macOS and bash 3.2 are untested for the shell version.
- The wiki content belongs in a separate private repository; this repository holds only the skills.
- This repository is public so that plugin installs and auto-updates need no GitHub credential.
