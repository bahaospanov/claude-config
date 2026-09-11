#!/usr/bin/env python3
"""PreToolUse gate on setting a merge-request / pull-request description.

Deterministic because every rule here is syntax: heading form, label vocabulary,
column-0 body, reviewer pre-answers. Taste stays with the judge. Fails open.
"""

import json
import os
import re
import sys

LABELS = ("Symptom", "Cause", "Measured", "Scope", "Constraint", "Cost",
          "Verified", "Remaining")

SETS_DESC = re.compile(
    r"--form\s+['\"]?description=|(?<![\w.])-F\s+['\"]?description=|"
    r"merge_request\.description=|--description[= ]|--body[= ]|"
    r"\.description\s*=", re.I)

FROM_FILE = re.compile(r"--form\s+['\"]?description=<([^'\"\s]+)")
FROM_FORM = re.compile(r"--form\s+(['\"])description=(.*?)\1", re.S)
FROM_OPT = re.compile(r"merge_request\.description=(['\"])(.*?)\1", re.S)
FROM_FLAG = re.compile(r"--(?:description|body)[= ]\s*(['\"])(.*?)\1", re.S)

HEADING = re.compile(r"^###\s+(\w+)")
BARE_LABEL = re.compile(r"^(%s)\b" % "|".join(LABELS))
PREEMPT = re.compile(
    r"\b(no|not?)\s+(\w+\s+){0,2}(change[sd]?|touched|affected|impact)\b"
    r"|\bnothing (else )?(changed|touched|moved)\b", re.I)


def read_ref(path):
    """`description=<file` given to curl. The hook sees the command unexpanded,
    so $VARS are unresolvable - fail open rather than judge the literal."""
    path = os.path.expandvars(path.strip())
    if "$" in path or not os.path.isfile(path):
        return None
    try:
        return open(path).read()
    except OSError:
        return None


def description_from(cmd):
    m = FROM_FILE.search(cmd)
    if m:
        return read_ref(m.group(1))
    for pat in (FROM_FORM, FROM_OPT, FROM_FLAG):
        m = pat.search(cmd)
        if m:
            value = m.group(2)
            return read_ref(value[1:]) if value.startswith("<") else value
    return None


def violations(text):
    lines = text.splitlines()
    out, seen_heading, fenced = [], False, False
    unlabelled, indented, bad_labels = [], [], []

    for line in lines:
        if line.strip().startswith("```"):
            fenced = not fenced
            continue
        if fenced or not line.strip():
            continue
        h = HEADING.match(line)
        if h:
            seen_heading = True
            if h.group(1) not in LABELS:
                bad_labels.append(h.group(1))
            continue
        if BARE_LABEL.match(line):
            bad_labels.append(line.strip())
            continue
        if not seen_heading:
            unlabelled.append(line.strip())
        elif line.startswith(" "):
            indented.append(line.strip())

    if bad_labels:
        out.append("labels must be `### Name` from: " + ", ".join(LABELS) +
                   "\n      got: " + "; ".join(b[:40] for b in bad_labels[:3]))
    elif not seen_heading and [l for l in lines if l.strip()]:
        out.append("no `### Label` headings. Use only the blocks that apply: " +
                   ", ".join(LABELS))
    if unlabelled:
        out.append("prose before any heading:\n      " + unlabelled[0][:80])
    if indented:
        out.append("body indented — renders as one run-on paragraph, structure "
                   "vanishes. Start at column 0; transcripts go in ``` fences:"
                   "\n      " + indented[0][:80])
    hits = [l for l in lines if PREEMPT.search(l)]
    if hits:
        out.append("pre-answers a reviewer:\n      " + hits[0].strip()[:80])
    return out


def main():
    cmd = (json.load(sys.stdin).get("tool_input") or {}).get("command") or ""
    if not SETS_DESC.search(cmd):
        return
    text = description_from(cmd)
    if not text or not text.strip():
        return
    found = violations(text)
    if not found:
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "mr-description-guard:\n  - " +
                                    "\n  - ".join(found)}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
