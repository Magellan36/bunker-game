extends CanvasLayer
## GameOverUI.gd — shown when the player's HP hits 0 (permanent death).
## The player model plays the one-shot dying clip behind a dim overlay; the
## game is over. Offers reloading the last save or quitting.
## Instantiated on demand by MainWorld._open_game_over() (death is final).

const BG_DIM: Color = Color(0.0, 0.0, 0.0, 0.8)
const TEXT_COLOR: Color = Color(1.0, 0.30, 0.25, 1.0)
const PANEL_W: float = 420.0
const PANEL_H: float = 240.0
## Sep 2026 — the screen deliberately appears a beat after death (so the dying
## collapse plays out) and fades in slowly instead of popping up instantly.
const FADE_DELAY: float = 1.5
const FADE_DURATION: float = 1.5

var _center: Control = null
var _dim: ColorRect = null
var _font: Font = null

func _ready() -> void:
	layer = 200   ## above pause menu (200 is PauseMenuUI's layer)
	visible = false
	_font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	if _font == null:
		_font = ThemeDB.fallback_font
	_build()

func _build() -> void:
	## Full-screen backdrop + centered panel of label and buttons.
	var dim := ColorRect.new()
	dim.color = BG_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   ## block clicks behind
	add_child(dim)
	_dim = dim

	_center = Control.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center)

	var title := Label.new()
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(0.0, -100.0)
	title.custom_minimum_size = Vector2(PANEL_W, 60.0)
	_center.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "The bunker falls silent."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", _font)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8, 0.9))
	subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle.position = Vector2(0.0, -30.0)
	subtitle.custom_minimum_size = Vector2(PANEL_W, 30.0)
	_center.add_child(subtitle)

	var load_btn := Button.new()
	load_btn.text = "Load Last Save"
	load_btn.pressed.connect(_on_load_pressed)
	load_btn.add_theme_font_override("font", _font)
	load_btn.add_theme_font_size_override("font_size", 18)
	load_btn.custom_minimum_size = Vector2(PANEL_W * 0.7, 42.0)
	load_btn.set_anchors_preset(Control.PRESET_CENTER)
	load_btn.position = Vector2(-PANEL_W * 0.35, -20.0)
	_center.add_child(load_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit to Desktop"
	quit_btn.pressed.connect(_on_quit_pressed)
	quit_btn.add_theme_font_override("font", _font)
	quit_btn.add_theme_font_size_override("font_size", 18)
	quit_btn.custom_minimum_size = Vector2(PANEL_W * 0.7, 42.0)
	quit_btn.set_anchors_preset(Control.PRESET_CENTER)
	quit_btn.position = Vector2(-PANEL_W * 0.35, 40.0)
	_center.add_child(quit_btn)

func open() -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	## Deliberately NOT pausing the tree — the player's dying clip must play
	## out behind the dim (a paused tree would freeze it mid-collapse). The
	## player is dead + movement-locked, so nothing meaningful continues.
	## Start fully transparent, let the collapse play for FADE_DELAY, then
	## fade the backdrop + panel in over FADE_DURATION.
	_center.modulate.a = 0.0
	_dim.modulate.a = 0.0
	await get_tree().create_timer(FADE_DELAY).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	UIFade.fade_in(_dim, FADE_DURATION)
	UIFade.fade_in(_center, FADE_DURATION)

func _on_load_pressed() -> void:
	SaveManager.load_game(0)

func _on_quit_pressed() -> void:
	get_tree().quit()