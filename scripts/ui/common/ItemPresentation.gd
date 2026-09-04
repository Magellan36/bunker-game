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
	if count > 1:
		return "%d items in this stack" % count
	if "_charges" in item and "_max_charges" in item:
		return "%d / %d uses remaining" % [int(item.get("_charges")), int(item.get("_max_charges"))]
	if "bottle_count" in item:
		return "%d bottles remaining" % int(item.get("bottle_count"))
	if "can_count" in item:
		return "%d cans remaining" % int(item.get("can_count"))
	return "Ready to retrieve"

static func signature(item: Node, count: int = 1) -> String:
	if item == null or not is_instance_valid(item):
		return "empty"
	return "%s|%s|%s|%d" % [item.get_instance_id(), title(item), detail(item, count), count]
