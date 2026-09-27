extends SceneTree
## Quiet UI design lint (Sep 2026). Structural checks that keep every
## migrated screen inside docs/ui/QUIET_DESIGN_SYSTEM.md. Each redesign pass
## REGISTERS its screen in SCREENS below; the lint then walks the live
## Control tree and fails on the audit's anti-patterns:
##   - buttons with persistent borders
##   - saturated project blue (BunkerDesign.BLUE / BLUE_DARK) in text or fills
##     (the main menu's approved hero rail is the one registered exception)
##   - loud scrollbars (grabber alpha above 0.35)
##   - type below the 11 px floor
##   - icons on buttons / free TextureRects without an explicit `quiet_icon`
##     meta (see the icon rules, design system §8)
## Opt-outs are per node via metas: quiet_allow_border, quiet_icon,
## quiet_allow_blue. Every opt-out must be justified in the screen's doc.
##
## godot --headless --path . --script res://tools/tests/quiet_ui_lint.gd
## Debt report for unmigrated screens (never fails):
## godot --headless --path . --script res://tools/tests/quiet_ui_lint.gd -- --baseline

const SCREENS: Array[Dictionary] = [
	{"name": "Graphics Settings", "kind": "canvas_script",
		"path": "res://scripts/ui/menus/GraphicsSettingsPanel.gd", "open": true},
	{"name": "Main Menu", "kind": "scene", "path": "res://scenes/ui/main_menu/MainMenu.tscn",
		"root": "Interface/Screen", "allow_hero_blue": true,
		"await_loads": ["res://scenes/world/menu_backdrop/MenuBackdrop.tscn"]},
	{"name": "Confirm dialog", "kind": "canvas_script", "path": "res://scripts/ui/common/ConfirmDialogUI.gd",
		"open_args": ["Exit to desktop?", "Unsaved progress will be lost.", "Exit game", "Stay here", "danger"]},
	{"name": "Pause", "kind": "canvas_script", "path": "res://scripts/ui/menus/PauseMenuUI.gd", "open": true},
	{"name": "Game over", "kind": "canvas_script", "path": "res://scripts/ui/menus/GameOverUI.gd"},
	{"name": "Character creation", "kind": "scene",
		"path": "res://scenes/ui/character_creation/CharacterCreation.tscn", "root": "Interface"},
	## Pass 3 — HUD, docked inspectors (runtime-styled, so linted through
	## their scripts), trash-bag card.
	{"name": "HUD", "kind": "scene", "path": "res://scenes/ui/HUD.tscn", "root": "."},
	{"name": "Generator inspector", "kind": "canvas_script", "path": "res://scripts/ui/power/GeneratorInspectUI.gd",
		"open_args": ["Generator S", 800.0, 99.0, 100.0, false, true]},
	{"name": "Breaker inspector", "kind": "canvas_script", "path": "res://scripts/ui/power/BreakerInspectUI.gd",
		"open_args": [null, "Breaker", {"zones": [{"name": "Living quarters"}]}]},
	{"name": "Battery inspector", "kind": "canvas_script", "path": "res://scripts/ui/power/BatteryInspectUI.gd",
		"open_args": [null, "Battery S", {"charge_wh": 40.0, "capacity_wh": 100.0}]},
	{"name": "Trash bag card", "kind": "canvas_script", "path": "res://scripts/ui/common/TrashBagInfoPanel.gd"},
	## Pass 4 — workspaces that can open without a live owner. NPC profile and
	## research need their owners; they are reviewed from live captures.
	{"name": "Power terminal", "kind": "canvas_script", "path": "res://scripts/ui/power/PowerTerminalModernUI.gd", "open": true},
	{"name": "Status", "kind": "canvas_script", "path": "res://scripts/ui/medical/StatusScreenUI.gd", "open": true},
]

## Unmigrated screens that can be built standalone. When a pass migrates one,
## MOVE it to SCREENS above (it then has to pass).
const BASELINE_SCREENS: Array[Dictionary] = [
]

const MIN_FONT_SIZE: int = 11
const MAX_SCROLL_GRABBER_ALPHA: float = 0.35
const COLOR_TOLERANCE: float = 0.06

var _failures: int = 0
var _checked: int = 0
var _per_screen: Dictionary = {}
var _current_screen: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	if "--baseline" in OS.get_cmdline_user_args():
		for screen: Dictionary in BASELINE_SCREENS:
			await _lint_screen(screen)
		print("QUIET_UI_BASELINE (violations per unmigrated screen):")
		for screen: Dictionary in BASELINE_SCREENS:
			print("  %-26s %d" % [screen["name"], int(_per_screen.get(screen["name"], 0))])
		quit(0)
		return
	for screen: Dictionary in SCREENS:
		await _lint_screen(screen)
	if _failures == 0:
		print("QUIET_UI_LINT_OK (%d screens, %d controls)" % [SCREENS.size(), _checked])
	quit(_failures)


