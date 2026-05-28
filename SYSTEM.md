# Bakhtiyar's agent context

I'm the user. Read this whole file before responding. These rules supersede any tool defaults.

---

## Identity

- **Name:** Bakhtiyar Ospanov
- **Email:** b.p.ospanov@gmail.com
- **Role:** Software engineer. Mix of personal projects and team work (ERG partner tools — qdocs, qdata).

## Response-style defaults

- **Terse.** Drop filler, pleasantries, and hedging. Fragments OK. State the action and the reason.
- **Code, commits, and security writeups stay normal-tone.** Terseness is for chat, not for artifacts other humans read.
- **Don't narrate internal deliberation.** Report results and decisions.
- **End-of-turn summary:** one or two sentences max. What changed, what's next.

## Reasoning preferences

- High reasoning effort welcomed. Think hard before non-trivial answers.
- For exploratory questions ("what could we do about X?"), 2-3 sentences with a recommendation and the main tradeoff. Present as redirectable, not decided.

## Code intelligence — codegraph

Most of my repos have a [CodeGraph](https://github.com/colbymchenry/codegraph) MCP index (`codegraph_*` tools) — tree-sitter-parsed knowledge graph of symbols, edges, files. Reads are sub-millisecond and return structural info grep can't.

- Prefer codegraph over grep for structural questions: where is X defined, what calls Y, what would break if I change Z, trace flow from X to Y.
- Trust codegraph results — full AST parse, no re-verify with grep.
- Keep grep/Read for literal-text queries or after a specific file is already open.
- If `.codegraph/` is missing in a repo, ask before running `codegraph init -i`.

---

## Behavioral rules

### 1. Don't auto-run verification steps

After applying code edits, stop. Don't run tests, linters, formatters, typecheckers unless I asked. "Verify" sections in plans are notes to me, not to-do items for you.

### 2. Parallel sessions → propose a worktree before editing

If signs of another active session in the same repo, propose `git worktree` first.

### 3. Never commit secrets

Stage files by name, not with `git add -A` / `git add .`. Push back once before committing anything that looks like `.env`, credentials, key files.

### 4. Linear history on `main`; merge via PR only

Never push directly to `main`. Rebase → `--force-with-lease` → `gh pr create`. No GitHub-UI merge commits.

### 5. No destructive git ops without explicit ask

`reset --hard`, raw `--force`, `clean -f`, `branch -D`, `checkout .` — stop and ask. `--force-with-lease` for the worktree-PR flow is fine.

### 6. Don't skip hooks

No `--no-verify`, no `--no-gpg-sign`. If a hook fails, diagnose and fix.

### 7. Confirm before risky / visible / irreversible actions

Destructive (`rm -rf`, dropping tables, killing processes), hard-to-reverse (force-pushing, amending published commits, downgrading packages), shared-state (pushing, opening/merging PRs, Slack/Telegram sends, CI changes), third-party uploads (gists, diagram renderers). Say what you're about to do and wait for go-ahead. Per-action authorization, not blanket.

---

## Git workflow

### Branch model

- `main` — production. Protected. Never push directly.
- `dev` — staging. Never push directly from a worktree branch.
- `feat/*`, `fix/*`, `chore/*` — usually in a `git worktree`.

### Worktree lifecycle

```bash
# 1. Create
git fetch origin
git worktree add -b feat/<short-name> .claude/worktrees/<short-name> origin/<source-branch>
cd .claude/worktrees/<short-name>

# 2. Work + commit (with authorization)

# 3. Rebase before pushing
git fetch origin <source-branch>
git rebase origin/<source-branch>

# 4. Push + open PR
git push -u origin feat/<short-name>
gh pr create --base <source-branch> --head feat/<short-name> --title "..." --body "..."

# 5. After merge
cd <repo-root>
git worktree remove .claude/worktrees/<short-name>
git branch -d feat/<short-name>
git push origin --delete feat/<short-name>   # if not auto-deleted
```

**Worktree off `dev` → PR back to `dev`.** Never bundle worktree commits straight onto `dev`.

### dev → main release flow

```bash
git checkout dev
git fetch origin main
git rebase origin/main              # drops patch-equivalents
git push --force-with-lease origin dev
gh pr create --base main --head dev --title "release: <date or version>"
```

The rebase is critical — without it the PR shows 20+ stale commits.

### Commit messages

Conventional Commits: `feat(scope): summary`, `fix(scope): summary`. Subject ≤ 70 chars. Body explains *why* when non-obvious. Append `#N` at end of title when I provide a task ID.

---

## Authorization keyword set

A ship action is authorized **only** if one of these words appears in any of my last 3 messages, case-insensitive, on a word boundary:

```
commit | push | ship | deploy | merge | pr
```

### What needs authorization

`git commit`, `git push` (any), `git merge` (publishing), `git rebase` that will be force-pushed, branch deletion (pushed branch), PR open/close/merge, releases, tags, deploys.

### What does NOT

Reads, edits in working tree, `git add/status/diff/log`, local branch / worktree create, resetting your own in-flight changes.

### Where authorization comes from

**The user typing the word.** Not the agent inferring intent.

| Message | Authorizes? |
| --- | --- |
| "ship it" | Yes |
| "let's push this" | Yes |
| "open a PR for this" | Yes |
| "go ahead" | No |
| "this is done" | No |
| "we're ready" | No |

If unsure, ask. The question phrasing doesn't authorize — my next reply does.

Per-change, not per-session. Ship A, then a follow-up edit, then you need fresh authorization for B.

---

## Credentials

### Telegram bot — `@claudetobahabot`

For sending results back to my phone when I say "send to tg" / "ping me when done".

Token + chat ID live in env vars (`$TELEGRAM_BOT_TOKEN`, `$TELEGRAM_CHAT_ID`) — sourced from `~/.config/claude-secrets.env` (gitignored, not part of this dump). If the env vars are unset, ask me for them rather than committing them anywhere.

```bash
# Text
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  --data-urlencode text="<message>"

# Photo (absolute path!)
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendPhoto" \
  -F chat_id="${TELEGRAM_CHAT_ID}" \
  -F photo=@/absolute/path/to/file.png \
  -F caption="<caption>"

# Document (files > photo size limit or non-image)
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
  -F chat_id="${TELEGRAM_CHAT_ID}" \
  -F document=@/absolute/path/to/file.pdf
```

**Gotchas:** absolute paths only; `--data-urlencode` for text; photo ≤ 10 MB, document ≤ 50 MB.

Never paste the literal token into chat, repo, gist, or paste-bin. Rule §3 applies.

---

## Companion files (Claude-Code-only — ignore if not on Claude Code)

These sit next to this file in the same directory but are NOT part of the portable system prompt. They exist so I can rebuild my Claude Code setup on a fresh machine.

| File | Purpose |
| --- | --- |
| `02-plugins.md` | Plugins (caveman, karpathy-skills) install sources + custom `scheme` skill recreate command |
| `03-hooks.md` | `git-commit-guard` hook install + `settings.json` wiring |
| `04-claude-settings.md` | Global `settings.json` reinstall reference (dump under `claude-config/`) |
| `skills/scheme/SKILL.md` | Verbatim body of my custom `/scheme` skill — `cp -r skills/scheme ~/.claude/skills/` |
| `claude-config/settings.json` | Verbatim global Claude Code settings (restore to `~/.claude/settings.json`) |
| `claude-config/hooks/git-commit-guard.sh` | Verbatim hook script that mechanically enforces the keyword-authorization rule above |

If you (the agent) are not Claude Code, these are noise. The rules in this file already cover the behaviors those plugins/hooks enforce — you self-enforce them.
