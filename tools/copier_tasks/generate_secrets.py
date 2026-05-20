#!/usr/bin/env python3
"""Replace __GENERATED_SECRET__ sentinels in .env.example with random values.

Run as a Copier `_tasks` hook from the rendered target directory. Each
occurrence of the sentinel is replaced with a distinct
secrets.token_urlsafe(32) value, so every distro gets per-instance secrets
even when the template ships the same sentinel for several variables.

Idempotent: if no sentinels are present (already replaced, or file
missing), the script is a no-op and exits cleanly.
"""
from __future__ import annotations

import re
import secrets
import sys
from pathlib import Path

SENTINEL = "__GENERATED_SECRET__"
TARGETS = (".env.example",)

# Only replace sentinels that appear as the complete VALUE on a KEY=VALUE
# line. Sentinels mentioned inside comments stay literal — they're
# self-documenting references like "if you see __GENERATED_SECRET__ here,
# the task didn't run". Matching the sentinel anywhere in the file would
# rewrite the documentation along with the actual placeholders.
LINE_RE = re.compile(rf"^([A-Z_][A-Z0-9_]*)={SENTINEL}\s*$", re.MULTILINE)


def replace_sentinels(path: Path) -> int:
    if not path.exists():
        return 0
    text = path.read_text(encoding="utf-8")
    if SENTINEL not in text:
        return 0
    new_text, count = LINE_RE.subn(
        lambda m: f"{m.group(1)}={secrets.token_urlsafe(32)}",
        text,
    )
    if count:
        path.write_text(new_text, encoding="utf-8")
    return count


def main() -> int:
    total = 0
    for name in TARGETS:
        total += replace_sentinels(Path(name))
    if total:
        print(f"generate_secrets: replaced {total} sentinel(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
