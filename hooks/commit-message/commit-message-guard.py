#!/usr/bin/env python3
"""PreToolUse gate on git commit: Conventional Commits prefix only.

Everything else about a message is taste, and taste is the judge hook's job -
a message-to-diff ratio flags a one-line fix that needed a paragraph and
passes a big refactor that needed none. Fails open.
"""

import json
import os
import re
import subprocess
import sys

INVOKED = re.compile(r"(?:\A|[;&|\n])\s*(?:cd\s+\S+\s*&&\s*)*git\s+c(?:ommit)\b")

CC = re.compile(r"^(feat|fix|chore|docs|refactor|test|perf|build|ci|style|revert)"
                r"(\([a-z0-9._/-]+\))?!?: .+")


def git(cwd, *args):
    out = subprocess.run(("git", "-C", cwd) + args, capture_output=True, text=True)
    return out.stdout if out.returncode == 0 else ""


def message_from(cmd):
    if "--no-edit" in cmd:
        return None
    here = re.search(r"-F\s*-\s*<<'?(\w+)'?\n(.*?)\n\1", cmd, re.S)
    if here:
        return here.group(2)
    dashm = re.search(r"-m\s+(['\"])(.*?)\1", cmd, re.S)
    if dashm:
        return dashm.group(2)
    fpath = re.search(r"-F\s+(\S+)", cmd)
    if fpath and os.path.isfile(fpath.group(1)):
        try:
            return open(fpath.group(1)).read()
        except OSError:
            return None
    return None


PREEMPT = re.compile(
    r"\b(no|not?)\s+(\w+\s+){0,2}(change[sd]?|touched|affected|impact)\b"
    r"|\bnothing (else )?(changed|touched|moved)\b"
    r"|\b(also|additionally|for completeness|worth noting)\b.*\bunchanged\b",
    re.I)


def violations(text):
    body = [l for l in text.strip().splitlines() if l.strip()]
    if not body:
        return []
    out = []
    if not CC.match(body[0]):
        out.append(f"first line is not Conventional Commits: {body[0][:70]!r}")
    hits = [l.strip() for l in body[1:] if PREEMPT.search(l)]
    if hits:
        out.append("pre-answers a reviewer instead of saying why:\n      " +
                   "\n      ".join(h[:90] for h in hits[:3]))

    return out


def main():
    payload = json.load(sys.stdin)
    cmd = (payload.get("tool_input") or {}).get("command") or ""
    cwd = payload.get("cwd") or os.getcwd()

    if not INVOKED.search(cmd):
        return
    text = message_from(cmd)
    if not text:
        return

    found = violations(text)
    if not found:
        return

    reason = "commit-message-guard: " + "; ".join(found)
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
