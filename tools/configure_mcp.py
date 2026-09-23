#!/usr/bin/env python3
"""Opt into/out of C# editor tooling. Close Godot before running this tool."""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = 'res://addons/godot_mcp/plugin.cfg'
AUTOLOAD = 'McpRuntimeInit="*res://scripts/core/McpRuntimeInit.cs"'


def configure(text, enabled):
    pattern = r'(\[editor_plugins\]\s*enabled=PackedStringArray\()(.*?)(\))'
    match = re.search(pattern, text, re.S)
    if not match:
        raise ValueError('Cannot locate editor_plugins/enabled; project was not changed.')
    plugins = re.findall(r'"([^"]+)"', match[2])
    plugins = [p for p in plugins if p != PLUGIN]
    if enabled:
        plugins.append(PLUGIN)
    text = text[:match.start(2)] + ', '.join('"' + p + '"' for p in plugins) + text[match.end(2):]
    text = re.sub(r'^McpRuntimeInit=.*\n', '', text, flags=re.M)
    if enabled:
        if '[autoload]\n' not in text:
            raise ValueError('Cannot locate autoload section; project was not changed.')
        text = text.replace('[autoload]\n', '[autoload]\n' + AUTOLOAD + '\n', 1)
    match = re.search(r'config/features=PackedStringArray\((.*?)\)', text)
    if not match:
        raise ValueError('Cannot locate config/features; project was not changed.')
    features = [f for f in re.findall(r'"([^"]+)"', match[1]) if f != 'C#']
    if enabled:
        features.insert(1, 'C#')
    return text[:match.start(1)] + ', '.join('"' + f + '"' for f in features) + text[match.end(1):]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['enable', 'disable'])
    parser.add_argument('--godot', help='Path to the matching Godot .NET Linux executable (enable only)')
    args = parser.parse_args()
    path = ROOT / 'project.godot'
    original = path.read_text()
    updated = configure(original, args.mode == 'enable')
    if args.mode == 'enable':
        if not args.godot or not shutil.which(args.godot):
            sys.exit('Enable requires --godot /path/to/Godot_4.7.2_mono executable.')
        version = subprocess.check_output([args.godot, '--version'], text=True).strip()
        if not version.startswith('4.7.2.') or '.mono.' not in version:
            sys.exit('Expected Godot 4.7.2 .NET; found: ' + version)
        if not shutil.which('dotnet'):
            sys.exit('Install the .NET SDK (net8.0 compatible) before enabling MCP.')
        subprocess.run(['dotnet', 'build', str(ROOT / 'BunkerGame.csproj')], cwd=ROOT, check=True)
    if path.read_text() != original:
        sys.exit('project.godot changed during configuration; close Godot and retry.')
    path.write_text(updated)
    print('MCP ' + args.mode + 'd. Open with ' + ('Godot .NET.' if args.mode == 'enable' else 'standard Godot.'))


if __name__ == '__main__':
    main()
