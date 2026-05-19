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


def replace_sentinels(path: Path) -> int:
    if not path.exists():
        return 0
    text = path.read_text(encoding="utf-8")
    if SENTINEL not in text:
        return 0
    new_text, count = re.subn(
        re.escape(SENTINEL),
        lambda _m: secrets.token_urlsafe(32),
        text,
    )
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
