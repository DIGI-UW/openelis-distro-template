#!/usr/bin/env python3
"""Materialize configs/analyzer-profiles/.active/ from core/ + distro/.

Run as a Copier `_tasks` hook from the rendered target directory after
generation. Walks `core/<protocol>/*.json` and copies each file into
`.active/<protocol>/`, then walks `distro/<protocol>/*.json` and copies
(overwriting on collision). Same logic is in
tools/contextualize/oe_context.py so the operator can re-merge after
editing without invoking copier.

Stdlib only — copier post-generate must run on a host that has only
copier and python3 installed.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

ROOT = Path("configs/analyzer-profiles")
SOURCES = ("core", "distro")
ACTIVE = ROOT / ".active"


def main() -> int:
    if not ROOT.exists():
        # Nothing to merge; not an error during initial generation in CI
        # environments that point copier at a stripped-down template fixture.
        return 0

    if ACTIVE.exists():
        shutil.rmtree(ACTIVE)
    ACTIVE.mkdir(parents=True)

    copied = 0
    overridden = 0
    for source in SOURCES:
        source_dir = ROOT / source
        if not source_dir.exists():
            continue
        for src in source_dir.rglob("*.json"):
            rel = src.relative_to(source_dir)
            dest = ACTIVE / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.exists():
                overridden += 1
            else:
                copied += 1
            shutil.copy2(src, dest)
    if copied or overridden:
        print(
            f"merge_profiles: {copied} copied, {overridden} overridden "
            f"(distro/ wins)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
