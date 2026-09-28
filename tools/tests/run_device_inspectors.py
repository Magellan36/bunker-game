#!/usr/bin/env python3
"""Run UI/owner contracts in an isolated Godot project; never edit the game.

Copies real UI/owner source with explicit small simulation doubles, not the
game's assets, autoloads or solver. This is not a full gameplay/playtest claim.
Fixture extensions keep their test class_names out of the real editor cache.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tools/tests/device_inspector_fixtures"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--keep", action="store_true", help="keep isolated project for investigation")
    args = parser.parse_args()
    stage = Path(tempfile.mkdtemp(prefix="bunker-device-ui-"))
    try:
        for folder in ("scripts/ui/common", "scripts/ui/power", "scripts/ui/water", "scripts/ui/farming", "scenes/ui/common", "scenes/ui/power", "assets/ui/themes"):
            # Only the migrated UI dependency graph, not unrelated legacy files.
            for source in (ROOT / folder).glob("*"):
                if source.name not in SOURCE_NAMES:
                    continue
                target = stage / source.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
        for name in ("GeneratorObject", "BatteryBank", "BreakerBox", "UpgradedBreakerBox",
                "WireSegment", "WallWireAttachment", "WireRoute"):
            source = ROOT / f"scripts/world/power/{name}.gd"
            target = stage / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        risk_path = Path("scripts/player/medical/MedicalRiskRules.gd")
        (stage / risk_path).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / risk_path, stage / risk_path)
        shutil.copytree(ROOT / "assets/fonts", stage / "assets/fonts", dirs_exist_ok=True)
        core = stage / "scripts/core"
        core.mkdir(parents=True)
        for name in ("InputMode", "DebugOutput"):
            shutil.copy2(ROOT / f"scripts/core/{name}.gd", core / f"{name}.gd")
        for source in FIXTURES.glob("*.fixture"):
            shutil.copy2(source, stage / source.name.removesuffix(".fixture"))
        for arguments in (("--editor", "--import", "--quit"), ("res://Test.tscn",)):
            result = subprocess.run([args.godot, "--headless", "--path", str(stage), *arguments], text=True, capture_output=True, timeout=90)
            print(result.stdout, end="")
            print(result.stderr, end="")
            if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr:
                return 1
        return 0
    finally:
        if args.keep:
            print(f"Isolated test project: {stage}")
        else:
            shutil.rmtree(stage)


SOURCE_NAMES = {
    "BunkerDeviceInspector.gd", "BunkerInspectorLayout.gd", "BunkerInspectorWidgets.gd",
    "BunkerDesign.gd", "BunkerPanelStyle.gd", "BunkerControlTheme.gd", "BunkerSmoothProgressBar.gd",
    "UIMotion.gd", "UIPanelLayout.gd", "UIPanelLifecycle.gd", "UIButtonMotion.gd", "UIScrollMotion.gd", "UIFormat.gd", "UIKit.gd",
    "BunkerPriorityControl.gd", "BunkerSymbolTexture.gd", "UIProximityClose.gd",
    "UIFade.gd", "ControllerUINavigation.gd", "GeneratorInspectUI.gd",
    "BatteryInspectUI.gd", "BreakerInspectUI.gd", "PowerPriorityUI.gd",
    "WaterDispenserUI.gd", "WaterInfoUI.gd", "FarmingTrayUI.gd",
    "DeviceInspectPanel.tscn", "GeneratorInspectPanel.tscn", "BunkerRedesignTheme.tres",
    # Quiet design kit (docs/ui/QUIET_DESIGN_SYSTEM.md) used by the shell.
    "QuietControls.gd", "SwitchGlyph.gd", "FocusRail.gd", "SmoothScroll.gd",
    "BunkerUIComponents.gd", "BunkerInputHint.gd",
    # Owners borrow their panels through SharedUI (one instance per type).
    "SharedUI.gd",
}

if __name__ == "__main__":
    raise SystemExit(main())
