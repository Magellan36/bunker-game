extends SceneTree
## tools/tests/survivor_select_smoke.gd — New Game survivor selection.
##   godot --headless --path . --script res://tools/tests/survivor_select_smoke.gd
## Drives the real path: pending_new_game → LoadingScreen → MainWorld startup
## → SurvivorSelectScreen (world paused) → pick limits → Confirm → residents
## wait outside with the shown identity (BunkerPhase) → message → reveal
## (unpaused, screen gone); they come in at the seal.

const DRAFT_PATH := "res://scripts/ui/new_game/SurvivorDraft.gd"
var failures: int = 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		failures += 1
		push_error("FAIL: " + what)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var draft: GDScript = load(DRAFT_PATH)
	# ── Data ──
	var rolled: Array = draft.call("roll")
	var names: Dictionary = {}
	var all_have_trait := true
	for c: Dictionary in rolled:
		names[c["name"]] = true
		all_have_trait = all_have_trait and not (c["words"] as Array).is_empty() \
			and int(c["revealed"]) < (c["words"] as Array).size()
	_check(rolled.size() == 6 and names.size() == 6, "six candidates with distinct names")
	_check(all_have_trait, "every candidate has at least one trait to reveal")
	var one: Dictionary = draft.call("daily_consumption", 1)
	_check(absf(float(one["cans"]) - 1.3344) < 0.01 and absf(float(one["bottles"]) - 1.161) < 0.01,
		"one person: %.2f cans, %.2f bottles a day" % [one["cans"], one["bottles"]])
	_check(String(draft.call("estimate_text", 4, false)) ==
		"Current bunker population would consume 5.3 cans of food and 4.6 bottles of water a day, on average.",
		"estimate wording for four people")
	_check(String(draft.call("estimate_text", 1, true)).ends_with(" This is not mandatory."),
		"not-mandatory variant appends the line")

	# ── Real new-game path ──
	root.get_node("WorldManager").set("pending_new_game", true)
	change_scene_to_file("res://scenes/ui/LoadingScreen.tscn")
	var screen: Node = null
	for i: int in 3000:
		await process_frame
		for child: Node in root.get_children():
			if child.get_script() != null and (child.get_script() as Script).resource_path.ends_with("SurvivorSelectScreen.gd"):
				screen = child
		if screen != null:
			break
	_check(screen != null, "selection screen appears after loading a new game")
	if screen == null:
		quit(1)
		return
	_check(paused, "world is paused while choosing")
	_check(not bool(root.get_node("WorldManager").get("pending_new_game")), "new-game flag consumed")
	for i: int in 90:
		await process_frame
	var world: Node = get_first_node_in_group("main_world")
	_check(world != null and current_scene == world, "world handed over beneath the selection")
	_check(get_nodes_in_group("npc").is_empty(), "no residents before Confirm")

	var cards: Array = screen.call("get_cards")
	var candidates: Array = screen.call("get_candidates")
	_check(cards.size() == 6, "six cards")
	var first_traits: Node = (cards[0] as Node).get_node("Box/Traits")
	var revealed := 0
	var hidden := 0
	for chip: Node in first_traits.get_children():
		if bool(chip.get_meta("hidden", false)):
			hidden += 1
		else:
			revealed += 1
	_check(revealed == 1 and hidden == (candidates[0]["words"] as Array).size() - 1,
		"one trait shown, the rest greyed (%d shown, %d hidden)" % [revealed, hidden])

	var estimate := screen.get_node("Content/Estimate") as Label
	_check(estimate.text.begins_with("Current bunker population would consume 1.3 cans"),
		"estimate counts the player alone at first")
	for i: int in [0, 2, 4]:
		(cards[i] as Button).button_pressed = true
	await process_frame
	_check((cards[1] as Button).disabled and (cards[3] as Button).disabled and (cards[5] as Button).disabled,
		"after three picks the others are greyed out")
	(cards[1] as Button).button_pressed = true
	await process_frame
	_check(not (cards[1] as Button).button_pressed, "a fourth pick is refused")
	_check(estimate.text.begins_with("Current bunker population would consume 5.3 cans"),
		"estimate covers three survivors plus the player")
	(cards[2] as Button).button_pressed = false
	await process_frame
	_check(not (cards[1] as Button).disabled, "deselecting re-enables the others")
	(cards[5] as Button).button_pressed = true
	await process_frame
	var picked: Array = [candidates[0], candidates[4], candidates[5]]

	(screen.get_node("Content/Confirm") as Button).emit_signal("pressed")
	await process_frame
	## A New Game is in preparation (BunkerPhase): the picks wait outside and
	## come in when the player leaves through the hatch.
	_check(get_nodes_in_group("npc").is_empty(), "nobody spawns before the apocalypse")
	var phase: Node = get_first_node_in_group("bunker_phase")
	var waiting: Array = phase.get("pending_survivors") if phase != null else []
	_check(waiting.size() == 3, "three survivors wait for the seal (%d)" % waiting.size())
	var matched := 0
	for c: Dictionary in picked:
		for w: Dictionary in waiting:
			if String(w["name"]) == String(c["name"]) and int(w["age"]) == int(c["age"]) \
					and String(w["gender"]) == String(c["gender"]) \
					and (w["personality"] as Dictionary) == (c["personality"] as Dictionary):
				matched += 1
	_check(matched == 3, "they keep the name, age, body and traits shown on their cards")
	var arrived: Array = phase.call("seal") if phase != null else []
	_check(arrived.size() == 3 and get_nodes_in_group("npc").size() == 3, "all three come in at the seal")
	var message := screen.get_node("Message") as Label
	await create_timer(0.6, true).timeout
	_check(message.modulate.a > 0.5 and message.text == "Survivors will join when the apocalypse begins.",
		"message fades in")
	for i: int in 70:
		await create_timer(0.1, true).timeout
		if not is_instance_valid(screen):
			break
	_check(not is_instance_valid(screen), "selection screen leaves after the reveal")
	_check(not paused, "world unpaused on reveal")

	if failures == 0:
		print("SURVIVOR_SELECT_SMOKE_OK")
	quit(1 if failures > 0 else 0)
