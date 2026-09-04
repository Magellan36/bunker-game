class_name ShopCart
extends RefCounted

signal changed
const MAX_ITEMS := 99
var lines: Dictionary = {}

func quantity(item_id: int) -> int:
	return int(lines.get(item_id, 0))

func change(item_id: int, amount: int) -> bool:
	var total_count := 0
	for count in lines.values():
		total_count += int(count)
	if amount > 0 and total_count >= MAX_ITEMS:
		return false
	var next := clampi(quantity(item_id) + amount, 0, MAX_ITEMS)
	if next == quantity(item_id):
		return false
	if next == 0:
		lines.erase(item_id)
	else:
		lines[item_id] = next
	changed.emit()
	return true

func remove(item_id: int) -> void:
	if lines.erase(item_id):
		changed.emit()

func clear() -> void:
	if lines.is_empty():
		return
	lines.clear()
	changed.emit()

func total(catalog: Dictionary) -> int:
	var result := 0
	for item_id in lines:
		result += int(lines[item_id]) * int(catalog.get(item_id, {}).get("price", 0))
	return result
