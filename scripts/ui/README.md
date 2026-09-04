# UI implementation map

Start here when making sweeping visual adjustments. The detailed historical
system overview is `docs/systems/ui/README.md`; the approved device contracts
and review boundaries are in `plans/ui-redesign-device-pass.md`.

## Compact in-world inspectors

| Change | Edit |
|---|---|
| Palette, borders, button states, meter fills | `assets/ui/themes/BunkerRedesignTheme.tres` |
| Width, dock, scale cap, font/spacing scaling | `common/BunkerInspectorLayout.gd` |
| Shared header, status area, scrolling, footer | `scenes/ui/common/DeviceInspectPanel.tscn` |
| Open/close, safe focus, popup ownership, hints, refresh cadence | `common/BunkerDeviceInspector.gd` |
| Reusable native status cards, meters, text rows, buttons, dropdowns | `common/BunkerInspectorWidgets.gd` |
| Shared priority control | `common/BunkerPriorityControl.gd` |
| Code-drawn functional icons | `common/BunkerSymbolTexture.gd` |
| Host binding, walk-away distance, host/player lifetime safety | `common/UIProximityClose.gd` |
| Device-specific order, wording, fields/actions | The device UI's `_build_content()` and `_refresh_data()` |

`GeneratorInspectUI.gd` retains its approved dedicated scene
`scenes/ui/power/GeneratorInspectPanel.tscn`. It shares the theme, layout,
symbol factory, controller helper and proximity behavior. Do not resize it
using character-creation dimensions. The other migrated inspectors compose
real Godot controls into the shared scene; no custom hit-test rectangles.

### Domain adapters

- `water/WaterDispenserUI.gd`: stored water/quality, request slider, received
  rate, priority, on/off. Existing owner and WaterManager APIs.
- `water/WaterInfoUI.gd`: hookup/sink/purifier variants in one place.
- `farming/FarmingTrayUI.gd`: one/two cell cards, real growth/health/status,
  fertilizer, NPC-only seed locks, water priority.
- `power/PowerPriorityUI.gd`: consumer state and priority, optional load toggle.
- `power/BatteryInspectUI.gd`: snapshot + enabled request. World-owned health
  stub remains explicit until battery health is implemented.
- `power/BreakerInspectUI.gd`: snapshot + independent sharing/reset requests.
  Standard and smart breakers use the same panel.

BatteryBank and BreakerBox keep small open/close/snapshot/action bridges only.
Never move network, timed-job, injury, save/load or simulation policy into UI.
Panel snapshots are transient presentation data, not a second save-state model.

## Standing rules for future device panels

1. Use `_open_device(..., real_device)` on every open. Position-only fallback is
   retained for API compatibility; new callers must pass the real host.
2. Keep the 500 px 1080p width, 24 px right margin, no dimming/backdrop and
   13–24 px type hierarchy. Height varies by content. Scroll the details at
   small resolutions. Do not lock movement or enable left-stick UI navigation.
3. Separate requests from confirmed display values. Native toggle/slider
   refresh uses no-signal setters; block Range signals around max-value updates.
4. Data without signals may use the existing 10 Hz open-only cadence. Prefer
   coalesced owner callbacks where available. No closed-panel polling.
5. Native dropdowns own their popup input. Close/distance dismissal hides them;
   the world-input gate stays active while a dropdown is open.
6. Keep Close as the safe initial focus, scroll to the top on open, respect
   higher-layer menus, and emit `closed` once. Do not replace walk-away behavior
   with a fullscreen mouse blocker.
7. Prefer native controls, theme resources and functional geometry. Do not
   create unnecessary image assets. Preserve labeled artwork provenance and
   the release blocker; file format is not a disclosure exemption.

## Held for user review

HUD/needs/inventory hotbar, hover/interaction prompts and world banners, pause
and settings, notifications/history, terminal/zone customization, storage,
research, NPC/medical, build/shop, loading and other unique workflows are not
authorized ports in this pass. Approved character creation stays full-screen
and unchanged. Consult the complete audit before choosing the next scope.

## Verification

`python3 tools/tests/run_device_inspectors.py --godot /path/to/godot`

This builds a temporary, isolated project using the actual UI/owner code and
explicit simulation doubles. It cannot prove the full game's solver, renderer,
controller hardware or feel. Also run the existing generator and character
creation scene tests, then the in-game checklist in the pass plan.
