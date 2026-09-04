#!/usr/bin/env python3
"""Validate UI placeholder provenance and block AI-authored art in releases."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
PLACEHOLDER_DIR = ROOT / "assets/ui/placeholders/redesign"
MANIFEST_PATH = PLACEHOLDER_DIR / "manifest.json"
SEARCH_SUFFIXES = {".gd", ".tscn", ".tres", ".res", ".json", ".md"}


def res_to_path(resource_path: str) -> Path:
    if not resource_path.startswith("res://"):
        raise ValueError(f"not a res:// path: {resource_path}")
    return ROOT / resource_path.removeprefix("res://")


def find_references(token: str) -> list[str]:
    references: list[str] = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix not in SEARCH_SUFFIXES:
            continue
        if PLACEHOLDER_DIR in path.parents:
            continue
        try:
            if token in path.read_text(encoding="utf-8", errors="ignore"):
                references.append(path.relative_to(ROOT).as_posix())
        except OSError:
            continue
    return references


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", action="store_true", help="fail while any AI placeholder or reference remains")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    listed = {entry["path"] for entry in manifest["assets"]}
    discovered = {
        "res://" + path.relative_to(ROOT).as_posix()
        for path in PLACEHOLDER_DIR.glob("*_AI_PLACEHOLDER.*")
    }
    errors: list[str] = []
    errors.extend(f"manifest entry is missing on disk: {path}" for path in sorted(listed) if not res_to_path(path).is_file())
    errors.extend(f"untracked placeholder file: {path}" for path in sorted(discovered - listed))

    references = {path: find_references(Path(path).name) for path in sorted(listed)}
    if args.release:
        errors.extend(f"release-blocking AI placeholder remains: {path}" for path in sorted(discovered))
        for path, refs in references.items():
            errors.extend(f"release-blocking reference to {path}: {ref}" for ref in refs)

    if errors:
        print("UI placeholder check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"UI placeholder check passed ({len(discovered)} tracked development placeholders).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
