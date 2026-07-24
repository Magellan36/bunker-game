extends Control
## NotificationHistoryUI.gd
## ─────────────────────────────────────────────────────────────────────────────
## Scrollable notification history panel (Jul 2026 follow-on to the
## "UI Kit + Central Notification System" plan). Shows the last
## `NotificationManager.MAX_HISTORY_LEN` notifications in a minimized/
## condensed row format, newest entry at the TOP (opposite of the live
## toast stack, which stacks newest-at-bottom).
##
## Visible ONLY inside the pause menu — instantiated as a child of
## PauseMenuUI (a CanvasLayer, layer=200) so it shows/hides for free with
## that layer's own `visible` toggle in open()/close(). No header, no
## title, no close button by design (Brannon's call) — it's a passive
## sub-panel, not its own modal.
##
## Live-updating while the pause menu is open: listens to
## NotificationManager's `history_changed` signal to rebuild rows on new
## notifications, and runs its own lightweight `_process()` (only while
## `visible`) to refresh each row's "Xs ago" label. Safe to run
## unconditionally in _process because the pause menu does NOT set
## SceneTree.paused (game keeps running behind it) — see PauseMenuUI.gd's
## own header comment.
##
## Row format: severity-colored accent bar + domain-tinted text + single
## line message + right-aligned "Xs ago" timestamp.

const PANEL_W: float = 380.0
const PANEL_H: float = 480.0
const ROW_H:   float = 34.0

var _scroll: ScrollContainer = null
var _rows_box: VBoxContainer = null
var _row_time_labels: Array[Label] = []   ## parallel to _row_entries, refreshed per-frame
var _row_entries: Array[Dictionary] = []


func _ready() -> void:
	## Anchor point ~(0.75 * viewport width, 0.25 * viewport height) as the
	## panel's top-left — "3/4 to the right, 3/4 up the screen" (upper-right
	## quadrant, inset from the corner) — clamped so it never overflows the
	## viewport on any resolution.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_reposition()
	get_viewport().size_changed.connect(_reposition)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color     = Color(0.06, 0.06, 0.07, 0.90)
	style.border_color = Color(0.32, 0.32, 0.35, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left   = 8.0
	style.content_margin_right  = 8.0
	style.content_margin_top    = 8.0
	style.content_margin_bottom = 8.0
	var bg_panel: Panel = Panel.new()
	bg_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_panel.add_theme_stylebox_override("panel", style)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(bg_panel)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bg_panel.add_child(_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 2)
	_scroll.add_child(_rows_box)

	NotificationManager.history_changed.connect(_rebuild_rows)
	_rebuild_rows()


func _reposition() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var x: float = clampf(vp.x * 0.75, 0.0, vp.x - PANEL_W)
	var y: float = clampf(vp.y * 0.25, 0.0, vp.y - PANEL_H)
	position = Vector2(x, y)
	size = Vector2(PANEL_W, PANEL_H)


func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_time_labels()


## Rebuilds the full row list from scratch. Called once on ready and again
## every time NotificationManager fires history_changed (a new notify()
## call) — the history is capped at 20 entries so a full rebuild is cheap.
func _rebuild_rows() -> void:
	for child: Node in _rows_box.get_children():
		child.queue_free()
	_row_time_labels.clear()
	_row_entries = NotificationManager.get_history()   ## already newest-first

	for entry: Dictionary in _row_entries:
		_rows_box.add_child(_make_row(entry))


func _make_row(entry: Dictionary) -> Control:
	## Row chrome matches the Jul 2026 toast rework: solid severity-colored
	## fill (same TOAST_FILL_ALPHA as the live toasts) + dark semi-transparent
	## border, instead of the old thin accent bar + domain-tinted text.
	var severity: NotificationManager.Severity = entry["severity"] as NotificationManager.Severity
	var fill: Color = _severity_color(severity)
	fill.a = NotificationManager.TOAST_FILL_ALPHA

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color     = fill
	style.border_color = NotificationManager.TOAST_BORDER_COLOR
	style.set_border_width_all(NotificationManager.TOAST_BORDER_WIDTH)
	style.set_corner_radius_all(NotificationManager.TOAST_CORNER_RADIUS)
	style.content_margin_left   = 8.0
	style.content_margin_right  = 8.0
	style.content_margin_top    = 2.0
	style.content_margin_bottom = 2.0

	var row_panel: PanelContainer = PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0.0, ROW_H)
	row_panel.add_theme_stylebox_override("panel", style)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row_panel.add_child(row)

	var text_lbl: Label = Label.new()
	text_lbl.text = str(entry["text"])
	text_lbl.clip_text = true
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_lbl.add_theme_font_override("font", UIKit.font())
	text_lbl.add_theme_font_size_override("font_size", 12)
	text_lbl.add_theme_color_override("font_color", NotificationManager.TOAST_TEXT_COLOR)
	row.add_child(text_lbl)

	var time_lbl: Label = Label.new()
	time_lbl.text = _format_age(entry["fired_at_msec"] as int)
	time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_lbl.custom_minimum_size = Vector2(48.0, 0.0)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_lbl.add_theme_font_override("font", UIKit.font())
	time_lbl.add_theme_font_size_override("font_size", 11)
	time_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.85))
	row.add_child(time_lbl)
	_row_time_labels.append(time_lbl)

	return row_panel


func _refresh_time_labels() -> void:
	for i: int in range(_row_time_labels.size()):
		if i >= _row_entries.size():
			continue
		_row_time_labels[i].text = _format_age(_row_entries[i]["fired_at_msec"] as int)


func _format_age(fired_at_msec: int) -> String:
	var elapsed_sec: int = int((Time.get_ticks_msec() - fired_at_msec) / 1000.0)
	if elapsed_sec < 60:
		return "%ds ago" % elapsed_sec
	var elapsed_min: int = int(elapsed_sec / 60.0)
	if elapsed_min < 60:
		return "%dm ago" % elapsed_min
	var elapsed_hr: int = int(elapsed_min / 60.0)
	return "%dh ago" % elapsed_hr


func _severity_color(severity: NotificationManager.Severity) -> Color:
	match severity:
		NotificationManager.Severity.WARNING:
			return NotificationManager.SEVERITY_COLOR_WARNING
		NotificationManager.Severity.CRITICAL:
			return NotificationManager.SEVERITY_COLOR_CRITICAL
		_:
			return NotificationManager.SEVERITY_COLOR_INFO
