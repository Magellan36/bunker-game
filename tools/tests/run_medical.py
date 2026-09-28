#!/usr/bin/env python3
"""Real movement/medical source in an isolated project; only UI/input neighbours are doubled."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ['scripts/player/Player.gd', 'scripts/player/PlayerStats.gd',
           'scripts/player/PlayerExertion.gd', 'scripts/player/medical/MedicalCondition.gd',
           'scripts/player/medical/PlayerMedical.gd', 'scripts/player/medical/MedicalRiskRules.gd',
           'scripts/player/medical/ExertionFeedback.gd']

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--screenshot', help='Render the feedback fixture to this PNG with the desktop display')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='bunker-medical-') as tmp:
        stage = Path(tmp)
        for name in SOURCES:
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        for source in (ROOT / 'tools/tests/medical_fixtures').glob('*.fixture'):
            shutil.copy2(source, stage / source.name.removesuffix('.fixture'))
        env = dict(os.environ, XDG_DATA_HOME=str(stage/'userdata'), XDG_CONFIG_HOME=str(stage/'config'), XDG_CACHE_HOME=str(stage/'cache'))
        for flags in [('--editor', '--import', '--quit'), ('res://Test.tscn',)]:
            command = [args.godot, '--path', str(stage), *flags]
            if flags[0] == '--editor' or not args.screenshot:
                command.insert(1, '--headless')
            else:
                command += ['--', '--screenshot', args.screenshot]
            result = subprocess.run(command,
                                    capture_output=True, text=True, timeout=60, env=env)
            print(result.stdout, end='')
            print(result.stderr, end='')
            if result.returncode or 'SCRIPT ERROR' in result.stderr or 'ERROR:' in result.stderr:
                return 1
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
