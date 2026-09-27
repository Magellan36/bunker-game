#!/usr/bin/env python3
"""Run UI screen smoke scripts without the optional C# editor bridge."""
from __future__ import annotations

import argparse
from pathlib import Path
import os
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TESTS = (
    "graphics_settings_ui_smoke.gd",
    "ui_rehaul_smoke.gd",
    "status_screen_ui_smoke.gd",
    "npc_menu_ui_smoke.gd",
    "power_terminal_ui_smoke.gd",
    "research_station_ui_smoke.gd",
    "zone_customize_ui_smoke.gd",
)


def _project_text() -> str:
    return """[application]
config/name="Bunker UI Screen Smokes"

[autoload]
CharacterCreationData="*res://scripts/core/CharacterCreationData.gd"
FocusMode="*res://scripts/core/FocusMode.gd"
InputMode="*res://scripts/core/InputMode.gd"
WorldManager="*res://scripts/world/core/WorldManager.gd"
SaveManager="*res://scripts/world/core/SaveManager.gd"
DeviceDatabase="*res://scripts/world/power/DeviceDatabase.gd"
GraphicsSettings="*res://scripts/core/GraphicsSettings.gd"
NotificationManager="*res://scripts/ui/notifications/NotificationManager.gd"
JobBoard="*res://scripts/npc/JobBoard.gd"

[display]
window/size/viewport_width=1920
window/size/viewport_height=1080

[rendering]
renderer/rendering_method="gl_compatibility"
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("tests", nargs="*", default=list(DEFAULT_TESTS))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="bunker-ui-smokes-") as stage_value:
        stage = Path(stage_value)
        for child in ROOT.iterdir():
            if child.name in {"project.godot", ".git", ".godot"}:
                continue
            os.symlink(child, stage / child.name, target_is_directory=child.is_dir())
        (stage / "project.godot").write_text(_project_text(), encoding="utf-8")
        imported = subprocess.run(
            [args.godot, "--headless", "--path", str(stage), "--editor", "--import", "--quit"],
            text=True,
            capture_output=True,
            timeout=60,
        )
        if imported.returncode or "SCRIPT ERROR" in imported.stderr or "Parse Error" in imported.stderr:
            print(imported.stdout, end="")
            print(imported.stderr, end="")
            print("screen smoke project import: FAIL")
            return 1
        for test_name in args.tests:
            script_path = f"res://tools/tests/{Path(test_name).name}"
            try:
                result = subprocess.run(
                    [args.godot, "--headless", "--path", str(stage),
                     "--resolution", "1920x1080", "--script", script_path],
                    text=True,
                    capture_output=True,
                    timeout=60,
                )
            except subprocess.TimeoutExpired as error:
                if error.stdout:
                    print(error.stdout.decode() if isinstance(error.stdout, bytes) else error.stdout, end="")
                if error.stderr:
                    print(error.stderr.decode() if isinstance(error.stderr, bytes) else error.stderr, end="")
                print(f"{test_name}: TIMEOUT")
                return 1
            print(result.stdout, end="")
            print(result.stderr, end="")
            if result.returncode or "SCRIPT ERROR" in result.stderr or "Parse Error" in result.stderr:
                print(f"{test_name}: FAIL ({result.returncode})")
                return 1
            print(f"{test_name}: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
