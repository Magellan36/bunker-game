# UI capture tools

Live-render screenshots for the Quiet UI passes (`plans/ui-quiet-redesign-plan.md`).
The headless smoke tests prove structure; these prove the look.

| Script | Captures |
|---|---|
| `capture_scene.gd` | Any scene at chosen times, with optional scripted actions; `CAPTURE_VIEWPORT=WxH` for other resolutions |
| `capture_world.gd` | HUD, pause, status, admin, build mode/catalog, every device inspector, NPC profile, in the real MainWorld |

Examples (Godot 4.7.x binary):

```bash
godot --path . --windowed --script res://tools/ui_capture/capture_scene.gd -- res://scenes/ui/main_menu/MainMenu.tscn /tmp/menu "4.5,5.5" "settings@0"
CAPTURE_VIEWPORT=1280x720 godot --path . --windowed --script res://tools/ui_capture/capture_scene.gd -- res://scenes/ui/main_menu/MainMenu.tscn /tmp/menu720 "5"
godot --path . --windowed --script res://tools/ui_capture/capture_world.gd -- /tmp/world
```

**Isolate user data.** Captures run the real game, which can write saves and
settings. Always point Godot at a throwaway data dir:

```bash
export XDG_DATA_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d)
```

Notes: a real mouse over the window moves focus (hover = focus by design); the
graphics memory guard may reject preset changes on a memory-starved machine.
