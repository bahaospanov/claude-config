# Plugins & skills — reinstall reference

> **Claude-Code-only appendix.** Other LLM agents don't have a plugin system — ignore this file there. The behavioral content I actually want is already in [[01-rules]] and [[00-identity]]. Hooks live in [[03-hooks]].

## Plugins to reinstall

## caveman

- **Marketplace:** `caveman` → `github:JuliusBrussee/caveman`
- **What:** terse-output mode (drops articles/filler), commit-message generator, code-review formatter, memory-file compressor. Plus a statusline.

## karpathy-skills

- **Marketplace:** `karpathy-skills` → `github:forrestchang/andrej-karpathy-skills`
- **What:** `karpathy-guidelines` skill — behavioral nudges to reduce common LLM coding mistakes (surgical changes, simplicity-first, surface assumptions, verifiable success criteria).

## mattpocock/skills

- **Source:** https://github.com/mattpocock/skills (not on the official marketplace — clone or fetch skills individually).
- **What:** Matt Pocock's curated set of skills (TypeScript-leaning). Pick the ones I want and drop them into `~/.claude/skills/<name>/SKILL.md`, or wire a custom marketplace if Claude Code supports a raw GitHub source for this repo.

## Custom skill — `scheme`

- **Source:** my own — full skill body checked into this dump at `skills/scheme/SKILL.md` (mirrors Claude Code's layout). To recreate on a new machine: `cp -r skills/scheme ~/.claude/skills/`.
- **Triggers:** `/scheme`, "show schematic", "diagram the change", "draw the flow", "visualize how new changes work".
- **What:** renders a compact ASCII schematic of recent or pending code changes — control flow, data flow, before/after deltas, and where the change lands.

See [[03-hooks]] for the `git-commit-guard` hook.
