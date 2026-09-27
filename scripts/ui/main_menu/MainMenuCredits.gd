extends ScrollContainer
## MainMenuCredits.gd (Sep 2026)
## Credits view for the main menu. Reads the project's attribution file
## directly so the in-game credits can never drift from the licences the game
## actually relies on (several are CC BY and legally require this). Formatting:
##   (Section name)                         -> brass section heading
##   Name by Author -- URL -- License: X    -> name + muted "author · licence · url"
##   anything else                          -> body line (HTML tags stripped)
## Scrolls itself slowly; any user scroll pauses the auto-scroll for a while.

const CREDITS_PATH: String = "res://credits and attribution for bunkergame.txt"
const FONT_BODY: FontFile = preload("res://assets/fonts/IosevkaCharon-Regular.ttf")
const FONT_HEAD: FontFile = preload("res://assets/fonts/IosevkaCharon-Medium.ttf")
const AUTO_SPEED: float = 26.0
const START_DELAY: float = 1.6
const RESUME_DELAY: float = 4.0

var ui_scale: float = 1.0
var _list: VBoxContainer
var _idle: float = 0.0
var _scroll_pos: float = 0.0


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Wheel, keys and auto-scroll still work; a bar would read as a stray line.
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	follow_focus = false
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_list)


func _ready() -> void:
	rebuild()


func reset() -> void:
	_idle = -START_DELAY
	_scroll_pos = 0.0
	scroll_vertical = 0


func rebuild() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	_list.add_theme_constant_override("separation", roundi(4.0 * ui_scale))
	var text := FileAccess.get_file_as_string(CREDITS_PATH)
	if text.is_empty():
		_add_label("Credits file not found.", false, BunkerDesign.MUTED, 15)
		return
	var tags := RegEx.create_from_string("<[^>]+>")
	var section := RegEx.create_from_string("^\\((.+)\\)$")
	var entry := RegEx.create_from_string("^(.+?) by (.+?) -- (\\S+) -- License: (.+)$")
	var gap_pending := false
	for raw: String in text.split("\n"):
		var line := tags.sub(raw, "", true).strip_edges()
		if line.is_empty():
			gap_pending = true
			continue
		var heading := section.search(line)
		if heading != null:
			_add_gap(22.0 if _list.get_child_count() > 0 else 0.0)
			_add_label(heading.get_string(1).to_upper(), true, BunkerDesign.BRASS.lightened(0.25), 13)
			gap_pending = false
			continue
		if gap_pending:
			_add_gap(8.0)
			gap_pending = false
		var found := entry.search(line)
		if found != null:
			_add_label(found.get_string(1), false, BunkerDesign.IVORY, 16)
			var url := found.get_string(3).trim_prefix("https://").trim_suffix("/")
			_add_label("%s  ·  %s  ·  %s" % [found.get_string(2), found.get_string(4), url],
				false, BunkerDesign.MUTED, 13)
		else:
			_add_label(line, false, BunkerDesign.IVORY, 16)
	_add_gap(40.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or UIMotion.reduced():
		return
	_idle += delta
	if _idle < 0.0:
		return
	var limit := maxf(_list.size.y - size.y, 0.0)
	if _scroll_pos >= limit:
		return
	_scroll_pos = minf(_scroll_pos + AUTO_SPEED * ui_scale * delta, limit)
	scroll_vertical = roundi(_scroll_pos)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenDrag \
			or event is InputEventPanGesture:
		_pause_auto()


## Called by the screen for keyboard/controller scrolling as well.
func nudge(pixels: float) -> void:
	_pause_auto()
	scroll_vertical += roundi(pixels)
	_scroll_pos = scroll_vertical


func _pause_auto() -> void:
	_idle = -RESUME_DELAY
	_scroll_pos = scroll_vertical


func _add_label(text: String, heading: bool, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", FONT_HEAD if heading else FONT_BODY)
	label.add_theme_font_size_override("font_size", maxi(12, roundi(font_size * ui_scale)))
	label.add_theme_color_override("font_color", color)
	_list.add_child(label)


func _add_gap(pixels: float) -> void:
	if pixels <= 0.0:
		return
	var gap := Control.new()
	gap.custom_minimum_size.y = pixels * ui_scale
	_list.add_child(gap)
