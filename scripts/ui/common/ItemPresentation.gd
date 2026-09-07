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
	return fallback_title(item.name)


static func record_title(record: Dictionary, fallback: String = "Unknown item") -> String:
	var explicit: String = String(record.get("display_name", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var item_type: String = String(record.get("item_type", "")).strip_edges()
	return fallback_title(item_type) if not item_type.is_empty() else fallback


static func fallback_title(raw: String) -> String:
	var source: String = raw.strip_edges().replace("_", " ").replace("-", " ")
	while source.length() > 0 and source[-1].is_valid_int():
		source = source.left(source.length() - 1)
	var result: String = ""
	for index: int in source.length():
		var character: String = source[index]
		if index > 0 and character == character.to_upper() and character != " " \
				and source[index - 1] != " ":
			result += " "
		result += character
	result = " ".join(result.strip_edges().split(" ", false))
	if result.to_lower().ends_with(" item"):
		result = result.left(result.length() - 5)
	return result.capitalize()


static func charge_info(item: Node) -> Array:
	if item == null or not is_instance_valid(item):
		return []
	if item.has_method("get_charge_info"):
		var explicit: Variant = item.call("get_charge_info")
		if explicit is Array and (explicit as Array).size() == 2:
			return explicit as Array
	if "_bites_left" in item:
		var bites_max: int = int(_script_constant(item, "TOTAL_BITES", -1))
		if bites_max >= 0:
			return [int(item.get("_bites_left")), bites_max]
	if "_charges" in item and "_max_charges" in item:
		return [int(item.get("_charges")), int(item.get("_max_charges"))]
	if "_charges_left" in item:
		var charge_max: int = int(_script_constant(item, "TOTAL_CHARGES", -1))
		if charge_max >= 0:
			return [int(item.get("_charges_left")), charge_max]
	return []

static func detail(item: Node, count: int = 1) -> String:
	if item == null or not is_instance_valid(item):
		return "Available for storage"
	if item.has_method("get_bottle_badge_info"):
		var info: Dictionary = item.call("get_bottle_badge_info")
		return "%s / %s mL filled  •  %s" % [
			UIFormat.rounded_integer(float(info.get("fill_mL", 0.0))),
			UIFormat.rounded_integer(float(info.get("max_fill_mL", 0.0))),
			UIFormat.water_quality(float(info.get("quality", 0.0)))]
	if count > 1:
		return "%s items in this stack" % UIFormat.integer(count)
	if "_fuel_remaining" in item:
		var fuel := float(item.get("_fuel_remaining"))
		var fuel_max := float(_script_constant(item, "FUEL_UNITS_TOTAL", 100.0))
		return "%s / %s fuel units  •  %s remaining" % [
			UIFormat.rounded_integer(fuel), UIFormat.rounded_integer(fuel_max),
			UIFormat.percent(100.0 * fuel / maxf(fuel_max, 1.0))]
	if "_battery" in item:
		return UIFormat.battery(float(item.get("_battery")))
	if "_charges" in item and "_max_charges" in item:
		return UIFormat.uses(int(item.get("_charges")), int(item.get("_max_charges")))
	if "_charges_left" in item:
		var charge_max := int(_script_constant(item, "TOTAL_CHARGES", int(item.get("_charges_left"))))
		return UIFormat.uses(int(item.get("_charges_left")), charge_max)
	if "_bites_left" in item:
		var serving_max := int(_script_constant(item, "TOTAL_BITES", int(item.get("_bites_left"))))
		return "%d / %d servings remaining" % [int(item.get("_bites_left")), serving_max]
	if "bottle_count" in item:
		return "%s bottles remaining" % UIFormat.integer(int(item.get("bottle_count")))
	if "can_count" in item:
		return "%s cans remaining" % UIFormat.integer(int(item.get("can_count")))
	return "Ready to retrieve"


static func record_detail(data: Dictionary) -> String:
	var details: Array[String] = []
	if data.has("current_fill_mL"):
		details.append("%s mL" % UIFormat.rounded_integer(float(data["current_fill_mL"])))
	if data.has("stored_water_quality"):
		details.append(UIFormat.water_quality_short(float(data["stored_water_quality"])))
	elif data.has("filter_quality"):
		details.append(UIFormat.water_quality_short(float(data["filter_quality"])))
	elif data.has("_fuel_remaining"):
		details.append("%s fuel" % UIFormat.percent(float(data["_fuel_remaining"])))
	elif data.has("_battery"):
		details.append(UIFormat.battery_charge(float(data["_battery"])))
	elif data.has("_charges_left"):
		var remaining: int = int(data["_charges_left"])
		details.append(UIFormat.uses(
			remaining, int(data.get("_max_charges", remaining)), false))
	elif data.has("_charges"):
		var charges: int = int(data["_charges"])
		details.append(UIFormat.uses(
			charges, int(data.get("_max_charges", charges)), false))
	elif data.has("_bites_left"):
		var servings: int = int(data["_bites_left"])
		details.append("%s serving%s left" % [
			UIFormat.integer(servings), "" if servings == 1 else "s"])
	elif data.has("fill_value"):
		details.append("%s full" % UIFormat.percent(float(data["fill_value"])))
	if details.size() < 2 and data.has("material"):
		var material: String = String(data["material"]).capitalize()
		if not material.is_empty():
			details.append(material)
	return "  •  ".join(details)

static func signature(item: Node, count: int = 1) -> String:
	if item == null or not is_instance_valid(item):
		return "empty"
	return "%s|%s|%s|%d" % [item.get_instance_id(), title(item), detail(item, count), count]

static func _script_constant(item: Node, constant_name: String, fallback: Variant) -> Variant:
	var script: Script = item.get_script() as Script
	if script != null and script.has_method("get_script_constant_map"):
		return script.get_script_constant_map().get(constant_name, fallback)
	return fallback
