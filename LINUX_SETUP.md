# Linux Mint development and play

## Open this checkout

The default project runs with **standard Godot 4.7.2**, without C# or Mono.
The locally downloaded Linux engine has been extracted to the ignored
`.local-tools/godot-4.7.2/` directory. From the project directory:

```bash
bash tools/linux_launch.sh editor
bash tools/linux_launch.sh play
```

For another checkout/machine, extract the official Godot 4.7.2 Linux archive,
make its executable runnable, and point the launcher at it:

```bash
GODOT_BIN=/absolute/path/to/Godot_v4.7.2-stable_linux.x86_64 bash tools/linux_launch.sh editor
```

Use the matching engine version initially; upgrading the engine is a separate
change. No system-wide Godot installation or Windows executable is required.

Blender **4.0.2** is installed here at `/usr/bin/blender`. Godot 4.7's local
editor settings have been configured to use it. Blender importing remains
enabled. To configure another machine (close Godot first):

```bash
python3 tools/configure_linux_editor.py --godot /absolute/path/to/godot --blender /usr/bin/blender
```

The helper preserves other editor settings. These are machine-local settings,
not paths committed to `project.godot`.

## Moving from Windows

- Copy the source project, including `.import` metadata and script `.uid` files.
  Keep `.godot`, `.local-tools`, `.dotnet`, `bin`, and `obj` machine-local.
  For a stale cache, close Godot and **rename** `.godot` as a backup outside the
  project before reopening. The migration did not delete the existing cache.
- Keep filenames and references exactly case-matched. The migration audit found
  no case collisions or incorrectly cased literal resource paths.
- Prefer an ext4 working copy on Mint. This checkout is on NTFS; the current
  mount permits execution, but NTFS does not provide all native Linux filesystem
  semantics. Avoid simultaneous editing/syncing from Windows and Linux.
- Save slots are separate from the project. Back up Windows
  `%APPDATA%\Godot\app_userdata\BunkerGame\` and copy desired `save_slot_*.json`
  files to `${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/BunkerGame/`.
  Preserve existing Linux saves before copying. Hardware preferences need not
  be copied; imported Direct3D preferences are normalized to Vulkan on Linux.
- Direct3D 12 is disabled in the Linux graphics menu. The launcher offers an
  OpenGL fallback (`bash tools/linux_launch.sh compatibility`), with reduced
  rendering features. Forward+ / Vulkan remains the normal renderer.

The archived vendor source packs under `assets/models/WIP` remain on disk.
Their `.gdignore` prevents automatic import of unused Unity/Unreal variants
with broken, author-specific Windows texture paths. Prepared gameplay assets
remain available. See `assets/models/WIP/SOURCE_ASSETS.md` for the art workflow.

## Optional C# / MCP tooling

The MCP addon, C# source, and `BunkerGame.csproj` are preserved. The standard
editor cannot acquire C# support merely by installing Mono: use the matching
**Godot .NET editor** plus a .NET SDK compatible with the project's `net8.0`
target. Official guidance: [Godot C# prerequisites](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html).

With Godot closed:

```bash
python3 tools/configure_mcp.py enable --godot /absolute/path/to/Godot_4.7.2_mono
```

The helper checks the editor version and .NET support, builds the C# assembly,
and only then enables the MCP plugin/autoload and C# project feature. Build or
NuGet failures leave the project configuration untouched. Extension package
versions in the existing C# project are still floating; the optional .NET build
has not been validated on this machine.

Return to the standard profile before standard-editor use or Linux export:

```bash
python3 tools/configure_mcp.py disable
```

These commands intentionally edit only the relevant project configuration.
The GdUnit editor addon remains enabled, but its invalid `Object` autoload was
removed. Existing custom smoke tests do not require GdUnit.

## Validation and export

```bash
bash tools/godot_check.sh /absolute/path/to/godot
```

This runs import, character-creation startup, world startup, and Windows-settings
migration checks. It uses temporary XDG directories so real saves and settings
are untouched, configures Blender in those temporary editor settings, and
fails on engine errors or nonzero exits. Logs are retained under `/tmp`.
It requires Bash, Python 3, `timeout`, Blender, and the selected Godot binary.

A `Linux` x86_64 export preset is included. It excludes development tools,
C# sources, .key/.pem files, vendor archives, and obsolete scratch scenes.
Install Godot's **matching 4.7.2 export templates** using the editor's
Manage Export Templates dialog, then:

```bash
mkdir -p builds/linux
/path/to/godot --headless --path . --export-release Linux
```

Distribute the executable together with its `.pck` file. A standalone release
binary requires the matching templates; a game-pack export can be tested with
the editor executable using `--main-pack /path/to/BunkerGame.pck`.

## Migration findings

- Standard-editor C# startup dependencies removed; cached-UID-only autoloads
  replaced with explicit portable resource paths.
- Script UID sidecars are no longer globally ignored by Git.
- Windows graphics preferences are validated on Linux; editor relaunch retains
  the project path and does not write overrides beside the shared editor binary.
- World startup fixes: water-tank shader constant syntax, deferred ceiling
  collider attachment, current Godot material specular property, and a stale
  WaterCase script UID.
- Two old `scenes/player/_test_adventurer_retarget*.tscn` scenes refer to a
  missing `_test_adventurer_retarget.gd`. They are preserved and excluded from
  release export; opening those obsolete probes still needs their original
  missing script. They are not game-entry scenes.

This is a migration validation, not a complete playthrough or performance test.

### Validation performed on this machine

| Check | Result |
| --- | --- |
| Godot 4.7.2 import with an empty `.godot` cache | Passed |
| Character creation and MainWorld startup | Passed, no engine/script errors |
| Windows Direct3D settings migration | Passed |
| Existing graphics-settings UI smoke test | Passed |
| Native Vulkan / Forward+ world run on AMD Radeon RX 580 | Passed, no engine/shader errors |
| Linux PCK export and boot outside the source checkout | Passed for character creation and MainWorld |
| Optional MCP profile transformation checks | Passed; .NET build not run |
| Standalone release executable | Not built; matching export templates are not installed |

The exported-pack file listing contains no WIP archives, MCP addon, or tool
scripts. The real graphics run was a short startup smoke test, not an extended
playthrough. Existing unrelated work was preserved and no commits were made.
