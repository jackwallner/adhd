#!/usr/bin/env python3
"""Check English App Store listing text against the fleet's length targets."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
METADATA = ROOT / "fastlane" / "metadata" / "en-US"
LIMITS = {
    "name.txt": (24, 30),
    "subtitle.txt": (24, 30),
    "keywords.txt": (94, 100),
    "promotional_text.txt": (0, 170),
    "description.txt": (1, 4000),
}


def main() -> int:
    errors = []
    for filename, (minimum, maximum) in LIMITS.items():
        path = METADATA / filename
        value = path.read_text(encoding="utf-8").strip()
        count = len(value)
        print(f"{filename}: {count} characters")
        if not minimum <= count <= maximum:
            errors.append(f"{filename}: expected {minimum} to {maximum} characters, got {count}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
