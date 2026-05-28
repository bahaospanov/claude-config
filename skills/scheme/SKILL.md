---
name: scheme
description: Render a compact ASCII schematic of recent or pending code changes — control flow, data flow, before/after deltas, and where the change lands. Triggers when the user says "/scheme", "show schematic", "diagram the change", "draw the flow", or asks to visualize how new changes work.
---

# /scheme — schematic of code changes

Produce an ASCII schematic that lets the user see, at a glance, how a change behaves: which functions are touched, what flows through them, and what differs before vs. after.

## When to use

- User says `/scheme`, "schematic", "draw the flow", "diagram this", "show me how it works visually".
- Right after finishing a change set, when the user asks to summarize what was done.
- When the change spans multiple files/layers and prose alone is hard to follow.

## What to draw

Pick the smallest diagram that explains the change. Prefer one focused diagram over a sprawl.

Choose ONE primary view:

1. **Control flow** — entry point → branches → terminal states. Use when the change adds/removes a branch.
2. **Data flow** — input → transforms → output. Use when the change reshapes data.
3. **Before/After delta** — two short stacks side-by-side or stacked. Use when a single behavior toggled.
4. **Layer map** — UI → API → DB. Use when the change crosses layers.

Add a small "test coverage" block under the main diagram if tests were written, listing which test asserts which behavior.

## Format rules

- Pure ASCII (`┌─┐ │ └─┘ ▼ ◀ ▶ ●`). No emoji.
- Wrap in a fenced code block so the monospace renders correctly.
- Keep nodes ≤ ~40 chars wide.
- Mark new/changed nodes with `NEW` or `▲` in the gutter — make the diff legible.
- One arrow per transition; label arrows only when the label adds info (`→ 400`, `→ rpc:foo`).
- Annotate with file:line where it helps locate the change.
- If a change is trivially summarized in two lines of text, skip the diagram and say so. Don't draw boxes around nothing.

## Workflow

1. Identify the change scope: read the diff (`git diff`), the files the user is asking about, or the conversation context.
2. Pick the view (control / data / before-after / layer).
3. Draft the diagram. Highlight new/changed nodes.
4. Add a 2–4 line legend or "Before / After" caption underneath if non-obvious.
5. If tests were added, append a small test-coverage block mapping test names to behaviors asserted.
6. Keep the whole reply tight — schematic + 1-3 lines of explanation. No restating the diff in prose.

## Example

```
┌──────────────────┐
│ POST /settle     │
└────────┬─────────┘
         │
         ▼
┌──────────────────────┐
│ getUnclaimedItems()  │
│ ▲ skip line_total≤0  │ NEW
└──────┬───────────────┘
       │
   ┌───┴────┐
   ▼        ▼
 [400]   [200 settled]

Before: free item → 400 unclaimed
After : free item → skipped → 200
```
