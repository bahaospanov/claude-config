"""Shared comment-classification rules.

Imported by comment-guard.py (PostToolUse, per-edit) and comment-diff-guard.py
(Stop, per-turn diff). One rulebook so the two cannot drift.
"""

import os

ADD_LIMIT = 3
CONTEXT = 15
MAX_DENSITY = 0.30
MIN_REGION_COMMENTS = 4
MAX_RUN = 5
DOC_RATIO = 2.0
DOC_FLOOR = 40
DOC_BLOCK = 2

SKIP_EXT = {".md", ".markdown", ".rst", ".txt", ".json", ".lock"}
DOC_EXT = {".md", ".markdown", ".rst"}

HASH_EXT = {
    ".sh", ".bash", ".zsh", ".fish", ".py", ".rb", ".pl", ".r",
    ".yml", ".yaml", ".toml", ".ini", ".cfg", ".conf", ".tf", ".tfvars",
    ".gitignore", ".dockerignore", ".env", ".example", ".properties",
}
HASH_BASE = {"dockerfile", "makefile", "justfile", "rakefile", "gemfile", "procfile"}

SLASH_EXT = {
    ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".go", ".java", ".c", ".h",
    ".cc", ".cpp", ".hpp", ".cs", ".rs", ".swift", ".kt", ".kts", ".scala",
    ".php", ".scss", ".less", ".css", ".dart", ".proto", ".gradle",
}
MARKUP_EXT = {".html", ".htm", ".vue", ".svelte", ".xml", ".svg"}
DASH_EXT = {".sql", ".lua", ".hs", ".elm"}

KEEP = (
    "Keep a comment that records a measured number, an observed behaviour, a "
    "named bug or version pin, a trap whose obvious cleanup would silently "
    "break something, or an invariant spanning processes - those are the ones "
    "this codebase is built on. Delete the ones that restate the code, narrate "
    "the change, or argue a decision; that reasoning belongs in the commit "
    "message, docs/decisions.md, or a runbook."
)

OUTRANKS = (
    "This outranks matching the file's existing comment density, and it "
    "outranks any skill or template instructing you to add a header or "
    "rationale block."
)


def prefixes(path):
    base = os.path.basename(path).lower()
    ext = os.path.splitext(base)[1]
    if ext in SKIP_EXT:
        return None
    if base.startswith("dockerfile") or base in HASH_BASE:
        return ("#",)
    out = []
    if ext in HASH_EXT:
        out.append("#")
    if ext in SLASH_EXT:
        out += ["//", "/*", "*/", "*"]
    if ext in MARKUP_EXT:
        out += ["<!--", "-->", "//", "/*", "*/", "*"]
    if ext in DASH_EXT:
        out.append("--")
    return tuple(out) or None


TRIPLE_EXT = {".py", ".pyi"}
_QUOTES = ('"""', "'''")


def docstring_lines(lines, path):
    # Only blocks whose opening line STARTS with the quote: `sql = """SELECT`
    # is a value, not prose. Counting docstrings as code both hid them from
    # the add-limit and diluted the density ratio they should have raised.
    if not path:
        return set()
    if os.path.splitext(os.path.basename(path).lower())[1] not in TRIPLE_EXT:
        return set()
    # An unterminated run stays unterminated to end-of-input, which in DIFF
    # mode swallows every later `+` line: the closing quote is unchanged
    # context, so it is not in the input at all. Only closed blocks count.
    out, quote, pending = set(), None, []
    for i, raw in enumerate(lines):
        line = raw.strip()
        if quote is None:
            opener = line.lstrip("rRfFbBuU")
            if not opener.startswith(_QUOTES):
                continue
            quote, pending = opener[:3], [i]
            if quote in opener[3:]:
                out.update(pending)
                quote = None
        else:
            pending.append(i)
            if quote in line:
                out.update(pending)
                quote = None
    if quote is not None:
        out.add(pending[0])
    return out


def classify(lines, marks, first_is_file_start, path=None):
    docs = docstring_lines(lines, path)
    comment, code = [], 0
    for i, raw in enumerate(lines):
        line = raw.strip()
        if not line:
            continue
        if first_is_file_start and i == 0 and line.startswith("#!"):
            continue
        if line.startswith(marks) or i in docs:
            comment.append(i)
        else:
            code += 1
    return comment, code


DOC_ASK = (
    "A document earns a file only if it stays useful AFTER the task is done.\n"
    "The test: could a human execute this in one sitting, with you guiding them "
    "live? Then it is a conversation, not a document - guide them and write "
    "nothing. Once the task is done such a page is dead weight: it clogs the "
    "repo and every future context window, and it rots because nobody runs it "
    "again to notice it is wrong.\n"
    "EARNS a file: something run repeatedly; something needed when you are NOT "
    "there (recovery, on-call, onboarding); a durable why that outlives the "
    "change.\n"
    "DOES NOT: a one-time cutover or migration you are about to run together; a "
    "narration of work just completed; a procedure whose only reader is the "
    "person you are already talking to.\n"
    "Second test, applied to every added line: does the code, a config file, or "
    "another page ALREADY say this? Prose that repeats a fact is worse than no "
    "prose - it is another copy to keep in sync, and it is the copy that will "
    "drift and start lying. Point at the existing source instead of restating "
    "it, or add nothing."
)
