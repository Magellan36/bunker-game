extends "res://scripts/ui/common/BunkerDeviceInspector.gd"
## Single/double tray inspector. World actions (soil, plant, harvest, fertilizer)
## remain item/interaction actions; seed locks are instructions for NPCs only.
var _tray: FarmingTray
var _connection: PanelContainer
var _water: VBoxContainer
var _warning: Label
var _priority_control: VBoxContainer
var _cells: Array[PanelContainer] = []
var _seed_lock_dd: Array[OptionButton] = []
var _seed_lock_options: Array = [[], []]
var _seed_lock_labels: Array = [[], []]

func _build_content() -> void:
	_connection = W.status(_statuses, "Connection")
	_water = W.meter(_details, "Water", "Water supplied", "water")
	_warning = W.label(_details, "WaterWarning", "", 14, "warning")
	for index: int in range(2):
		var card := PanelContainer.new()
		card.name = "Cell%d" % (index + 1)
		card.theme_type_variation = &"BunkerInspectorCard"
		_details.add_child(card)
		var content: VBoxContainer = W.column(card, "Content", 8)
		W.label(content, "Title", "Cell %d" % (index + 1), 18)
		W.label(content, "State", "", 14, "secondary")
		W.meter(content, "Health", "Health", "condition")
		W.meter(content, "Growth", "Growth", "plant")
		W.label(content, "Fertilizer", "", 14, "secondary")
		W.label(content, "SeedLabel", "Seed lock · NPC auto-plant only", 14, "secondary")
		var option: OptionButton = W.option(content, "SeedLock")
		option.item_selected.connect(func(option_index: int): _on_seed_lock_selected(index, option_index))
		_cells.append(card)
		_seed_lock_dd.append(option)
	_priority_control = _add_priority(_footer, _on_priority_requested)
	_priority_control.set_hint("Water allocation · 1 is served first, 5 last")

func open(tray: FarmingTray) -> void:
	if not is_instance_valid(tray):
		return
	_tray = tray
	_seed_lock_options = [[], []]
	_seed_lock_labels = [[], []]
	_open_device("Farm tray · %s" % ("Single" if tray.cell_count == 1 else "Double"), "FARMING", "plant", tray)

func _refresh_data() -> void:
	if not is_instance_valid(_tray) or _tray.is_queued_for_deletion():
		close()
		return
	var connected: bool = _tray.is_connected_to_water()
	var demand: float = _tray.get_current_demand_mL_per_day()
	var fraction: float = _tray.get_water_fraction()
	W.set_status(_connection, "Water connected" if connected else "Disconnected", "success" if connected else "warning", "grid")
	W.set_meter(_water, fraction * 100.0, "%d%%" % roundi(fraction * 100.0),
		"%.0f / %.0f mL/day received" % [fraction * demand, demand], "blue" if fraction >= 1.0 else "warning")
	_warning.visible = fraction < 1.0
	_warning.text = "Insufficient water (%d%% of demand met) — plant growth will slow." % roundi(fraction * 100.0)
	_priority_control.set_value(_tray.priority)
	var available: Array[String] = _get_available_seed_types()
	for index: int in range(2):
		_cells[index].visible = index < _tray.cell_count
		if index < _tray.cell_count:
			_refresh_cell(index)
			_refresh_seed_lock_dropdown(index, available)

