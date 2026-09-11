#!/usr/bin/env python3
"""PostToolUse guard on Write|Edit. Two signals, both deterministic.

ADDED: comment-only lines this edit introduced, over ADD_LIMIT.
DENSITY: comment density of the region the edit landed in (changed hunk plus
CONTEXT lines either side), over MAX_DENSITY. This one is the blast radius -
it counts comments that were already there, so editing inside a rationale
block obliges pruning it whether or not this edit added anything.

Fails open: any error exits 0 silently.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comment_rules import (  # noqa: E402
    ADD_LIMIT, CONTEXT, MAX_DENSITY, MIN_REGION_COMMENTS, MAX_RUN,
    KEEP, OUTRANKS, prefixes, classify,
)

def added_signal(text, marks, path):
    comment, _ = classify(text.splitlines(), marks, True, path)
    n = len(comment)
    if n <= ADD_LIMIT:
        return None
    return f"This edit adds {n} comment-only lines (soft limit {ADD_LIMIT})."


def density_signal(path, text, marks):
    with open(path, encoding="utf-8", errors="replace") as fh:
        body = fh.read()
    lines = body.splitlines()

    idx = body.find(text)
    if idx < 0:
        return None
    start = body.count("\n", 0, idx)
    end = start + text.count("\n")

    lo = max(0, start - CONTEXT)
    hi = min(len(lines), end + CONTEXT + 1)
    region = lines[lo:hi]

    comment, code = classify(region, marks, lo == 0, path)
    total = len(comment) + code
    if total == 0:
        return None

    run = run_start = best = best_start = 0
    prev = None
    for i in comment:
        if prev is not None and i == prev + 1:
            run += 1
        else:
            run, run_start = 1, i
        if run > best:
            best, best_start = run, run_start
        prev = i

    density = len(comment) / total
    dense = len(comment) >= MIN_REGION_COMMENTS and density > MAX_DENSITY
    blocky = best >= MAX_RUN
    if not (dense or blocky):
        return None

    where = f"{path}:{lo + 1}-{hi}"
    if blocky:
        what = (f"a {best}-line comment block at line {lo + best_start + 1} "
                f"(region is {round(density * 100)}% comment)")
    else:
        what = (f"{round(density * 100)}% comment - {len(comment)} comment lines "
                f"against {code} of code")
    return (
        f"The region you edited ({where}) carries {what}. Every comment in that "
        f"range is in scope, including the ones you did not write: editing here "
        f"is what puts them in your blast radius."
    )


def main():
    data = json.load(sys.stdin)
    tool_input = data.get("tool_input") or {}
    path = tool_input.get("file_path") or ""
    text = tool_input.get("new_string")
    if text is None:
        text = tool_input.get("content")
    if not path or not text:
        return

    marks = prefixes(path)
    if marks is None:
        return

    findings = [s for s in (added_signal(text, marks, path),
                            density_signal(path, text, marks)) if s]
    if not findings:
        return

    name = os.path.basename(path)
    body = "\n".join(f"- {s}" for s in findings)
    guidance = (
        f"comment-guard on {name}:\n{body}\n\n"
        "CLAUDE.md: 'Do not write comments by default. Default is no comment.'\n"
        f"{KEEP}\n"
        f"{OUTRANKS}\n"
        "Prune, then say in your reply which comments you kept and why."
    )
    print(json.dumps({
        "systemMessage": f"comment-guard: {len(findings)} signal(s) on {name}",
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": guidance,
        },
    }))


try:
    main()
except Exception:
    pass
sys.exit(0)
