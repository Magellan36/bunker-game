extends CanvasLayer
class_name NPCTalkMenuUI
## NPCTalkMenuUI.gd
## Minimal NPC interaction menu — opened by NPC.gd's on_interact() when the
## player presses [E] near an NPC. Two states:
##   MENU     — NPC name + single "Talk" button.
##   DIALOGUE — one placeholder line of dummy text + "Close" button.
## Built on the shared UIKit real-Control-node menu builders — same
## building blocks PauseMenuUI's own confirm-dialog uses
## (build_modal_backdrop/build_centered_panel/make_button), so this reads
## consistently with every other menu instead of being a one-off look.
##
## FUTURE WORK: replace the single "Talk" button / placeholder line with a
## real dialogue-tree system (multiple options, branching text, NPC-specific
## lines) once one exists. This file is intentionally the simplest possible
## version of that shape — do not add dialogue branching here now.

const PANEL_W: float = 340.0
const PANEL_H: float = 170.0
const PLACEHOLDER_LINE: String = "\"...\""

var _backdrop: ColorRect     = null
var _panel:    Panel         = null
var _vbox:     VBoxContainer = null
var _npc_name: String = "Survivor"
var _is_open:  bool   = false

func _ready() -> void:
	layer   = 70   ## same weight as ConfirmDialogUI — above HUD, below AdminMenu(128)/PauseMenuUI(200)
	visible = false

func open(npc_name: String) -> void:
	_npc_name = npc_name
	_is_open  = true
	visible   = true
	_build_menu_state()

func close() -> void:
	_is_open = false
	visible  = false
	_teardown()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _teardown() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_backdrop = null
	_panel    = null
	_vbox     = null

func _open_panel() -> UIKit.UITheme:
	var theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.NEUTRAL)

	_backdrop = UIKit.build_modal_backdrop()
	add_child(_backdrop)

	_panel = UIKit.build_centered_panel(PANEL_W, PANEL_H, theme)
	var panel_style: StyleBoxFlat = _panel.get_theme_stylebox("panel") as StyleBoxFlat
	panel_style.content_margin_left   = 18.0
	panel_style.content_margin_right  = 18.0
	panel_style.content_margin_top    = 16.0
	panel_style.content_margin_bottom = 16.0
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(_vbox)

	var title: Label = Label.new()
	title.text = _npc_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", theme.header)
	title.add_theme_font_override("font", UIKit.font())
	_vbox.add_child(title)

	UIFade.fade_in(_panel)
	return theme

func _build_menu_state() -> void:
	_teardown()
	_open_panel()
	_vbox.add_child(UIKit.make_button("Talk", _on_talk_pressed))

func _build_dialogue_state() -> void:
	_teardown()
	var theme: UIKit.UITheme = _open_panel()

	var line: Label = Label.new()
	line.text = PLACEHOLDER_LINE
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	line.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
	line.add_theme_color_override("font_color", theme.text)
	line.add_theme_font_override("font", UIKit.font())
	_vbox.add_child(line)

	_vbox.add_child(UIKit.make_button("Close", close))

func _on_talk_pressed() -> void:
	_build_dialogue_state()