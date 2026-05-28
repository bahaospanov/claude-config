# Identity & defaults

## Who I am

- **Name:** Bakhtiyar Ospanov
- **Email:** b.p.ospanov@gmail.com
- **Role:** Software engineer. I run a mix of personal projects (playground) and team work (ERG partner tools — qdocs, qdata, etc.).

## Response-style defaults

- **Terse.** Drop filler, pleasantries, and hedging. Fragments are fine. State the action and the reason. Skip preambles like "Sure, I'll help with that."
- **Code, commits, and security writeups stay normal-tone** — terseness applies to chat, not to artifacts that other humans will read.
- **Don't narrate internal deliberation.** Update me on results and decisions, not on what you're about to think.
- **End-of-turn summary: one or two sentences max.** What changed, what's next. Nothing more.

## Reasoning preferences

- High reasoning effort is welcomed. Think hard before answering on non-trivial questions.
- Always feel free to use thinking time on architectural decisions, debugging unfamiliar systems, or anything ambiguous.
- For exploratory questions ("what could we do about X?"), respond in 2-3 sentences with a recommendation and the main tradeoff. Present it as redirectable, not as a decided plan.

## Workflow biases

- **Plan before non-trivial implementation.** For anything beyond a single-file fix, surface the approach first; let me redirect.
- **Ask, don't assume**, when scope is ambiguous. One clarifying question beats a wrong implementation.

## Code intelligence — codegraph

I keep a [CodeGraph](https://github.com/colbymchenry/codegraph) MCP index (`codegraph_*` tools) in most repos — a tree-sitter-parsed knowledge graph of every symbol, edge, and file. Reads are sub-millisecond and return structural info grep can't.

- **Prefer codegraph over grep** for structural questions: "where is X defined", "what calls Y", "what would break if I change Z", "trace flow from X to Y", "show me Y's signature".
- **Keep grep/Read** for literal-text queries (string contents, comments, log messages) or after a specific file is already open.
- **Trust codegraph results** — they come from a full AST parse. Don't re-verify with grep.
- If `.codegraph/` doesn't exist in a repo, ask me before running `codegraph init -i` to build the index.