func _lint_screen(screen: Dictionary) -> void:
	var host: Node = null
	var target: Node = null
	match str(screen["kind"]):
		"canvas_script":
			host = (load(str(screen["path"])) as GDScript).new()
			root.add_child(host)
			await process_frame
			if screen.get("open", false) and host.has_method("open"):
				host.call("open")
			if screen.has("open_args"):
				host.callv("open", screen["open_args"])
			target = host
		"scene":
			host = (load(str(screen["path"])) as PackedScene).instantiate()
			root.add_child(host)
			await process_frame
			target = host.get_node(str(screen["root"]))
			if target.has_method("skip_intro"):
				target.call("skip_intro")
	for i: int in range(3):
		await process_frame
	_current_screen = str(screen["name"])
	var context := {"screen": str(screen["name"]),
		"allow_blue": bool(screen.get("allow_hero_blue", false))}
	_walk(target, context)
	# Let any threaded load the screen started finish before tearing down,
	# or the loader reports a spurious parse failure at exit.
	var waited := 0.0
	for path: String in screen.get("await_loads", []):
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS \
				and waited < 20.0:
			await create_timer(0.1).timeout
			waited += 0.1
	host.free()
	await process_frame


func _walk(node: Node, context: Dictionary) -> void:
	if node is Control:
		_checked += 1
		_lint_control(node as Control, context)
	# Engine-internal children (scroll hints, popup internals) are not ours.
	for child: Node in node.get_children(false):
		_walk(child, context)


func _lint_control(control: Control, context: Dictionary) -> void:
	var where := "%s › %s" % [context["screen"], _path(control)]
	var allow_blue: bool = context["allow_blue"] or control.has_meta(&"quiet_allow_blue")
	if control is BaseButton and not control.has_meta(&"quiet_allow_border"):
		var normal := control.get_theme_stylebox("normal") as StyleBoxFlat
		if normal != null and _has_border(normal):
			_fail(where, "button has a persistent border")
		if not allow_blue:
			for state: String in ["normal", "hover", "pressed", "focus"]:
				var style := control.get_theme_stylebox(state) as StyleBoxFlat
				if style != null and (_is_blue(style.bg_color) or _is_blue(style.border_color)):
					_fail(where, "saturated blue in button '%s' style" % state)
	if control is Button and control.visible and (control as Button).icon != null and not control.has_meta(&"quiet_icon"):
		_fail(where, "button icon without quiet_icon meta")
	## A deliberately hidden legacy icon (kept only so callers keep working)
	## is not an icon on screen.
	if control is TextureRect and control.visible and not control.has_meta(&"quiet_icon"):
		var texture := (control as TextureRect).texture
		if texture != null and not (texture is GradientTexture2D) and not (texture is ViewportTexture):
			_fail(where, "TextureRect icon without quiet_icon meta")
	if control is Label or control is Button:
		var font_size := control.get_theme_font_size("font_size")
		if font_size > 0 and font_size < MIN_FONT_SIZE:
			_fail(where, "font size %d below floor" % font_size)
		if not allow_blue and control.is_visible_in_tree() \
				and _is_blue(control.get_theme_color("font_color")):
			_fail(where, "saturated blue text")
	if control is PanelContainer and not allow_blue:
		var panel := control.get_theme_stylebox("panel") as StyleBoxFlat
		if panel != null and panel.bg_color.a > 0.05 and _is_blue(panel.bg_color):
			_fail(where, "saturated blue panel fill")
	if control is ScrollBar and control.is_visible_in_tree():
		var grabber := control.get_theme_stylebox("grabber") as StyleBoxFlat
		if grabber != null and grabber.bg_color.a > MAX_SCROLL_GRABBER_ALPHA:
			_fail(where, "loud scrollbar grabber (alpha %.2f)" % grabber.bg_color.a)


func _has_border(style: StyleBoxFlat) -> bool:
	return (style.border_width_left + style.border_width_top + style.border_width_right
		+ style.border_width_bottom) > 0 and style.border_color.a > 0.01


func _is_blue(color: Color) -> bool:
	if color.a < 0.05:
		return false
	for reference: Color in [BunkerDesign.BLUE, BunkerDesign.BLUE_DARK]:
		if absf(color.r - reference.r) < COLOR_TOLERANCE and absf(color.g - reference.g) < COLOR_TOLERANCE \
				and absf(color.b - reference.b) < COLOR_TOLERANCE:
			return true
	return false


func _path(node: Node) -> String:
	var parts: PackedStringArray = []
	var current := node
	while current != null and parts.size() < 4:
		parts.insert(0, str(current.name))
		current = current.get_parent()
	return "/".join(parts)


func _fail(where: String, message: String) -> void:
	_failures += 1
	_per_screen[_current_screen] = int(_per_screen.get(_current_screen, 0)) + 1
	if "--baseline" in OS.get_cmdline_user_args():
		return
	push_error("QUIET_UI_LINT_FAIL: %s — %s" % [where, message])
