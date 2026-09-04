class_name ItemPresentation
extends RefCounted

static func title(item: Node) -> String:
	if item == null or not is_instance_valid(item):
		return "Empty slot"
	for method in [&"get_display_name", &"get_item_name"]:
		if item.has_method(method):
			var value: String = str(item.call(method)).strip_edges()
			if not value.is_empty():
				return value
	for property in [&"item_name", &"display_name"]:
		if property in item:
			var value: String = str(item.get(property)).strip_edges()
			if not value.is_empty():
				return value
	return item.name.replace("Item", "").capitalize()

static func detail(item: Node, count: int = 1) -> String:
	if item == null or not is_instance_valid(item):
		return "Available for storage"
	if item.has_method("get_bottle_badge_info"):
		var info: Dictionary = item.call("get_bottle_badge_info")
		var fill := roundi(float(info.get("fill_mL", 0.0)))
		var capacity := roundi(float(info.get("max_fill_mL", 0.0)))
		var quality := roundi(float(info.get("quality", 0.0)))
		return "%d / %d mL filled  •  Water quality %d%%" % [fill, capacity, quality]
	if count > 1:
		return "%d items in this stack" % count
	if "_fuel_remaining" in item:
		var fuel := float(item.get("_fuel_remaining"))
		var fuel_max := float(_script_constant(item, "FUEL_UNITS_TOTAL", 100.0))
		return "%.0f / %.0f fuel units  •  %d%% remaining" % [
			fuel, fuel_max, roundi(100.0 * fuel / maxf(fuel_max, 1.0))]
	if "_battery" in item:
		return "%d%% battery remaining" % roundi(float(item.get("_battery")))
	if "_charges" in item and "_max_charges" in item:
		return "%d / %d uses remaining" % [int(item.get("_charges")), int(item.get("_max_charges"))]
	if "_charges_left" in item:
		var charge_max := int(_script_constant(item, "TOTAL_CHARGES", int(item.get("_charges_left"))))
		return "%d / %d uses remaining" % [int(item.get("_charges_left")), charge_max]
	if "_bites_left" in item:
		var serving_max := int(_script_constant(item, "TOTAL_BITES", int(item.get("_bites_left"))))
		return "%d / %d servings remaining" % [int(item.get("_bites_left")), serving_max]
	if "bottle_count" in item:
		return "%d bottles remaining" % int(item.get("bottle_count"))
	if "can_count" in item:
		return "%d cans remaining" % int(item.get("can_count"))
	return "Ready to retrieve"

static func signature(item: Node, count: int = 1) -> String:
	if item == null or not is_instance_valid(item):
		return "empty"
	return "%s|%s|%s|%d" % [item.get_instance_id(), title(item), detail(item, count), count]

static func _script_constant(item: Node, constant_name: String, fallback: Variant) -> Variant:
	var script := item.get_script()
	if script != null and script.has_method("get_script_constant_map"):
		return script.get_script_constant_map().get(constant_name, fallback)
	return fallback
