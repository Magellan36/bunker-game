extends SceneTree
## Headless inventory HUD contract smoke. Run with:
## godot --headless --path . --script res://tools/tests/inventory_hud_polish_smoke.gd

const INVENTORY_HUD_SCRIPT: GDScript = preload("res://scripts/ui/inventory/InventoryHUD.gd")
const FLASHLIGHT_SCRIPT: GDScript = preload("res://scripts/world/items/Flashlight.gd")
const WATER_BOTTLE_SCRIPT: GDScript = preload("res://scripts/world/items/WaterBottle.gd")
const FOOD_CAN_SCRIPT: GDScript = preload("res://scripts/world/items/FoodCan.gd")
const BANDAGE_SCRIPT: GDScript = preload("res://scripts/world/items/Bandage.gd")
const ANTIBIOTICS_SCRIPT: GDScript = preload("res://scripts/world/items/Antibiotics.gd")
const SPLINT_SCRIPT: GDScript = preload("res://scripts/world/items/Splint.gd")
const TRAUMA_KIT_SCRIPT: GDScript = preload("res://scripts/world/items/TraumaKit.gd")

var _failures: int = 0


class MockInventory:
	extends Node
	var slots: Array = [null, null, null, null]


class MockItem:
	extends Node
	signal charge_changed()
	var display_name: String = "Test Item"
	var hud_state: Dictionary = {"kind": "none"}

	func get_display_name() -> String:
		return display_name

	func get_inventory_hud_state() -> Dictionary:
		return hud_state


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud: Control = INVENTORY_HUD_SCRIPT.new() as Control
	var inventory: MockInventory = MockInventory.new()
	var bottle: MockItem = MockItem.new()
	bottle.display_name = "Water Bottle"
	bottle.hud_state = {"kind": "liquid", "fraction": 0.72, "quality": 92.0}
	var flashlight: MockItem = MockItem.new()
	flashlight.display_name = "Flashlight"
	flashlight.hud_state = {"kind": "battery", "fraction": 0.25}
	var bandage: MockItem = MockItem.new()
	bandage.display_name = "Bandage"
	bandage.hud_state = {"kind": "charges", "current": 2, "maximum": 2, "unit": "use"}
	inventory.slots[0] = flashlight
	inventory.slots[1] = bottle
	inventory.slots[2] = bandage
	root.add_child(inventory)
	root.add_child(hud)
	hud.set("inventory", inventory)
	hud.call("refresh_previews")
	hud.call("set_selected", 1)
	await process_frame

	var constants: Dictionary = INVENTORY_HUD_SCRIPT.get_script_constant_map()
	_check(int(constants.get("SLOT_COUNT", 0)) == 4, "four-slot inventory is preserved")
	_check(is_equal_approx(float(constants.get("SLOT_SIZE", 0.0)), 72.0),
		"approved compact slot size is preserved")
	_check(is_equal_approx(float(constants.get("DRAWER_WIDTH", 0.0)),
		float(constants.get("SLOT_SIZE", -1.0))),
		"identity drawer never exceeds its object tile")
	_check(is_equal_approx(float(constants.get("DRAWER_HEIGHT", 0.0)), 24.0),
		"identity drawer is a compact name-only row")
	_check(int(hud.get("_drawer_slot")) == 1,
		"selection reveals the transient item identity drawer")
	_check(bool(hud.call("_has_low_flashlight")),
		"a flashlight at 25 percent enters the low-battery pulse state")
	var liquid_state: Dictionary = hud.call("_item_hud_state", bottle) as Dictionary
	_check(String(liquid_state.get("kind", "")) == "liquid"
		and is_equal_approx(float(liquid_state.get("fraction", 0.0)), 0.72),
		"water fill and quality reach the circular gauge contract")
	var charge_state: Dictionary = hud.call("_item_hud_state", bandage) as Dictionary
	_check(int(charge_state.get("current", 0)) == 2
		and int(charge_state.get("maximum", 0)) == 2,
		"consumable charge pips receive current and maximum values")
	_check(UIKit.Domain.INVENTORY == 4, "inventory notification domain is additive")

	hud.free()
	inventory.free()
	if _failures == 0:
		print("INVENTORY_HUD_POLISH_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("INVENTORY_HUD_POLISH_SMOKE_FAIL: %s" % message)
