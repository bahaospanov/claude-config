# Rules

Each rule has the same shape: the rule itself, then **Why** and **How to apply**. Follow the spirit, not just the letter — the *why* is there so you can judge edge cases.

---

## 1. Don't auto-run verification steps

**Why:** Tests, linters, formatters, typecheckers can be slow, noisy, or destructive (running migrations as a side effect, hitting external services). I'll ask when I want them.

**How to apply:** After applying code edits, stop. Don't run `npm test`, `pytest`, `ruff`, `mypy`, `eslint`, `prettier`, `tsc`, format-on-save scripts, etc. unless I explicitly asked. "Plan: Verify" sections are notes to me, not to-do items for you.

---

## 2. Parallel sessions → propose a worktree before editing

**Why:** Two agents writing into the same working tree race on the index and produce broken commits.

**How to apply:** If you see signs of another active session in the same repo (recent files modified outside your touch points, locked index, multiple agents running), propose a `git worktree` before editing.
---

## 3. Never commit secrets

**Why:** Obvious. Once a secret is in git history it's compromised.

**How to apply:** When staging, never run `git add -A` or `git add .` if `.env`, credential files, key files, or `secrets.*` are untracked. Stage by name. If I explicitly ask to commit something that looks like a credential file, push back once before doing it.

---

## 4. Keep `main` history linear; merge via PR only

**Why:** Linear history makes `git bisect`, `git log`, and incident retros sane. PR reviews give CI a chance to gate.

**How to apply:** Never push directly to `main`. Always: rebase your branch onto `origin/main` (or `origin/dev`), force-push-with-lease, then `gh pr create`. No `git merge` that creates a merge commit on `main`.

---

## 5. No destructive git operations without explicit ask

**Why:** `reset --hard`, `push --force`, `clean -f`, `branch -D`, `checkout .` can destroy work-in-progress. I'd rather resolve the underlying conflict than discard.

**How to apply:** If you find yourself reaching for a destructive git command, stop and ask. `--force-with-lease` is fine for the worktree-PR flow; raw `--force` is not.

---

## 6. Don't skip hooks (`--no-verify`, `--no-gpg-sign`)

**Why:** Hooks exist for a reason. Skipping them masks the underlying problem.

**How to apply:** If a pre-commit/pre-push hook fails, diagnose and fix. Never pass `--no-verify` or `--no-gpg-sign` to git unless I explicitly ask.

---

## 7. Confirm before risky/visible/irreversible actions

**Why:** Cost of pausing to confirm is low. Cost of an unwanted destructive or shared-state action (deleted branch, sent message, force-pushed main, dropped table) is high.

**How to apply:** Before any of these, transparently say what you're about to do and wait for go-ahead:
- Destructive: `rm -rf`, dropping tables, deleting branches, killing processes
- Hard-to-reverse: force-pushing, amending published commits, downgrading/removing packages
- Shared-state: pushing code, opening/closing/commenting on PRs/issues, sending Slack/email/Telegram, modifying CI
- Third-party uploads: pasting code to gists, diagram renderers, screenshot services

Authorization for one such action does not extend to others. "Yes, push" does not mean "yes, also open a PR and tag people."

---

## 8. Refresh and rebase onto the base branch *before* starting work

**Why:** If the base (the PR target, e.g. `origin/dev`) moved while you weren't looking, you discover the overlap as PR conflicts after the work is already done, squashed, and pushed — the expensive time to resolve it. Catching it up front is cheap.

**How to apply:** At the start of a task on an existing branch, `git fetch origin` and rebase onto the current base before editing — not after a PR shows conflicts. Confirm the real base (`gh pr view <n> --json baseRefName`; don't assume `main`). Watch for a stale remote base: `origin/dev` can lag far behind the local tip a branch was cut from — sanity-check with `git rev-list --count origin/<base>..HEAD` and `…HEAD..origin/<base>` before treating it as current. (Rule 4 still governs the force-push-with-lease + PR flow; Rule 5/7 still gate the push.)

---

## 9. "Push" means a new commit, never amend

**Why:** I want each shipped change to be its own commit on the branch. Amending or squashing rewrites history and forces a force-push — not what I want by default.

**How to apply:** When I say "push" (or "ship"), stage the changed files and make a **new** `git commit`, then `git push`. Only `git commit --amend` or squash when I explicitly say "amend" or "squash". This composes with Rule 7 — still wait for the explicit push/ship word before committing or pushing at all.
