#!/usr/bin/env python3
"""Configure the local Godot editor's Blender path without changing project settings."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot4'))
    parser.add_argument('--blender', default=shutil.which('blender'))
    args = parser.parse_args()
    if not args.blender:
        parser.error('Blender not found. Supply --blender /path/to/blender.')
    blender = str(Path(args.blender).resolve())
    subprocess.run([blender, '--version'], check=True, stdout=subprocess.DEVNULL)
    version = subprocess.check_output([args.godot, '--version'], text=True)
    match = re.match(r'(\d+\.\d+)\.', version)
    if not match:
        parser.error('Could not identify the Godot editor version.')
    config_dir = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'godot'
    config_dir.mkdir(parents=True, exist_ok=True)
    path = config_dir / ('editor_settings-' + match[1] + '.tres')
    text = path.read_text() if path.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    if '[resource]' not in text:
        parser.error('Unrecognized editor settings format; nothing changed.')
    key = 'filesystem/import/blender/blender_path'
    line = key + ' = ' + json.dumps(blender)
    if re.search(r'^' + re.escape(key) + r'\s*=', text, re.M):
        text = re.sub(r'^' + re.escape(key) + r'\s*=.*$', lambda _: line, text, flags=re.M)
    else:
        text = text.replace('[resource]', '[resource]\n' + line, 1)
    path.write_text(text)
    print('Configured Blender: ' + blender + ' in ' + str(path))


if __name__ == '__main__':
    main()