func _refresh_cell(index: int) -> void:
	var content: VBoxContainer = _cells[index].get_node("Content") as VBoxContainer
	var plant: FarmPlant = _tray.plant_refs[index] if is_instance_valid(_tray.plant_refs[index]) else null
	var occupied: bool = plant != null and not plant.is_queued_for_deletion()
	for key: String in ["Health", "Growth", "Fertilizer"]:
		(content.get_node(key) as Control).visible = occupied
	var title: Label = content.get_node("Title") as Label
	var state: Label = content.get_node("State") as Label
	title.text = "Cell %d" % (index + 1)
	if not occupied:
		state.text = "Needs soil" if not _tray.soil_filled[index] else "Empty · Ready to plant"
		state.add_theme_color_override("font_color", W.color(_view, "secondary"))
		return
	title.text += " · " + PlantDatabase.get_display_name(plant.plant_type)
	state.text = _growth_status(plant)
	state.add_theme_color_override("font_color", W.color(_view, "success" if plant.is_ready() else "secondary"))
	var health_token: String = "success" if plant.health >= 60.0 else ("warning" if plant.health >= 25.0 else "critical")
	W.set_meter(content.get_node("Health") as VBoxContainer, plant.health, "%d%%" % roundi(plant.health), "", health_token)
	W.set_meter(content.get_node("Growth") as VBoxContainer, plant.progress * 100.0, "%d%%" % roundi(plant.progress * 100.0), "", "success")
	var fertilizer: Label = content.get_node("Fertilizer") as Label
	fertilizer.text = "Fertilized (%s, +%d%% growth)" % [plant.fertilizer_tier.capitalize(), roundi(plant.fertilizer_bonus * 100.0)] if plant.is_fertilized() else "Not fertilized"

func _growth_status(plant: FarmPlant) -> String:
	if plant.is_ready():
		return "Ready to harvest"
	if plant.progress <= 0.0 and plant.water_fraction <= 0.0:
		return "Dormant · No water"
	if plant.growth_per_hour_current <= 0.0:
		var reasons: Array[String] = []
		if plant.water_fraction <= 0.0:
			reasons.append("No water")
		if plant._light_speed_cached <= FarmPlant.LIGHT_FLOOR_SPEED:
			reasons.append("No light")
		return "Stalled" + (" · " + ", ".join(reasons) if not reasons.is_empty() else "")
	var hours: float = (1.0 - plant.progress) / plant.growth_per_hour_current
	var amount: int = ceili(hours / 24.0) if hours >= 24.0 else ceili(hours)
	return "About %d %s%s until harvest" % [amount, "day" if hours >= 24.0 else "hour", "" if amount == 1 else "s"]

func _on_priority_requested(value: int) -> void:
	if _is_open and is_instance_valid(_tray):
		_tray.priority = clampi(value, 1, 5)
		_refresh_data()

func _on_seed_lock_selected(cell_index: int, option_index: int) -> void:
	if not _is_open or not is_instance_valid(_tray):
		return
	var options: Array = _seed_lock_options[cell_index]
	if option_index >= 0 and option_index < options.size():
		_tray.set_cell_seed_lock(cell_index, String(options[option_index]))
		_refresh_data()

func _get_available_seed_types() -> Array[String]:
	var seen: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("inventory_item"):
		if node is SeedItem and not node.is_queued_for_deletion() and node._charges > 0:
			seen[(node as SeedItem).seed_type] = true
	var types: Array[String] = []
	for type: String in seen.keys():
		types.append(type)
	types.sort_custom(func(a: String, b: String) -> bool:
		return PlantDatabase.get_display_name(a) < PlantDatabase.get_display_name(b))
	return types

func _refresh_seed_lock_dropdown(index: int, available: Array[String]) -> void:
	var option: OptionButton = _seed_lock_dd[index]
	# Do not reorder an open native popup beneath the player's selection.
	if option.get_popup().visible:
		return
	var current: String = _tray.get_cell_seed_lock(index)
	var options: Array[String] = [""]
	options.append_array(available)
	if not current.is_empty() and not current in available:
		options.append(current)
	var labels: Array[String] = []
	for type: String in options:
		var text: String = "Any (NPC auto-plant)" if type.is_empty() else PlantDatabase.get_display_name(type)
		if not type.is_empty() and not type in available:
			text += " (none in stock)"
		labels.append(text)
	if options != _seed_lock_options[index] or labels != _seed_lock_labels[index]:
		_seed_lock_options[index] = options
		_seed_lock_labels[index] = labels
		option.clear()
		for text: String in labels:
			option.add_item(text)
	option.select(maxi(options.find(current), 0))
	option.tooltip_text = labels[option.selected]
