class_name UIFade
extends RefCounted
## UIFade.gd
## Tiny shared fade-in helper for UI panels — standing convention (July 2026):
## every panel that opens via player interaction fades in rather than
## popping instantly on screen. Applies to ALL current panels (Power
## Terminal, Power Priority, Generator Inspect, Breaker settings — including
## Upgraded Breaker via inheritance, Battery Bank, Shelf UI, Admin Spawn
## Menu, Pause Menu, Graphics Settings) and every new panel going forward.
##
## Usage: call once, right after setting `visible = true` in a panel's
## open()/toggle() function —
##     UIFade.fade_in(_panel)
## `_panel` (or `_canvas`/`_root`, whichever Control holds the panel's actual
## content) must be a CanvasItem — Control, Panel, etc. CanvasLayer itself
## does NOT work as a target (no `modulate` property); pass the Control
## child that sits inside it instead.
##
## Deliberately a tiny pure-function utility (RefCounted, no instance state)
## in its own file/folder rather than duplicated inline in every panel — see
## PROJECT_SUMMARY.md's "no god files" / folder-organization standing rules.

const DEFAULT_DURATION: float = 0.15


static func fade_in(target: CanvasItem, duration: float = DEFAULT_DURATION) -> void:
	if target == null or not is_instance_valid(target):
		return
	target.modulate.a = 0.0
	var tw: Tween = target.create_tween()
	tw.tween_property(target, "modulate:a", 1.0, duration)
