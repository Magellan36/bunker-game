extends CanvasLayer
class_name NPCSeedSelectMenuUI
## NPCSeedSelectMenuUI.gd (Aug 2026)
## Standalone popup for "Plant seeds" — lists every seed TYPE currently
## available (loose or shelved, any quantity) as its own button. Picking
## one issues NPCBrain.CommandGardeningActivity(mode="plant_only",
## forced_seed_type=that type) on the NPC that opened this, then closes.
## Deliberately its own small CanvasLayer rather than more rows crammed
## into NPCTalkMenuUI — see that file's _open_seed_select_menu().

const PANEL_W: float = 320.0
const ROW_H: float = 36.0

var _npc: Node = null
var _backdrop: ColorRect = null
var _panel: Panel = null
var _vbox: VBoxContainer = null

func open(npc: Node) -> void:
	_npc = npc
	layer = 210   ## above NPCTalkMenuUI
	var theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.FARMING)
	_backdrop = UIKit.build_modal_backdrop()
	add_child(_backdrop)
	_backdrop.gui_input.connect(_on_backdrop_input)

	var available_types: Array = _find_available_seed_types()
	var panel_h: float = 90.0 + float(max(available_types.size(), 1)) * (ROW_H + 6.0)
	_panel = UIKit.build_centered_panel(PANEL_W, panel_h, theme)
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vbox.offset_left = 16.0
	_vbox.offset_right = -16.0
	_vbox.offset_top = 16.0
	_vbox.offset_bottom = -16.0
	_panel.add_child(_vbox)

	var header: Label = UIKit.make_section_label("What kind of seed?", theme)
	_vbox.add_child(header)

	if available_types.is_empty():
		var none_label: Label = UIKit.make_row_label("No seeds available right now.", theme)
		_vbox.add_child(none_label)
	else:
		for seed_type: String in available_types:
			var display: String = PlantDatabase.get_display_name(seed_type)
			var btn: Button = UIKit.make_button(display, _on_type_pressed.bind(seed_type), ROW_H)
			_vbox.add_child(btn)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	_vbox.add_child(spacer)
	var cancel: Button = UIKit.make_button("Cancel", _on_cancel_pressed, ROW_H)
	_vbox.add_child(cancel)

## Enumerates every species with at least one loose or shelved SeedItem
## right now — deliberately NOT every species in PlantDatabase, so the
## player only ever sees types that could actually succeed.
func _find_available_seed_types() -> Array:
	var found: Dictionary = {}   ## seed_type -> true
	for item: Node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(item) or not (item is SeedItem):
			continue
		if ("is_held" in item and item.is_held) or item.is_in_group("shelved"):
			continue
		found[item.seed_type] = true
	for shelf: Node in get_tree().get_nodes_in_group("shelving"):
		if not is_instance_valid(shelf) or not ("slots" in shelf):
			continue
		for stack in shelf.slots:
			if stack is Array and not stack.is_empty() and stack.back() is SeedItem:
				found[stack.back().seed_type] = true
	var out: Array = found.keys()
	out.sort()
	return out

func _on_type_pressed(seed_type: String) -> void:
	if _npc != null and is_instance_valid(_npc) and ("brain" in _npc) and _npc.brain != null:
		var cmd: NPCBrain.CommandGardeningActivity = NPCBrain.CommandGardeningActivity.new()
		cmd.mode = "plant_only"
		cmd.forced_seed_type = seed_type
		_npc.brain.force_command(cmd)
		var label: String = PlantDatabase.get_display_name(seed_type)
		NotificationManager.notify(UIKit.Domain.FARMING, NotificationManager.Severity.INFO,
			"%s: heading to plant %s seeds" % [_npc.npc_name if "npc_name" in _npc else "NPC", label])
	_close()

func _on_cancel_pressed() -> void:
	_close()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _close() -> void:
	queue_free()