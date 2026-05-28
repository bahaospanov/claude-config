# LLM agent context — Bakhtiyar Ospanov

Tool-agnostic dump of identity, rules, workflow, and credentials. Any LLM coding agent (Claude Code, Codex, Gemini CLI, Cursor, Aider, etc.) can be bootstrapped from this directory.

## How to use

**Quick path:** paste [[SYSTEM]] into the agent's system prompt or instructions slot (`AGENTS.md`, `GEMINI.md`, `CLAUDE.md`, custom-instructions field, etc.).

**Detailed path:** point the agent at this directory and tell it to read every file. The numbered prefix is the suggested read order.

## Files

| File                   | Purpose                                                                                                                |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| [[00-identity]]        | Who I am, response-style defaults, date interpretation                                                                 |
| [[01-rules]]           | 7 distilled behavioral rules (the "don'ts" and "always") with reasons — full 14 live in [[SYSTEM]]                     |
| [[02-plugins]]         | Claude-Code-only — plugins (caveman, karpathy, mattpocock/skills) + custom skill (scheme, body under `skills/scheme/`) |
| [[03-hooks]]           | Claude-Code-only — `git-commit-guard` hook (script under `claude-config/hooks/`)                                       |
| [[04-claude-settings]] | Claude-Code-only — global `settings.json` dump (under `claude-config/`)                                                |
| [[SYSTEM]]             | Single-file paste-ready compilation of 00–04                                                                           |

## Updating this dump

When a new rule emerges in conversation, add it to [[01-rules]] (or the relevant file) and re-compile [[SYSTEM]] by concatenating 00–04 with their headings. Keep [[SYSTEM]] under ~5k tokens.
