class_name NotificationHistoryUI
extends Control
## Filterable Bunker Log embedded in the pause menu. It is a view over the
## manager's bounded run history; it never owns or mutates gameplay state.

const FILTERS: Array[String] = ["All", "Critical", "Inventory", "Power", "Water", "Farming"]
const ROW_HEIGHT := 68.0

var _filter := "All"
var _event_count: Label
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _empty: Label
var _filter_buttons: Dictionary = {}
var _row_time_labels: Array[Label] = []
var _row_entries: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	BunkerPanelStyle.apply(self)
	_build()
	NotificationManager.history_changed.connect(_rebuild_rows)
	_rebuild_rows()

func _build() -> void:
	var body := VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("separation", 9)
	add_child(body)
	var accent := ColorRect.new()
	accent.color = BunkerPanelStyle.BLUE
	accent.custom_minimum_size = Vector2(68, 4)
	body.add_child(accent)
	var title_row := HBoxContainer.new()
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 1)
	var title := Label.new()
	title.text = "Bunker Log"
	BunkerPanelStyle.title(title, 29)
	titles.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Recent shelter activity"
	BunkerPanelStyle.muted(subtitle, 14)
	titles.add_child(subtitle)
	title_row.add_child(titles)
	_event_count = Label.new()
	_event_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_event_count.add_theme_color_override("font_color", BunkerPanelStyle.BRASS.lightened(0.35))
	_event_count.add_theme_font_size_override("font_size", 13)
	title_row.add_child(_event_count)
	body.add_child(title_row)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	body.add_child(filters)
	for filter_name: String in FILTERS:
		var button := Button.new()
		button.text = filter_name.to_upper()
		button.toggle_mode = true
		button.button_pressed = filter_name == _filter
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 38
		BunkerPanelStyle.button(button, filter_name == _filter)
		button.pressed.connect(_set_filter.bind(filter_name))
		filters.add_child(button)
		_filter_buttons[filter_name] = button
	_scroll = ScrollContainer.new()
	_scroll.name = "BunkerLogScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	body.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	_scroll.add_child(_rows)
	_empty = Label.new()
	_empty.text = "No events match this filter."
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.custom_minimum_size.y = 120
	BunkerPanelStyle.muted(_empty, 14)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and is_inside_tree():
		_rebuild_rows()
		## Preserve NEW badges during this visit; the manager marks the backing
		## entries after this frame so the next pause-open starts clean.
		NotificationManager.call_deferred("mark_history_seen")

func _set_filter(filter_name: String) -> void:
	_filter = filter_name
	for key: String in _filter_buttons:
		var button := _filter_buttons[key] as Button
		button.button_pressed = key == filter_name
		## Reapply normal/accent styles so selection is more than a thin focus ring.
		BunkerPanelStyle.button(button, key == filter_name)
	_rebuild_rows()

func _rebuild_rows() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.queue_free()
	_row_time_labels.clear()
	_row_entries.clear()
	var history: Array[Dictionary] = NotificationManager.get_history()
	_event_count.text = "%d EVENT%s" % [history.size(), "" if history.size() == 1 else "S"]
	for entry: Dictionary in history:
		if _matches(entry):
			_row_entries.append(entry)
			_rows.add_child(_make_row(entry))
	if _row_entries.is_empty():
		_rows.add_child(_empty.duplicate())
	_scroll.scroll_vertical = 0
	if visible:
		NotificationManager.call_deferred("mark_history_seen")

func _matches(entry: Dictionary) -> bool:
	match _filter:
		"Critical":
			return int(entry.severity) == NotificationManager.Severity.CRITICAL
		"Power":
			return int(entry.domain) == UIKit.Domain.POWER
		"Water":
			return int(entry.domain) == UIKit.Domain.WATER
		"Farming":
			return int(entry.domain) == UIKit.Domain.FARMING
		"Inventory":
			return int(entry.domain) == UIKit.Domain.INVENTORY
		_:
			return true

func _make_row(entry: Dictionary) -> Control:
	var severity := int(entry.severity) as NotificationManager.Severity
	var domain := int(entry.domain) as UIKit.Domain
	var accent := NotificationManager.severity_color(severity)
	if severity == NotificationManager.Severity.INFO:
		accent = NotificationManager.domain_color(domain)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		Color("151a19f2"), BunkerPanelStyle.BRASS.darkened(0.32), 6, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(BunkerPanelStyle.margin(row, 0, 6, 10, 6))
	var stripe := ColorRect.new()
	stripe.color = accent
	stripe.custom_minimum_size.x = 5
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stripe)
	var icon_well := PanelContainer.new()
	icon_well.custom_minimum_size = Vector2(48, 48)
	icon_well.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		BunkerPanelStyle.BG, BunkerPanelStyle.BRASS.darkened(0.18), 5, 1))
	var icon := TextureRect.new()
	icon.texture = BunkerPanelStyle.icon(NotificationManager.domain_symbol(domain))
	icon.self_modulate = NotificationManager.domain_color(domain)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_well.add_child(BunkerPanelStyle.margin(icon, 10, 10, 10, 10))
	row.add_child(icon_well)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 1)
	row.add_child(copy)
	var eyebrow := Label.new()
	eyebrow.text = "%s  •  %s" % [NotificationManager.domain_label(domain),
		NotificationManager.severity_label(severity)]
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", accent)
	copy.add_child(eyebrow)
	var message := Label.new()
	message.text = str(entry.text)
	message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message.add_theme_font_size_override("font_size", 15)
	message.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	copy.add_child(message)
	var detail := str(entry.get("detail", ""))
	if not detail.is_empty():
		var detail_label := Label.new()
		detail_label.text = detail
		detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail_label.add_theme_font_size_override("font_size", 11)
		detail_label.add_theme_color_override("font_color", BunkerPanelStyle.BRASS.lightened(0.32))
		copy.add_child(detail_label)
	var meta := VBoxContainer.new()
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(meta)
	var age := Label.new()
	age.text = _format_age(int(entry.fired_at_msec))
	age.custom_minimum_size.x = 72
	age.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	BunkerPanelStyle.muted(age, 11)
	meta.add_child(age)
	_row_time_labels.append(age)
	var count := int(entry.get("count", 1))
	if count > 1:
		var count_label := Label.new()
		count_label.text = "×%d" % count
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_font_size_override("font_size", 11)
		count_label.add_theme_color_override("font_color", accent)
		meta.add_child(count_label)
	elif not bool(entry.get("seen", true)):
		var new_label := Label.new()
		new_label.text = "NEW"
		new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		new_label.add_theme_font_size_override("font_size", 10)
		new_label.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
		meta.add_child(new_label)
	return panel

func _process(_delta: float) -> void:
	if not visible:
		return
	for i: int in mini(_row_time_labels.size(), _row_entries.size()):
		_row_time_labels[i].text = _format_age(int(_row_entries[i].fired_at_msec))

func _format_age(fired_at_msec: int) -> String:
	var elapsed := maxi(0, int((Time.get_ticks_msec() - fired_at_msec) / 1000.0))
	if elapsed < 10:
		return "JUST NOW"
	if elapsed < 60:
		return "%dS AGO" % elapsed
	var minutes := elapsed / 60
	if minutes < 60:
		return "%dM AGO" % minutes
	return "%dH AGO" % (minutes / 60)
