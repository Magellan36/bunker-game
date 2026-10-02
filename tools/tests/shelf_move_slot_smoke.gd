extends SceneTree
## tools/tests/shelf_move_slot_smoke.gd — move a stack between shelf slots.
##   godot --headless --path . --script res://tools/tests/shelf_move_slot_smoke.gd
## A real Shelving + FoodCans: slot rules, the resident stamp, the claim
## guard, the out → across → in path ending on the new slot's pose, and the
## StorageUI move mode (Move → choose a slot → Esc cancels, not closes).

const SHELF := "res://scripts/world/furniture/Shelving.gd"
const CAN := "res://scripts/world/items/FoodCan.gd"
const ITEM_USER := "res://scripts/npc/NPCItemUser.gd"
var failures: int = 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		failures += 1
		push_error("FAIL: " + what)


func _initialize() -> void:
	_run.call_deferred()


func _can() -> RigidBody3D:
	var can: RigidBody3D = (load(CAN) as GDScript).new()
	root.add_child(can)
	return can


func _run() -> void:
	var world := Node3D.new()
	world.add_to_group("world")
	root.add_child(world)
	var shelf: Node3D = (load(SHELF) as GDScript).new()
	world.add_child(shelf)
	var player := Node3D.new()
	player.add_to_group("player")
	world.add_child(player)
	player.global_position = Vector3(0, 1, 2)   ## in front (+Z)
	await process_frame
	var helper := Node.new()
	root.add_child(helper)
	var cans: Array = []
	for i: int in 3:
		var can := _can()
		cans.append(can)
		shelf.call("npc_try_place_item", helper, can, 0)
	var odd := _can()
	shelf.call("npc_try_place_item", helper, odd, 2)
	await create_timer(0.4).timeout
	var slots: Array = shelf.get("slots")
	_check((slots[0] as Array).size() == 3 and (slots[2] as Array).size() == 1, "setup: 3 cans in slot 0, 1 in slot 2")

	# ── Rules ──
	_check(shelf.call("can_move_slot", 0, 1), "empty slot is a valid target")
	_check(shelf.call("can_move_slot", 0, 2), "same-type stack with room is a valid target")
	_check(not shelf.call("can_move_slot", 1, 0), "an empty slot has nothing to move")
	_check(not shelf.call("can_move_slot", 0, 0), "a slot can't move onto itself")
	var item_user: GDScript = load(ITEM_USER)
	item_user.call("claim_item", cans[1], helper)
	_check(not shelf.call("can_move_slot", 0, 1), "a stack a resident has claimed won't move")
	_check(not shelf.call("can_move_slot", 2, 0), "nothing moves onto a claimed stack")
	item_user.call("release_item", cans[1])

	# ── Move (whole stack, stamped, three-step path) ──
	var moved: Array = []
	shelf.connect("item_moved", func(_f: int, _t: int, it: Node) -> void: moved.append(it))
	var start_z: float = shelf.to_local((cans[0] as Node3D).global_position).z
	_check(shelf.call("move_slot", 0, 1, player), "move_slot accepts the move")
	_check((slots[0] as Array).is_empty() and (slots[1] as Array).size() == 3, "the whole stack changes slots at once")
	_check(moved.size() == 3, "item_moved fires per item")
	var stamped := true
	for can: Node in cans:
		stamped = stamped and can.has_meta("player_placed_h")
	_check(stamped, "moved items carry the player-placed stamp")
	var peak_z: float = start_z
	for f: int in 40:
		await process_frame
		peak_z = maxf(peak_z, shelf.to_local((cans[0] as Node3D).global_position).z)
	_check(peak_z > 0.85 * 0.5 + 0.1, "item travels out past the shelf front toward the player (z %.2f)" % peak_z)
	await create_timer(0.8).timeout
	var pose: Array = shelf.call("_slot_pose", cans[0], 1, 0)
	_check((cans[0] as Node3D).global_position.distance_to(pose[0]) < 0.01, "item settles on the new slot's pose")
	_check(not (cans[0] as Node).has_meta("_shelf_move_tween"), "move tween cleaned up")

	# ── StorageUI move mode ──
	var ui: CanvasLayer = (load("res://scripts/ui/inventory/StorageUI.gd") as GDScript).new()
	root.add_child(ui)
	await process_frame
	ui.open(shelf)
	await process_frame
	var cards: Array = ui.get("_cards")
	var move: Button = ui.get("_move")
	var order: Array = (shelf.call("get_ui_config") as Dictionary).get("display_order", [])
	var visual_of := func(data: int) -> int: return order.find(data) if not order.is_empty() else data
	var src: int = visual_of.call(1)
	var dst: int = visual_of.call(4)
	_check(move.visible, "shelves offer Move")
	ui.call("_select", src)
	_check(not move.disabled, "Move is available for a movable stack")
	move.emit_signal("pressed")
	await process_frame
	_check(int(ui.get("_moving_from")) == src and move.text == "Cancel", "Move enters move mode")
	_check(not (ui.get("_controller_nav") as ControllerUINavigation).close_on_cancel, "Esc/B cancel the move, not the panel")
	_check((cards[visual_of.call(3)] as Control).modulate.a > 0.9 and (cards[visual_of.call(2)] as Control).modulate.a > 0.9,
		"empty and same-type slots stay lit as targets")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	ui.call("_input", esc)
	_check(ui.is_open and int(ui.get("_moving_from")) == -1, "Esc cancels the move and keeps the panel open")
	move.emit_signal("pressed")
	(cards[dst] as Button).emit_signal("pressed")
	_check((slots[4] as Array).size() == 3 and (slots[1] as Array).is_empty(), "choosing a slot moves the stack on the shelf")
	_check(int(ui.get("_selected_visual")) == dst and int(ui.get("_moving_from")) == -1, "selection follows the item to its new slot")
	await create_timer(0.6).timeout
	_check((cards[dst] as Control).modulate.a > 0.99 and ui.get("_ghost") == null, "the card glide lands and clears")
	ui.close()
	ui.free()

	if failures == 0:
		print("SHELF_MOVE_SLOT_SMOKE_OK")
	quit(1 if failures > 0 else 0)
