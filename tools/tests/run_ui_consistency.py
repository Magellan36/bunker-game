#!/usr/bin/env python3
"""Run shared UI consistency contracts in a minimal Godot 4.7 project."""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
COMMON = ROOT / "scripts/ui/common"
SOURCES = (
    "BunkerSmoothProgressBar.gd",
    "UIFade.gd",
    "UIMotion.gd",
    "UIPanelLayout.gd",
    "UIPanelLifecycle.gd",
    "UIPreviewMotion.gd",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--keep", action="store_true")
    args = parser.parse_args()
    stage = Path(tempfile.mkdtemp(prefix="bunker-ui-consistency-"))
    try:
        common_target = stage / "scripts/ui/common"
        common_target.mkdir(parents=True)
        for name in SOURCES:
            shutil.copy2(COMMON / name, common_target / name)
        shutil.copy2(ROOT / "tools/tests/ui_consistency_foundations.gd", stage / "Test.gd")
        (stage / "project.godot").write_text(
            '[application]\nconfig/name="Bunker UI Consistency Contracts"\n'
            '[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n',
            encoding="utf-8",
        )
        for arguments in (("--editor", "--import", "--quit"), ("--script", "res://Test.gd")):
            result = subprocess.run(
                [args.godot, "--headless", "--path", str(stage), *arguments],
                text=True,
                capture_output=True,
                timeout=60,
            )
            print(result.stdout, end="")
            print(result.stderr, end="")
            if result.returncode or "SCRIPT ERROR" in result.stderr or "Parse Error" in result.stderr:
                return 1
        return 0
    finally:
        if args.keep:
            print(f"Isolated test project: {stage}")
        else:
            shutil.rmtree(stage)


if __name__ == "__main__":
    raise SystemExit(main())
