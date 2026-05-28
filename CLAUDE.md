# CLAUDE.md — for agents working in this directory

This is **not an app**. It's a portable dump of Bakhtiyar's LLM-agent config, used to bootstrap a fresh machine. No build, no tests, no run step. The work here is editing markdown and the Claude Code restore artifacts under `claude-config/` and `skills/`.

## Unusual git layout — read before touching git

The working tree lives **inside an iCloud-synced Obsidian vault**. To stop iCloud from corrupting the repo, git was set up with `--separate-git-dir`:

- `.git` here is a **pointer file**, not a directory: it contains `gitdir: /Users/baha/artifacts/git-storage/claude-config`.
- The real git database lives at `~/artifacts/git-storage/claude-config` (off iCloud).
- Remote: `github.com/bahaospanov/claude-config` (**private**). This is the backup + the thing a fresh machine clones.

Implications:
- **Don't "fix" the `.git` file by re-running `git init`** — it's correct as-is. The pointer is intentional.
- The pointer path is **machine-specific** — commits only work on this Mac. See "Editing from another machine" below.
- iCloud occasionally creates `filename 2.md` conflict copies. They're harmless noise — `rm` them; don't commit them.
- A fresh-machine restore is a plain `git clone` to a **non-iCloud** path (e.g. `~/code/claude-config`), then run the restore steps — the clone won't carry the separate-git-dir indirection.

### Editing from another machine

The `.git` pointer is a file *inside* the working tree, so iCloud syncs it to every machine — but each machine would need it to name a *different* local git-dir path. One synced file can't hold two values, so git only works on this Mac. Don't try to run git on a second machine; it would rewrite the synced pointer and break this Mac too.

The working flow — **edit anywhere, commit only here**:

1. Edit freely in Obsidian on the other machine. iCloud syncs the markdown back to this Mac.
2. On this Mac, wait for iCloud to pull those edits (confirm the changes are present in the files).
3. Commit/push from here as normal (`git add <files by name>` → commit → push).

Git here is for versioning + backup, not commit-where-you-edited. If committing from another machine ever becomes a real need, the fix is to drop git from the vault and `git clone` the GitHub repo to a normal `~/code/claude-config` per machine — at the cost of the single-copy "edit in Obsidian = edit the repo" workflow.

## Committing (user rules — enforced by the git-commit-guard hook)

- **Stage by name, never `git add -A` / `git add .`.**
- **Never commit secrets.** None live here by design — the Telegram token etc. live in `~/.config/claude-secrets.env` and env vars. Files reference them only as `${ENV_VAR}` placeholders.
- Don't commit/push without an explicit authorizing word (`commit | push | ship | deploy | merge | pr`) in the user's recent message. Conventional Commits format.

## File map

- `00-identity.md … 04-claude-settings.md` — source docs (numbered = suggested read order).
- `SYSTEM.md` — paste-ready compilation of `00`–`04`. **If you edit a `0X` file, re-sync `SYSTEM.md`.**
- `README.md` — human-facing overview of the dump.
- `claude-config/settings.json` → restores to `~/.claude/settings.json`.
- `claude-config/hooks/git-commit-guard.sh` → restores to `~/.claude/hooks/`.
- `skills/scheme/SKILL.md` → restores to `~/.claude/skills/scheme/`.
- Restore instructions live in `03-hooks.md` and `04-claude-settings.md`.
