#!/usr/bin/env python3
"""`claim` (PreToolUse) records a worktree HEAD and its existing comments the
first time a tool touches it; `check` (Stop) diffs against that. Sourced from
git diff, not tool calls, because the PostToolUse guard cannot see edits made
through Bash. Only claimed worktrees are ever read. Fails open.
"""

import hashlib
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comment_rules import (  # noqa: E402
    ADD_LIMIT, DOC_ASK, DOC_BLOCK, DOC_EXT, DOC_FLOOR, DOC_RATIO, KEEP, OUTRANKS,
    docstring_lines, prefixes,
)

STATE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "state")
MAX_BLOCKS = 2


def git(cwd, *args):
    out = subprocess.run(("git", "-C", cwd) + args, capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def worktrees(cwd):
    root = git(cwd, "rev-parse", "--show-toplevel")
    if not root:
        return []
    listing = git(root, "worktree", "list", "--porcelain") or ""
    return [l.split(" ", 1)[1] for l in listing.splitlines() if l.startswith("worktree ")]


def state_path(session):
    os.makedirs(STATE_DIR, exist_ok=True)
    safe = "".join(c for c in session if c.isalnum() or c in "-_")[:64]
    return os.path.join(STATE_DIR, f"comment-diff-{safe}.json")


def load(session):
    try:
        with open(state_path(session)) as fh:
            return json.load(fh)
    except Exception:
        return {"owned": {}, "reported": [], "blocks": 0}


def save(session, data):
    with open(state_path(session), "w") as fh:
        json.dump(data, fh)


def known_worktrees(data, cwd, session):
    cached = data.get("worktrees")
    if cached is not None:
        return cached
    found = worktrees(cwd)
    data["worktrees"] = found
    save(session, data)
    return found


def do_claim(data, payload, cwd, session):
    ti = payload.get("tool_input") or {}
    blob = " ".join(str(ti[k]) for k in ("command", "file_path", "notebook_path")
                    if ti.get(k))
    if not blob:
        return
    known = known_worktrees(data, cwd, session)
    hits = [wt for wt in known if wt in blob]
    hits = [wt for wt in hits
            if not any(other != wt and other.startswith(wt) for other in hits)]

    owned = data.setdefault("owned", {})
    dirty = False
    for wt in hits:
        if owned.get(wt, {}).get("head"):
            continue
        head = git(wt, "rev-parse", "HEAD")
        if not head:
            continue
        owned[wt] = {"head": head,
                     "baseline": [[p, l]
                                  for p, lines in added_comments(wt, "HEAD").items()
                                  for l in lines]}
        dirty = True
    if dirty:
        save(session, data)


def untracked_comments(wt, found):
    listing = git(wt, "ls-files", "--others", "--exclude-standard") or ""
    for rel in listing.splitlines():
        marks = prefixes(rel)
        if not marks:
            continue
        full = os.path.join(wt, rel)
        try:
            if os.path.getsize(full) > 512_000:
                continue
            with open(full, encoding="utf-8", errors="replace") as fh:
                body = fh.read()
        except OSError:
            continue
        lines = [l.strip() for l in body.splitlines()]
        docs = docstring_lines(lines, rel)
        for i, stripped in enumerate(lines):
            if stripped.startswith("#!"):
                continue
            if not stripped.startswith(marks) and i not in docs:
                continue
            found.setdefault(rel, []).append(stripped)
    return found


def added_comments(wt, base):
    found = {}
    diff = git(wt, "diff", "--unified=0", base)
    if not diff:
        return untracked_comments(wt, found)
    path, marks = None, None
    added = {}
    for line in diff.splitlines():
        if line.startswith("+++ "):
            raw = line[4:].strip()
            path = None if raw == "/dev/null" else raw[2:]
            marks = prefixes(path) if path else None
            continue
        if not path or not marks or not line.startswith("+") or line.startswith("+++"):
            continue
        body = line[1:].strip()
        if body.startswith("#!"):
            continue
        added.setdefault(path, []).append(body)
    for path, bodies in added.items():
        marks = prefixes(path)
        docs = docstring_lines(bodies, path)
        for i, body in enumerate(bodies):
            if body.startswith(marks) or i in docs:
                found.setdefault(path, []).append(body)
    return untracked_comments(wt, found)


def doc_budget(wt, base):
    diff = git(wt, "diff", "--unified=0", base)
    per_doc, code, new_docs, path, is_new = {}, 0, [], None, False
    for line in (diff or "").splitlines():
        if line.startswith("--- "):
            is_new = line[4:].strip() == "/dev/null"
            continue
        if line.startswith("+++ "):
            raw = line[4:].strip()
            path = None if raw == "/dev/null" else raw[2:]
            if path and is_new and os.path.splitext(path)[1].lower() in DOC_EXT:
                new_docs.append(path)
            continue
        if not path or not line.startswith("+") or line.startswith("+++"):
            continue
        body = line[1:].strip()
        if not body:
            continue
        if os.path.splitext(path)[1].lower() in DOC_EXT:
            per_doc[path] = per_doc.get(path, 0) + 1
            continue
        marks = prefixes(path)
        if not marks or not body.startswith(marks):
            code += 1

    listing = git(wt, "ls-files", "--others", "--exclude-standard") or ""
    for rel in listing.splitlines():
        if os.path.splitext(rel)[1].lower() not in DOC_EXT:
            continue
        new_docs.append(rel)
        try:
            with open(os.path.join(wt, rel), encoding="utf-8", errors="replace") as fh:
                per_doc[rel] = per_doc.get(rel, 0) + sum(1 for line in fh if line.strip())
        except OSError:
            pass
    return per_doc, code, new_docs


TOKEN = re.compile(r"`([^`\n]{3,60})`")


def duplication_hints(wt, base):
    diff = git(wt, "diff", "--unified=0", base)
    hints, path = [], None
    for line in (diff or "").splitlines():
        if line.startswith("+++ "):
            raw = line[4:].strip()
            path = None if raw == "/dev/null" else raw[2:]
            continue
        if not path or os.path.splitext(path)[1].lower() not in DOC_EXT:
            continue
        if not line.startswith("+") or line.startswith("+++"):
            continue
        toks = [t for t in TOKEN.findall(line[1:]) if " " not in t]
        if len(toks) < 2:
            continue
        sets = []
        for t in toks[:4]:
            out = git(wt, "grep", "-l", "-F", "--", t) or ""
            sets.append({f for f in out.splitlines()
                         if os.path.splitext(f)[1].lower() not in DOC_EXT})
        common = set.intersection(*sets) if sets else set()
        if common:
            hints.append((path, ", ".join(sorted(common)[:2]), toks[:3]))
    return hints


def do_gate(payload):
    ti = payload.get("tool_input") or {}
    path = ti.get("file_path") or ""
    if os.path.splitext(path)[1].lower() not in DOC_EXT:
        return None
    added = ti.get("new_string")
    if added is None:
        added = ti.get("content") or ""
    old = ti.get("old_string")
    if old is None:
        # A Write carries no old_string. Comparing against "" made every
        # whole-file rewrite look like pure addition, so a trim was gated
        # exactly like a new document. Compare against what is on disk.
        try:
            with open(path, encoding="utf-8") as fh:
                old = fh.read()
        except OSError:
            old = ""

    grew = (len([l for l in added.splitlines() if l.strip()]) >
            len([l for l in old.splitlines() if l.strip()]))
    if not grew:
        return None

    root = git(os.path.dirname(path) or ".", "rev-parse", "--show-toplevel")
    if not root:
        return None

    for line in added.splitlines():
        if line in old:
            continue
        toks = [t for t in TOKEN.findall(line) if " " not in t]
        if len(toks) < 2:
            continue
        sets = []
        for t in toks[:4]:
            out = git(root, "grep", "-l", "-F", "--", t) or ""
            sets.append({f for f in out.splitlines()
                         if os.path.splitext(f)[1].lower() not in DOC_EXT})
        common = set.intersection(*sets) if sets else set()
        if common:
            where = ", ".join(sorted(common)[:2])
            return (f"This line repeats {'/'.join(toks[:3])}, already stated in "
                    f"{where}:\n  {line.strip()[:160]}\n"
                    "A duplicated fact is a second copy to keep in sync, and it is "
                    "the copy that drifts and starts lying. Point at the source or "
                    "add nothing.")
    return None


def do_check(data, cwd, session):
    owned = data.get("owned") or {}
    if not owned:
        return None

    findings = []
    for wt, info in owned.items():
        base = info.get("head")
        if not base:
            continue
        was = {tuple(pair) for pair in info.get("baseline") or []}
        for path, lines in added_comments(wt, base).items():
            new = [l for l in lines if (path, l) not in was]
            if len(new) > ADD_LIMIT:
                findings.append((path, new))
    doc_notes = []
    for wt, info in owned.items():
        base = info.get("head")
        if not base:
            continue
        per_doc, code, new_docs = doc_budget(wt, base)
        for path, n in sorted(per_doc.items()):
            if path in new_docs:
                doc_notes.append(f"NEW document {path} ({n} lines)")
            elif n > DOC_BLOCK:
                doc_notes.append(f"{path} grew by {n} lines")
        for dpath, where, toks in duplication_hints(wt, base)[:4]:
            doc_notes.append(f"{dpath} repeats {'/'.join(toks)} - already stated "
                             f"in {where}; point at it instead of copying it")
        docs = sum(per_doc.values())
        if docs >= DOC_FLOOR and docs > DOC_RATIO * max(code, 1):
            doc_notes.append(f"{docs} lines of prose against {code} of code "
                             f"({docs / max(code, 1):.1f}:1)")

    if not findings and not doc_notes:
        return None

    digest = hashlib.sha1(
        json.dumps([sorted((p, l) for p, l in findings), sorted(doc_notes)]
                   ).encode()).hexdigest()
    if digest in data.get("reported", []) or data.get("blocks", 0) >= MAX_BLOCKS:
        return None
    data.setdefault("reported", []).append(digest)
    data["blocks"] = data.get("blocks", 0) + 1
    save(session, data)

    parts = []
    for path, lines in findings:
        shown = "\n".join(f"    {l}" for l in lines[:8])
        more = "" if len(lines) <= 8 else f"\n    ... +{len(lines) - 8} more"
        parts.append(f"  {path} - {len(lines)} added comment lines:\n{shown}{more}")
    out = []
    if parts:
        out.append(
            "comment-diff-guard: this turn's diff adds more comment lines than "
            f"the budget of {ADD_LIMIT} per file.\n\n" + "\n".join(parts) + "\n"
            f"{KEEP}")
    if doc_notes:
        out.append("comment-diff-guard: prose outweighs the change.\n  " +
                   "\n  ".join(doc_notes) + f"\n{DOC_ASK}")
    out.append(
        "This check reads git diff, so it sees edits made through Bash, sed and "
        f"heredocs that the per-edit hook never sees.\n{OUTRANKS}\n"
        "Cut what does not earn its place, then say what you kept and why.")
    return "\n\n".join(out)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    payload = json.load(sys.stdin)
    cwd = payload.get("cwd") or os.getcwd()
    session = payload.get("session_id") or "nosession"
    data = load(session)

    if mode == "claim":
        do_claim(data, payload, cwd, session)
        return

    if mode == "gate":
        reason = do_gate(payload)
        if reason:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason}}))
        return

    reason = do_check(data, cwd, session)
    if reason:
        print(json.dumps({"decision": "block", "reason": reason}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
