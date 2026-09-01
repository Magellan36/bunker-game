extends Node3D
class_name InteractionSystem
## InteractionSystem.gd
## Handles pickup, drop, world interaction, inventory storing, and slot scrolling.
## Scroll wheel cycles through inventory slots.
## E is a pure instant tap-to-use/interact key. G is the instant store/put-away key.
## Scroll auto-stores/retrieves items.
##
## KEY DESIGN: inventory items stay in their slot even while held.
## activate_item()   → makes item visible/physics-on, keeps it in slot
## deactivate_item() → hides item back, keeps it in slot
## remove_item()     → only called on world-drop (clears slot)
## This means the HUD always shows all 4 slots correctly, and scrolling
## never reshuffles slot positions.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var hold_height: float       = 0.8

# ─── Node refs ────────────────────────────────────────────────────────────────
@onready var hold_point: Node3D      = $HoldPoint
@onready var detect_area: Area3D     = $DetectArea
@onready var player: CharacterBody3D = get_parent()

## Phase 1 (Aug 2026) extraction — see InteractionProximityScan.gd's own
## header comment for what moved and why.
var _proximity: InteractionProximityScan = null
var _focus_glow: InteractionFocusGlow = null

## Set by MainWorld after ready
var prompt: Node     = null
var inventory: Node  = null   ## InventoryManager reference

## Set by MainWorld — used to highlight the selected slot in the HUD
var inventory_hud: Node = null

## Set by MainWorld — when true, all interaction input is suppressed
var build_mode_active: bool = false

## Set by MainWorld — ShelfUI node ref; checked to suppress input while open
var shelf_ui: Node = null

## Set by MainWorld — BasketUI node ref; checked to suppress input while open
var basket_ui: Node = null

## Set by MainWorld — ResearchStationUI node ref; checked to suppress input
## while open (Aug 2026, Research Station Foundation pass)
var research_ui: Node = null

# ─── State ────────────────────────────────────────────────────────────────────
var held_item: RigidBody3D = null
var _world_root: Node3D    = null

## If held_item came from inventory, track which slot so we can deactivate it
## when swapping away. -1 means the item was picked up fresh from the world.
var _held_from_slot: int = -1

## True while the player is holding E down. E itself is a pure instant tap
## (on_use/on_interact fires on press, not on release) — this flag only
## drives per-frame continuous-hold actions on the held item, e.g.
## FuelCan.refuel_tick(). It no longer gates any store behavior (see G).
var _is_holding_e: bool = false

## ── Research Station chute hold-to-feed (Aug 2026) ─────────────────────────
## Feeding an item into the chute is a HOLD, not a tap: pressing F/X while
## holding a feedable item near the chute starts a CHUTE_TAP_WINDOW tap window
## (release within it = the normal F action: shelf-store/drop), then the press
## is considered "held" and a CHUTE_HOLD_DURATION ring-fill completes the
## feed. This prevents accidental feeds when the player taps F/X near the
## chute intending to drop/pick up instead. Only the chute-feed case is gated —
## every other F/X use stays press-to-fire.
enum ChuteFeedState { IDLE, TAP_PENDING, HOLDING }
const CHUTE_TAP_WINDOW:   float = 0.5   ## grace before the press is "held"
const CHUTE_HOLD_DURATION: float = 1.0   ## ring fill to completion (after the tap window)
var _chute_feed_state: int = ChuteFeedState.IDLE
var _chute_feed_elapsed: float = 0.0
var _chute_feed_target: Node3D = null

## Currently selected inventory slot (-1 = none)
var selected_slot: int = -1

## Medical item injury-selection submenu (Aug 2026) — see
## docs/systems/medical/README.md's "Injury-selection submenu". Opened by
## a held medical item's own on_use() (e.g. Bandage.gd) calling
## open_medical_submenu() below, instead of applying treatment directly —
## which body part to target is itself a player choice. Deliberately
## NON-modal: player movement is untouched (movement input never routes
## through this file's _unhandled_input() dispatch at all), only the
## discrete E/F/G/pickup actions this file already owns get intercepted
## while it's open — see _unhandled_input()'s own guard below.
var _medical_submenu_open: bool      = false
var _medical_submenu_item: Node      = null   ## the held item (e.g. a Bandage) that opened it
var _medical_submenu_highlight: int  = 0      ## controller-only — currently highlighted line index

## Highlight color for the controller-focused line in the submenu text —
## sourced from the shared theme's blue UI accent (UI/colors/accent_toggle,
## the same Color(0.3, 0.68, 1.0) reused across PowerPriorityUI/
## PowerTerminalUI/WaterDispenserUI for toggle/selected states), not a
## hardcoded literal, so it stays in lockstep if the theme's blue ever
## changes. Resolved once in _ready() since UIKit.theme_color() isn't a
## compile-time call; falls back to the same literal value if the theme
## key is ever missing.
var _medical_submenu_highlight_hex: String = "#4dadff"

func _ready() -> void:
	hold_point.position = Vector3(0.0, hold_height, -1.0)
	_world_root = get_tree().get_first_node_in_group("world")
	detect_area.body_entered.connect(_on_body_entered)
	detect_area.body_exited.connect(_on_body_exited)
	_proximity = InteractionProximityScan.new(self)
	_focus_glow = InteractionFocusGlow.new()
	add_child(_focus_glow)
	_medical_submenu_highlight_hex = UIKit.theme_color("UI", "accent_toggle", Color(0.3, 0.68, 1.0, 1.0)).to_html(false)

## Tracked interactable bodies currently inside DetectArea.
## Maintained via body_entered / body_exited signals.
## This is the authoritative set — _update_prompt() only considers bodies in here.
var _tracked_bodies: Dictionary = {}   ## Node3D → true
## StaticBody3D nodes currently in prompt range — used to fire set_player_in_range()
## because Jolt Area3D body_entered/exited signals never fire for StaticBody3D.
var _static_in_range: Dictionary = {}  ## Node3D → true

# ─── Medical item injury-selection submenu (Aug 2026) ─────────────────────────
## Called by a held medical item's own on_use() (e.g. Bandage.gd) instead of
## applying treatment directly. Resets highlight to 0 each time it opens.
func open_medical_submenu(item: Node) -> void:
	_medical_submenu_open      = true
	_medical_submenu_item      = item
	_medical_submenu_highlight = 0

func _close_medical_submenu() -> void:
	_medical_submenu_open      = false
	_medical_submenu_item      = null
	_medical_submenu_highlight = 0

## Wraps around both ends (matches ControllerUINavigation's general "stay
## inside the list" feel, though this is a single vertical column, not
## its 2D best-guess navigation — that component isn't used here at all,
## see the design doc's note on why this submenu reuses the hovering-
## prompt pipeline instead of Control-based focus).
func _move_medical_submenu_highlight(delta: int) -> void:
	if _medical_submenu_item == null or not _medical_submenu_item.has_method("get_eligible_targets"):
		return
	var targets: Array = _medical_submenu_item.get_eligible_targets()
	if targets.is_empty():
		return
	_medical_submenu_highlight = wrapi(_medical_submenu_highlight + delta, 0, targets.size())

## Applies the item's real treatment to the target at `idx` in its current
## (worst-severity-first) eligible list, then closes the submenu. Calls
## straight into the item's own apply_to_target() — the exact same
## function real gameplay always uses, no separate debug-only path.
func _select_medical_submenu_target(idx: int) -> void:
	if _medical_submenu_item == null or not _medical_submenu_item.has_method("get_eligible_targets"):
		return
	var targets: Array = _medical_submenu_item.get_eligible_targets()
	if idx < 0 or idx >= targets.size():
		return
	var body_part: int = int((targets[idx] as Dictionary).get("body_part", -1))
	if body_part < 0:
		return
	var item: Node = _medical_submenu_item
	if item.has_method("apply_to_target"):
		item.apply_to_target(body_part)
	## apply_to_target() may destroy the item itself on its last charge
	## (Aug 2026 — Bandage/Splint/Trauma Kit queue_free() when empty;
	## Antibiotics replaces itself with an Empty Bottle instead — see each
	## item's own apply_to_target()). Mirrors the exact same dangling-
	## held_item fix the normal on_use() dispatch above already applies,
	## for the same reason: is_instance_valid() alone misses a queue_free()
	## still pending at end-of-frame.
	if not is_instance_valid(item) or item.is_queued_for_deletion():
		if _held_from_slot != -1 and inventory != null:
			inventory.clear_slot(_held_from_slot)
		held_item       = null
		_held_from_slot = -1
		_is_holding_e   = false
	_close_medical_submenu()

## Builds the multi-line prompt text shown in place of the item's normal
## use/interact/store lines while the submenu is open — see
## _update_prompt()'s CASE 1 branch below, which anchors this to the exact
## same hold_point world_pos any other held-item prompt already uses.
## Keyboard lines use the existing "[1]"."[9]" InteractPrompt key-icon
## tokens (InteractPrompt._is_key_char() already includes 0-9, so this
## needs zero changes to that file); controller mode uses a plain "1."
## prefix instead (XBOX_BUTTONS has no number mapping — a bracketed
## digit would otherwise still render as a KEYBOARD key-cap even in
## controller mode) plus a color-highlighted line for the current D-pad
## selection.
func _build_medical_submenu_text() -> String:
	if _medical_submenu_item == null or not _medical_submenu_item.has_method("get_eligible_targets"):
		return "No eligible injuries"
	var targets: Array = _medical_submenu_item.get_eligible_targets()
	if targets.is_empty():
		return "No eligible injuries"
	if _medical_submenu_highlight >= targets.size():
		_medical_submenu_highlight = targets.size() - 1
	var controller: bool = InputMode.is_controller()
	var lines: Array[String] = []
	for i: int in targets.size():
		var t: Dictionary = targets[i] as Dictionary
		var num: int = i + 1
		var raw: String = "%s (%s)" % [String(t.get("label", "")), String(t.get("detail", ""))]
		var line: String
		if controller:
			line = "%d. %s" % [num, raw]
			if i == _medical_submenu_highlight:
				line = "[color=%s]%s[/color]" % [_medical_submenu_highlight_hex, line]
		else:
			line = "[%d] %s" % [num, raw]
		lines.append(line)
	return "\n".join(lines)

## Owns every discrete input this file normally dispatches (numbers, D-pad,
## confirm, cancel) while the submenu is open — called from the very top of
## _unhandled_input() before the normal E/F/G/pickup dispatch, same
## precedence as the existing shelf/basket/research/NPC modal-UI guard
## immediately above it. Deliberately does NOT touch movement — see this
## var block's own header comment for why that's automatic here.
func _handle_medical_submenu_input(event: InputEvent) -> void:
	# Cancel — Escape (keyboard) or B (controller, ui_cancel action).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_close_medical_submenu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_close_medical_submenu()
		get_viewport().set_input_as_handled()
		return

	# Keyboard — number keys 1-9 select-and-apply immediately.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_select_medical_submenu_target(int(event.keycode) - int(KEY_1))
			get_viewport().set_input_as_handled()
			return

	# Controller — D-pad Up/Down moves the highlight (button indices match
	# ControllerUINavigation.DPAD_UP/DPAD_DOWN exactly, kept as separate
	# literals here rather than a cross-class const reference — same
	# convention PickupableItem.gd uses for its own NPC.gd mass-threshold
	# mirror, see that file's own comment on why).
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == 11:   ## DPAD_UP
			_move_medical_submenu_highlight(-1)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == 12:   ## DPAD_DOWN
			_move_medical_submenu_highlight(1)
			get_viewport().set_input_as_handled()
			return

	# Controller — A confirms the highlighted entry (ui_accept action).
	if event.is_action_pressed("ui_accept"):
		_select_medical_submenu_target(_medical_submenu_highlight)
		get_viewport().set_input_as_handled()
		return

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("interactable") or body.is_in_group("pickup"):
		_tracked_bodies[body] = true
	if body.is_in_group("interactable") and body.has_method("set_player_in_range"):
		body.set_player_in_range(true)

func _on_body_exited(body: Node3D) -> void:
	_tracked_bodies.erase(body)
	if body.is_in_group("interactable") and body.has_method("set_player_in_range"):
		body.set_player_in_range(false)

func _process(delta: float) -> void:
	## Chute-feed tap/hold timer (Aug 2026) — advances the hold, exposes
	## progress to the prompt, and fires the feed on completion. Runs first so
	## the early-return branches below (build mode / job / UI open) also cancel
	## an in-progress hold via the tick's own cancel conditions.
	_tick_chute_feed_hold(delta)
	if build_mode_active:
		return   ## Aug 2026 — BuildModeController now owns the prompt display
				 ## entirely during build mode (Build Station exit prompt).
				 ## Previously this branch also force-hid the prompt every
				 ## frame, which would have fought BuildModeController's own
				 ## prompt.set_prompts() call for the same node.
	## Job Progress Bar (Aug 2026) — while a job is running, this file's
	## normal CASE 1/CASE 2 prompt building and continuous-tick handling are
	## fully suppressed; _tick_job() owns the prompt (see _render_job_prompt())
	## and its own cancellation checks entirely for the duration. See
	## docs/systems/player/README.md's "Job Progress Bar" entry.
	if not _active_job.is_empty():
		_tick_job(delta)
		return
	if _shelf_ui_open() or _basket_ui_open() or _research_ui_open() or _npc_ui_open() \
			or _any_controller_ui_open():
		if prompt != null:
			prompt.hide_prompt()
		return
	## Medical submenu auto-close safety (Aug 2026) — if the held item
	## changed or was freed out from under it (dropped, stored, consumed,
	## knocked out, etc.) while the submenu was open, close it rather than
	## leaving it pointed at a stale/wrong item.
	if _medical_submenu_open:
		if held_item != _medical_submenu_item or not is_instance_valid(_medical_submenu_item):
			_close_medical_submenu()
	_update_prompt()

## True only when the held item + proximity make the Research Station chute
## the ACTUAL F target — the chute is the only non-shelf F-capable body with a
## non-empty prompt while holding (a shelf always wins the held-item F
## priority first, so the hold only ever gates the genuine chute-feed case).
func _chute_feed_condition() -> bool:
	if held_item == null:
		return false
	if _nearest_shelf() != null:
		return false
	return _nearest_f_interactable() != null

## F/X release — a release within the tap window runs the normal F action
## (shelf-store else drop); a release after the hold armed cancels with no
## action.
func _finish_chute_feed_press() -> void:
	if _chute_feed_state == ChuteFeedState.IDLE:
		return
	var was_tap: bool = _chute_feed_state == ChuteFeedState.TAP_PENDING \
			and _chute_feed_elapsed < CHUTE_TAP_WINDOW
	_chute_feed_state = ChuteFeedState.IDLE
	_chute_feed_elapsed = 0.0
	_chute_feed_target = null
	if was_tap and held_item != null:
		var shelf: Node3D = _nearest_shelf()
		if shelf != null and shelf.has_method("on_f_interact"):
			shelf.on_f_interact()
		elif held_item != null:
			_quick_drop()

## Advances the chute-feed tap/hold timer every frame. Cancels if a
## higher-priority state took over, the button was released, or the feed
## condition broke (walked away / item changed). At the end of the tap window
## the ring arms; at the end of the hold duration the feed fires.
func _tick_chute_feed_hold(delta: float) -> void:
	if _chute_feed_state == ChuteFeedState.IDLE:
		return
	if build_mode_active or not _active_job.is_empty() \
			or _shelf_ui_open() or _basket_ui_open() or _research_ui_open() \
			or _npc_ui_open() or _any_controller_ui_open() \
			or not Input.is_action_pressed("pickup") or not _chute_feed_condition():
		_chute_feed_state = ChuteFeedState.IDLE
		_chute_feed_elapsed = 0.0
		_chute_feed_target = null
		return
	_chute_feed_elapsed += delta
	if _chute_feed_state == ChuteFeedState.TAP_PENDING:
		if _chute_feed_elapsed >= CHUTE_TAP_WINDOW:
			_chute_feed_state = ChuteFeedState.HOLDING
			_chute_feed_elapsed = 0.0
	elif _chute_feed_state == ChuteFeedState.HOLDING:
		if _chute_feed_elapsed >= CHUTE_HOLD_DURATION:
			var target: Node3D = _chute_feed_target
			_chute_feed_state = ChuteFeedState.IDLE
			_chute_feed_elapsed = 0.0
			_chute_feed_target = null
			if target != null and is_instance_valid(target) and target.has_method("on_f_interact"):
				target.on_f_interact()

## Continuously transfers fuel while the player holds E with a fuel can in hand.
## Fires every frame E is held; FuelCan.refuel_tick() handles the actual transfer.
func _tick_continuous_refuel(delta: float) -> void:
	if not _is_holding_e:
		return
	if held_item == null:
		return
	## Only act when the item supports continuous refuelling.
	if not held_item.has_method("refuel_tick"):
		return
	held_item.refuel_tick(delta)

## Continuously refills a water bottle while the player holds E with it near a
## WaterDispenser. Mirrors _tick_continuous_refuel() exactly — fires every
## frame E is held; WaterBottle.bottle_refill_tick() handles the actual
## transfer + nearest-dispenser lookup (Jul 2026 bottle rework).
func _tick_continuous_bottle_refill(delta: float) -> void:
	if not _is_holding_e:
		return
	if held_item == null:
		return
	if not held_item.has_method("bottle_refill_tick"):
		return
	held_item.bottle_refill_tick(delta)

## Returns true if the shelf UI overlay is open
func _shelf_ui_open() -> bool:
	return shelf_ui != null and shelf_ui.is_open

## Returns true if the basket UI overlay is open
func _basket_ui_open() -> bool:
	return basket_ui != null and basket_ui.is_open

## Returns true if the Research Station UI overlay is open
func _research_ui_open() -> bool:
	return research_ui != null and research_ui.is_open

## Returns true if any NPC talk menu UI is open (Aug 2026). Each NPC lazily
## creates its own menu instance and the player can only talk to one at a
## time, so "any open" is the correct check. Without this, an A/interact
## press while the talk menu is open (e.g. with no button focused) fell
## through to the world interact path, which re-fired NPC.on_interact() and
## rebuilt the menu — making the controller buttons appear dead.
func _npc_ui_open() -> bool:
	for n: Node in get_tree().get_nodes_in_group("npc_talk_ui"):
		if n != null and ("is_open" in n) and bool(n.get("is_open")):
			return true
	return false

## True while ANY controller-nav UI is open (Aug 2026). Every modal UI
## (storage, power, water, farming, research, NPC talk, pause, admin,
## character creation, …) attaches a ControllerUINavigation, which registers
## in the "controller_ui_nav" group while its ui_root is visible. While one
## is open, A must belong to IT until it closes (exit click, B, or
## walk-away) — a press with nothing focused must never fall through to the
## world interact and pop open a DIFFERENT UI near the player.
func _any_controller_ui_open() -> bool:
	for nav: Node in get_tree().get_nodes_in_group("controller_ui_nav"):
		if nav != null and nav.has_method("is_active"):
			if nav.call("is_active"):
				return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	## Job cancellation (Aug 2026) — any action-trigger press while a job is
	## running cancels it (per design: any other action attempt cancels it
	## too) and consumes the input outright — the cancelled press does NOT
	## also fire the new action same-frame; a second press is required.
	## Movement-attempt cancellation is handled separately, every tick, in
	## _tick_job() (a direct Input.get_vector() poll) since movement doesn't
	## route through this input-event dispatch at all while job-locked. ALL
	## input is swallowed here while a job is active — nothing below this
	## block should run until the job resolves.
	if not _active_job.is_empty():
		if event.is_action_pressed("interact") or event.is_action_pressed("pickup") \
				or event.is_action_pressed("store_item") \
				or event.is_action_pressed("inv_cycle_next") or event.is_action_pressed("inv_cycle_prev") \
				or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
					and ((event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP \
						or (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN)):
			_cancel_job()
			get_viewport().set_input_as_handled()
		return
	if build_mode_active:
		return   ## BuildModeController owns all input while active
	if _shelf_ui_open() or _basket_ui_open() or _research_ui_open() or _npc_ui_open() \
			or _any_controller_ui_open():
		return   ## An open UI owns all input while it's open (Aug 2026 — ANY controller-nav UI)
	## Medical injury-selection submenu (Aug 2026) — owns numbers/D-pad/
	## confirm/cancel while open, same precedence as the modal-UI guard just
	## above, but deliberately NOT added to that guard's own condition or to
	## _process()'s prompt.hide_prompt() branch — this submenu stays visible
	## and non-modal (see the state vars' own header comment for why).
	if _medical_submenu_open:
		_handle_medical_submenu_input(event)
		return
	# ── Scroll wheel — cycle inventory slots ──
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_slot(-1)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_slot(1)
				get_viewport().set_input_as_handled()
				return

	# ── D-pad right/left — cycle inventory slots (controller, Aug 2026) ──
	# Mirrors the wheel so both input styles behave the same: right = scroll
	# down (next slot), left = scroll up (previous slot). Inherits the
	# build-mode/UI-open guards above, same as every other action here.
	if event.is_action_pressed("inv_cycle_next"):
		_scroll_slot(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inv_cycle_prev"):
		_scroll_slot(-1)
		get_viewport().set_input_as_handled()
		return

	# F — pickup / drop / shelf place
	if event.is_action_pressed("pickup"):
		## If shelf UI is open, F does nothing (UI owns interaction)
		if _shelf_ui_open():
			get_viewport().set_input_as_handled()
			return
		## Research Station chute feed is hold-to-fire (Aug 2026) — see the
		## ChuteFeedState header. When holding a feedable item with the chute
		## as the actual F target, swallow the press and start the tap/hold
		## timer instead of feeding instantly. A tap (release within
		## CHUTE_TAP_WINDOW) runs the normal F action on release.
		if _chute_feed_condition():
			_chute_feed_state = ChuteFeedState.TAP_PENDING
			_chute_feed_elapsed = 0.0
			_chute_feed_target = _nearest_f_interactable()
			get_viewport().set_input_as_handled()
			return
		var shelf: Node3D = _nearest_shelf()
		if held_item != null:
			## Cooking Pot held + a nearby open Stove → [F] places it there.
			## Moved from [E] to [F], confirmed Aug 2026. Checked before the
			## shelf fallback so a shelf sitting near a stove can't steal
			## the placement action.
			if "is_cookpot_container" in held_item:
				var open_stove: Node = _find_nearest_open_stove()
				if open_stove != null:
					if _try_place_held_cookpot_on_stove(held_item, open_stove):
						return
			## Holding something — try placing on nearby shelf first, else a
			## nearby non-shelving F-capable interactable (Aug 2026 Option A —
			## e.g. ResearchStationChute feeds the held item), else drop.
			if shelf != null and shelf.has_method("on_f_interact"):
				shelf.on_f_interact()
			else:
				var f_body: Node3D = _nearest_f_interactable()
				if f_body != null:
					f_body.on_f_interact()
				else:
					_quick_drop()
		else:
			## Aug 2026 — shelf-family objects can have meaningful empty-
			## handed F behavior now (TrashCan collecting into a bag).
			## on_f_interact() returns bool: true if it consumed the press,
			## false if it was a no-op (nothing held to store — true for
			## every existing Shelving/EndTable/Dresser call and for a
			## TrashCan with nothing to collect). Checked first, mirroring
			## the held_item branch's existing shelf-priority convention;
			## falls through unchanged to the stove-pot/pickup logic below
			## when false, so this is a no-op for every object except the
			## new trash-can-with-contents case.
			##
			## Aug 2026 fix — this was missing the same distance-fairness
			## check the stove-pot-vs-pickup comparison below already has:
			## previously called unconditionally whenever ANY shelving-group
			## object was in range, so a full trash can could win over a
			## genuinely closer loose item on the ground. Now gated on
			## _nearest_shelf_distance() (flat-XZ, matching how shelf reach
			## is measured everywhere else) vs. _nearest_pickup_distance() —
			## identical head-to-head pattern as stove_dist vs.
			## _nearest_pickup_distance() immediately below.
			if shelf != null and shelf.has_method("on_f_interact"):
				if _nearest_shelf_distance() <= _nearest_pickup_distance():
					if shelf.on_f_interact():
						return
			## Aug 2026 Option A — same pattern for non-shelving F-capable
			## interactables (e.g. ResearchStationChute), empty-handed.
			## _nearest_f_interactable() only returns bodies whose
			## get_f_prompt() is currently non-empty, so this is a no-op for
			## the chute (nothing held → empty prompt) and only matters for
			## bodies with real empty-handed F behavior; distance-fairness
			## vs. a genuinely closer pickup, mirroring the shelf branch.
			var f_body: Node3D = _nearest_f_interactable()
			if f_body != null and f_body.has_method("on_f_interact"):
				if _f_interactable_distance(f_body) <= _nearest_pickup_distance():
					if f_body.on_f_interact():
						return
			## Empty-handed — compare the closest stove-with-pot (if any)
			## against the closest normal pickup candidate and grab whichever
			## is TRULY closer. Confirmed Aug 2026 fix: previously the
			## stove-pot case always won regardless of distance, so a pot
			## across the room could beat a vegetable at the player's feet.
			var host_stove: Node = _find_nearest_stove_with_pot()
			if host_stove != null:
				var stove_dist: float = (host_stove as Node3D).global_position.distance_to(player.global_position)
				if stove_dist <= _nearest_pickup_distance():
					_try_pickup_pot_from_stove(host_stove)
					return
			_try_pickup()

	## F/X release — finalize any in-progress chute-feed tap/hold.
	if event.is_action_released("pickup"):
		if _chute_feed_state != ChuteFeedState.IDLE:
			_finish_chute_feed_press()

	# E — use held item (instant tap) / shelf open / world interact.
	# Pure tap: fires immediately on press, no hold-to-store behavior.
	if event.is_action_pressed("interact"):
		## Held-item E priority (Aug 2026) — an item's own E action ALWAYS
		## wins over a nearby shelf/dresser/end table, unconditionally,
		## whenever it has one. Supersedes the earlier "distance fairness"
		## rule (shelf won only if farther than a basket/cookpot/give
		## target) — that covered those three cases but left every OTHER
		## held item with its own E action (Flashlight, FuelCan, Water
		## Bottle, Food Can, Dish, produce, seeds, fertilizer, soil, filter
		## — anything implementing on_use()) losing E to any shelf within
		## 2.5 m, since the old distance check returned INF — "shelf
		## always wins" — for all of them. The player's own hands take
		## priority full stop; shelf/stove/world-interact are the
		## fallback, reached only once nothing in the player's hand claims
		## E for itself. A held item with genuinely no E action at all
		## (Crate — implements neither on_use() nor on_interact())
		## deliberately still falls through to the shelf check below: E
		## doing nothing at all near a shelf while holding a Crate would
		## be worse, not more correct, especially given how close together
		## furniture gets placed in a bunker.

		## Basket held → E stashes nearest "basket_storable" item instead of item use
		if held_item != null and ("is_basket_container" in held_item):
			_try_add_nearest_to_basket(held_item)
			get_viewport().set_input_as_handled()
			return
		## Cooking Pot held → E either places it on a nearby open Stove, or
		## (if no open stove in range) stashes the nearest "cookpot_storable"
		## item into it. Mirrors the basket branch immediately above exactly.
		if held_item != null and ("is_cookpot_container" in held_item):
			_try_use_held_cookpot(held_item)
			get_viewport().set_input_as_handled()
			return
		## Giveable item held + an NPC in range → E gives it instead of
		## normal item use.
		if held_item != null and NPCItemUser.is_giveable(held_item) and _find_nearest_npc() != null:
			_try_give_to_nearest_npc(held_item)
			get_viewport().set_input_as_handled()
			return
		## Any other held item with its own E action (Flashlight toggle,
		## FuelCan refuel, WaterBottle drink, FoodCan/Dish/produce eat,
		## seed/fertilizer/soil/filter use, etc.) — also takes unconditional
		## priority. This is the branch that previously ran AFTER the shelf
		## check and could lose to it; moved ahead of the shelf check and
		## given an explicit return so it can't fall through into it.
		if held_item != null and (held_item.has_method("on_use") or held_item.has_method("on_interact")):
			# _is_holding_e stays true only to drive per-frame continuous
			# actions (e.g. FuelCan.refuel_tick / bottle refill) — it no
			# longer gates a store action.
			_is_holding_e = true
			if held_item.has_method("on_use"):
				held_item.on_use()
			elif held_item.has_method("on_interact"):
				held_item.on_interact()
			## Aug 2026 fix — on_use()/on_interact() can free `self` as a
			## side effect (DishItem/FarmProduceItem/FoodCan/WaterBottle/
			## SeedItem/FertilizerItem/BagOfSoilItem/PurifierFilterItem all
			## do this when a consumable runs out — confirmed via
			## DishItem.consume_as_food()'s queue_free()). Nothing here
			## ever checked afterward, leaving held_item pointing at a
			## freed object until some UNRELATED system's own per-frame
			## read happened to notice — confirmed root cause of
			## Player.get_held_item()'s "Trying to return a previously
			## freed instance" crash (PlayerModelController.gd polls it
			## every frame, unaware this dispatch just left a gap).
			## Closes it immediately, same frame, before anything else
			## gets a chance to read the dangling reference.
			## Second fix: queue_free() DEFERS the actual free to end-of-
			## frame, so is_instance_valid() alone is still TRUE right
			## after on_use() and the reference dangled until the NEXT
			## frame — exactly the soil-bag-into-tray repro. Added
			## is_queued_for_deletion() to catch pending frees too (the
			## `or` short-circuits, so it only runs when the item is
			## still valid).
			if not is_instance_valid(held_item) or held_item.is_queued_for_deletion():
				## Third fix (Aug 2026): items stay in their slot even while
				## held, so a consumed-and-freed item left its SLOT dangling
				## too — the next inventory_changed handed the dead ref to
				## the HUD previews (ItemPreviewKit.set_item crash). Clear
				## the slot before resetting the held state.
				if _held_from_slot != -1 and inventory != null:
					inventory.clear_slot(_held_from_slot)
				held_item       = null
				_held_from_slot = -1
				_is_holding_e   = false
			return

		## Shelf nearby — reached only if empty-handed, or holding
		## something with no E action of its own (Crate, etc. — see
		## header comment).
		##
		## Aug 2026 fix — previously won unconditionally here regardless
		## of true distance to any other nearby interactable (reported
		## bug: shelving stealing E from things genuinely closer to the
		## player). Now fairly compared against the same candidate
		## _try_interact() would otherwise pick, mirroring the existing
		## ready-dish/stove-pot fairness pattern already used in this
		## handler. Metrics aren't identical — shelf distance is
		## intentionally flat-XZ (reach along its whole vertical face,
		## see _nearest_shelf()'s header) vs. the generic candidate's
		## full 3D distance — but this is the same head-to-head "peek
		## both, smaller wins" pattern already used for stove_dist vs.
		## _nearest_pickup_distance() a few lines up; if this metric
		## mismatch ever causes a new edge case, switching
		## _nearest_shelf()/_nearest_shelf_distance() to full 3D is a
		## small, isolated follow-up.
		var shelf: Node3D = _nearest_shelf()
		if shelf != null and shelf.has_method("on_e_interact"):
			var shelf_dist: float = _nearest_shelf_distance()
			var other: Dictionary = _nearest_generic_interactable()
			if shelf_dist <= float(other["dist"]):
				shelf.on_e_interact()
				get_viewport().set_input_as_handled()
				return
			## else: something else is genuinely closer — fall through,
			## the logic below (or _try_interact() at the bottom) picks
			## the real winner instead.

		if held_item != null:
			## Holding something with no E action and no shelf in range —
			## E is a no-op here, matching prior behavior exactly (this
			## was already a no-op via a different code path before this
			## fix — just preserving _is_holding_e's per-frame-continuous-
			## action bookkeeping regardless of whether this item uses it).
			_is_holding_e = true
		else:
			## A ready dish takes priority over other interactables ONLY if
			## it's truly the closest one — same distance-fairness fix
			## already applied to the [F] stove-pot pickup case.
			var ready_pot: Node = _find_nearest_ready_pot()
			if ready_pot != null:
				var pot_dist: float = (ready_pot as Node3D).global_position.distance_to(player.global_position)
				if pot_dist <= _nearest_interact_distance():
					_try_take_dish(ready_pot)
					return
			_try_interact()

	if event.is_action_released("interact"):
		_is_holding_e = false

	# G — store / put away held item (instant, no progress bar). The same
	# button toggles back when empty-handed: it pulls a stored item to hand
	# (prefers the selected slot, falls back to the first occupied one).
	if event.is_action_pressed("store_item"):
		if held_item != null and ("is_basket_container" in held_item):
			if basket_ui != null and basket_ui.has_method("open"):
				basket_ui.open(held_item)
			get_viewport().set_input_as_handled()
			return
		if held_item != null:
			_is_holding_e = false
			if _held_from_slot != -1:
				_put_item_back_to_slot()
			elif inventory != null and not inventory.is_full() and _item_is_storable(held_item):
				_store_item()
			get_viewport().set_input_as_handled()
			return
		## Empty-handed — pull a stored item back to hand.
		if inventory != null:
			var take_from: int = -1
			if selected_slot != -1 and inventory.slots[selected_slot] != null:
				take_from = selected_slot
			else:
				for si in inventory.slots.size():
					if inventory.slots[si] != null:
						take_from = si
						break
			if take_from != -1:
				selected_slot = take_from
				_bring_item_to_hand_from_slot(take_from)
				_update_hud_selection()
				get_viewport().set_input_as_handled()

# ─── Scroll slot logic ────────────────────────────────────────────────────────
func _scroll_slot(direction: int) -> void:
	if inventory == null:
		return

	# Next slot index (wraps 0-3)
	var next_slot: int
	if selected_slot == -1:
		next_slot = 0 if direction > 0 else 3
	else:
		next_slot = (selected_slot + direction + inventory.SLOT_COUNT) % inventory.SLOT_COUNT

	# Deactivate current held item (put it back to hidden/frozen in its slot)
	# but ONLY if it came from inventory — world-pickups stay active until dropped
	if held_item != null and _held_from_slot != -1:
		_put_item_back_to_slot()

	# If a world-held item and we scroll, store it first to free a hand.
	# Non-storable items (crates, cases) always drop — never go into inventory.
	if held_item != null and _held_from_slot == -1:
		if _item_is_storable(held_item):
			# Try to store in the selected slot if empty, otherwise first free
			var store_to: int = selected_slot if (selected_slot != -1 and inventory.slots[selected_slot] == null) \
				else inventory.first_empty_slot()
			if store_to != -1:
				_store_item_to_slot(store_to)
			else:
				_quick_drop()
		else:
			_quick_drop()

	# Bring new slot's item to hand (if occupied)
	if inventory.slots[next_slot] != null:
		_bring_item_to_hand_from_slot(next_slot)

	selected_slot = next_slot
	_update_hud_selection()

## Deactivate held inventory item — it stays in slot but goes hidden/frozen.
func _put_item_back_to_slot() -> void:
	if held_item == null or inventory == null or _held_from_slot == -1:
		return

	_is_holding_e = false

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	# Reset held state on the item itself
	if "is_held" in held_item:
		held_item.is_held = false
	if "_hold_point" in held_item:
		held_item._hold_point = null
	held_item.gravity_scale = 1.0

	# Reset flag — item is no longer being held
	if "from_inventory" in held_item:
		held_item.from_inventory = false
	inventory.deactivate_item(_held_from_slot)

	held_item = null
	_held_from_slot = -1

## Activate an inventory-slot item and bring it to the player's hand.
func _bring_item_to_hand_from_slot(slot: int) -> void:
	if inventory == null:
		return

	var item: RigidBody3D = inventory.activate_item(slot)
	if item == null:
		return

	item.global_position = hold_point.global_position

	held_item = item
	_held_from_slot = slot
	# Remove from tracked set — inventory items re-entering the DetectArea
	# after activation could otherwise show a ghost prompt in Case 2.
	_tracked_bodies.erase(held_item)

	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	# Mark as inventory-held so the item skips its knockout distance check
	if "from_inventory" in held_item:
		held_item.from_inventory = true
	held_item.pickup(hold_point)
	# Pass player reference so items that need facing direction (e.g. flashlight) can track it.
	if held_item.has_method("set_player"):
		held_item.set_player(player)

# ─── Store held item into inventory (explicit, e.g. G-tap or scroll-to-empty) ─
## Store a world-held item into a specific slot.
func _store_item_to_slot(slot: int) -> void:
	if held_item == null or inventory == null:
		return

	_is_holding_e = false

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	held_item.gravity_scale   = 1.0
	held_item.freeze_mode     = RigidBody3D.FREEZE_MODE_STATIC
	held_item.collision_layer = 1
	held_item.collision_mask  = 1
	held_item.linear_velocity = Vector3.ZERO

	inventory.add_item_to_slot(held_item, slot)
	held_item = null
	_held_from_slot = -1

## Store held item into inventory — first available slot (G-tap path).
func _store_item() -> void:
	if held_item == null or inventory == null:
		return

	_is_holding_e = false

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	held_item.gravity_scale   = 1.0
	held_item.freeze_mode     = RigidBody3D.FREEZE_MODE_STATIC
	held_item.collision_layer = 1
	held_item.collision_mask  = 1
	held_item.linear_velocity = Vector3.ZERO

	var stored_slot: int = inventory.add_item(held_item)
	held_item = null
	_held_from_slot = -1

	if stored_slot != -1:
		selected_slot = stored_slot
		_update_hud_selection()

func _update_hud_selection() -> void:
	if inventory_hud != null and inventory_hud.has_method("set_selected"):
		inventory_hud.set_selected(selected_slot)

# ─── Prompt ───────────────────────────────────────────────────────────────────

## Maximum distance at which any prompt is shown (world units).
## Must match InteractPrompt.FADE_END so entries are culled exactly when alpha=0.
const MAX_PROMPT_DIST: float = 3.2

## Maximum number of interact prompts shown at once (empty-handed, Case 2 only).
## When more interactables are in range, only the N closest to the player show —
## keeps the screen from getting crowded/confusing with many overlapping prompts.
const MAX_VISIBLE_PROMPTS: int = 3

# ─── Job Progress Bar system (Aug 2026) ────────────────────────────────────
## Generic timed-interaction engine. Any world object or held item that
## wants a timed interaction (instead of the old instant-on-press behavior)
## calls start_job() on its own resolved InteractionSystem reference — held
## items reach it via `_hold_point.get_parent()` (PickupableItem's own
## established shortcut, see that file), world objects via the player's
## public `interaction_system` var (resolved through the "player" group).
## Deliberately NOT a generic has_method("get_job_duration") hook scanned
## automatically from this file's own dispatch — several job-eligible
## objects (TrashCan, BreakerBox, FarmingTray) branch on more than just
## "is this object job-eligible" before deciding whether to start one, so
## each object decides for itself and calls start_job() directly. See
## docs/systems/player/README.md's "Job Progress Bar" entry for the full
## design and the complete list of converted interactions.
const JOB_DEFAULT_DURATION: float = 1.0

var _active_job: Dictionary = {}   ## {} when no job running; see start_job()
var _player_medical_for_job: PlayerMedical = null   ## lazy-resolved, see _job_speed_mult()

## Starts a timed job. `target` anchors the progress-bar panel and is the
## point range-checked against `job_range` every tick (defaults to
## MAX_PROMPT_DIST, matching every other object's normal interact reach) —
## pass a very large job_range for a held-item-based job (the target isn't
## something you can "walk away from" in the usual sense; movement itself
## is blocked anyway, see below). `on_complete` is called with ZERO
## arguments once the bar fills — bind() whatever the callback needs before
## passing it in. `label` is the text shown in the floating panel while
## charging (e.g. "Turning Stove On..."). The player is locked in place for
## the duration (Player.set_job_locked() — separate from the pause-menu's
## own _movement_locked, see that method's own comment) — per design, a
## future "interacting" animation depends on the player staying put.
## Cancelled (progress reset, nothing committed, movement unlocked,
## on_complete never called) if the player attempts to move, presses any
## other action (E/F/G/scroll), or the target drifts out of job_range — see
## _unhandled_input()'s job-cancel guard and _tick_job()'s own checks.
func start_job(target: Node3D, duration: float, on_complete: Callable, label: String, job_range: float = MAX_PROMPT_DIST) -> void:
	if not _active_job.is_empty():
		_cancel_job()   ## defensive — shouldn't normally be reachable, a job already locks out new job-starts via the input guard
	_active_job = {
		"target":      target,
		"duration":    maxf(duration, 0.001),
		"elapsed":     0.0,
		"on_complete": on_complete,
		"label":       label,
		"range":       job_range,
	}
	if player != null:
		player.set_job_locked(true)
	_render_job_prompt()

func is_job_active() -> bool:
	return not _active_job.is_empty()

## PlayerMedical.get_medical_job_speed_multiplier() — 1.0 (no effect) when
## nothing's active or PlayerMedical hasn't been added to the scene yet.
func _job_speed_mult() -> float:
	if _player_medical_for_job == null or not is_instance_valid(_player_medical_for_job):
		_player_medical_for_job = get_tree().get_first_node_in_group("player_medical") as PlayerMedical
	if _player_medical_for_job == null:
		return 1.0
	return _player_medical_for_job.get_medical_job_speed_multiplier()

func _tick_job(delta: float) -> void:
	var target: Node3D = _active_job.get("target")
	if target != null and not is_instance_valid(target):
		_cancel_job()
		return
	if target != null:
		var job_range: float = float(_active_job.get("range", MAX_PROMPT_DIST))
		if target.global_position.distance_to(player.global_position) > job_range:
			_cancel_job()
			return
	## Movement-attempt cancel — the player is job-locked (see start_job()),
	## so this poll never actually MOVES them; it only detects the attempt
	## and cancels the job, same as any other action press does (see
	## _unhandled_input()). Checked here rather than in Player.gd because
	## movement input doesn't route through _unhandled_input() at all while
	## job-locked (Input.get_vector() is a direct poll, not an input event).
	var move_input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move_input.length_squared() > 0.0:
		_cancel_job()
		return
	_active_job["elapsed"] = float(_active_job["elapsed"]) + delta * _job_speed_mult()
	if float(_active_job["elapsed"]) >= float(_active_job["duration"]):
		_complete_job()
	else:
		_render_job_prompt()

func _cancel_job() -> void:
	if _active_job.is_empty():
		return
	_active_job = {}
	if player != null:
		player.set_job_locked(false)

func _complete_job() -> void:
	var cb: Callable   = _active_job.get("on_complete", Callable())
	var target: Node3D = _active_job.get("target")
	_active_job = {}
	if player != null:
		player.set_job_locked(false)
	if cb.is_valid() and (target == null or (is_instance_valid(target) and not target.is_queued_for_deletion())):
		cb.call()
	## Mirrors the E-dispatch block's own "held item freed itself as a side
	## effect" guard (see that block's Aug 2026 comment) — a job's completion
	## callback can free held_item too (BagOfSoilItem/SeedItem/FertilizerItem/
	## PurifierFilterItem's last charge), so the same dangling-reference
	## cleanup applies here.
	if held_item != null and (not is_instance_valid(held_item) or held_item.is_queued_for_deletion()):
		if _held_from_slot != -1 and inventory != null:
			inventory.clear_slot(_held_from_slot)
		held_item       = null
		_held_from_slot = -1
		_is_holding_e   = false

func _render_job_prompt() -> void:
	if prompt == null or _active_job.is_empty():
		return
	var target: Node3D = _active_job.get("target")
	var pos: Vector3 = target.global_position if target != null and is_instance_valid(target) else player.global_position
	var frac: float = clampf(float(_active_job["elapsed"]) / float(_active_job["duration"]), 0.0, 1.0)
	prompt.set_prompts([{
		"text":      String(_active_job.get("label", "")),
		"world_pos": pos,
		"dist":      0.0,
		"progress":  frac,
	}])



func _update_prompt() -> void:
	if prompt == null:
		return

	## Seated players always see [E] Stand, overriding every other prompt.
	if player.seated_chair != null and is_instance_valid(player.seated_chair):
		if _focus_glow != null:
			_focus_glow.set_target(null)
		prompt.set_prompts([{
			"text":      "[E] Stand",
			"world_pos": player.seated_chair.global_position,
			"dist":      0.0,
			"icons":     [],
		}])
		return

	# ── Guard: held_item freed externally (build mode deconstruct, etc.) ─────
	## is_instance_valid() alone — `held_item != null` does NOT catch a freed
	## reference, which can compare equal to null in Godot 4 (see the same
	## fix in Player.get_held_item).
	if held_item != null and not is_instance_valid(held_item):
		held_item       = null
		_held_from_slot = -1

	# ═════════════════════════════════════════════════════════════════════════
	# CASE 1 — Player is holding an item
	# ═════════════════════════════════════════════════════════════════════════
	if held_item != null:
		var entries: Array            = []
		var item_lines: Array[String] = []

		if _medical_submenu_open and held_item == _medical_submenu_item:
			## Injury-selection submenu (Aug 2026) — replaces the item's normal
			## use/interact/store lines entirely while open. Deliberately reuses
			## this exact same entries-building/anchoring path (item_prompt_pos
			## below is untouched) rather than a separate UI system — per
			## docs/systems/medical/README.md's "Injury-selection submenu": the
			## submenu should hover over the item and move with it/the player
			## exactly like any other held-item prompt already does.
			item_lines.append(_build_medical_submenu_text())
		else:
			# Use prompt (e.g. water bottle drink line)
			if held_item.has_method("get_use_prompt"):
				var up: String = held_item.get_use_prompt()
				if up != "": item_lines.append(up)

			# Interact prompt
			if held_item.has_method("get_interact_prompt"):
				var ip: String = held_item.get_interact_prompt()
				if ip != "": item_lines.append(ip)

			# Store / put-away hint — only add when it adds value
			if _item_is_storable(held_item) or _held_from_slot != -1:
				if _held_from_slot != -1:
					item_lines.append("[G] Put away")
				elif inventory != null and inventory.is_full():
					item_lines.append("[G] Inventory full")
				else:
					item_lines.append("[G] Store")

		# Anchor prompt to hold_point position, not physics body center.
		var item_prompt_pos: Vector3 = hold_point.global_position \
				if hold_point != null else held_item.global_position

		## Aug 2026 fix — CASE 2 (below) already does this lookup for nearby
		## interactables; CASE 1 never did, which is why a held item's own
		## icon row (e.g. CookingPot's 3 ingredient previews) used to vanish
		## the instant it was picked up. Generic — works for any held item
		## that implements get_slot_icon_descriptors(), not cooking-specific.
		var held_icons: Array = []
		if held_item.has_method("get_slot_icon_descriptors"):
			held_icons = held_item.get_slot_icon_descriptors()

		if not item_lines.is_empty():
			entries.append({
				"text":      "\n".join(item_lines),
				"world_pos": item_prompt_pos,
				"dist":      0.0,
				"icons":     held_icons,
			})

		# Shelf nearby — separate panel above the shelf
		var nearby_shelf: Node3D = _nearest_shelf()
		if nearby_shelf != null:
			var shelf_lines: Array[String] = []
			var shelf_fp: String = ""
			if nearby_shelf.has_method("get_f_prompt"):
				shelf_fp = nearby_shelf.get_f_prompt()
			if shelf_fp != "":
				shelf_lines.append(shelf_fp)
			else:
				## Aug 2026 fix — mirrors the same fix already applied to
				## CASE 2's "shelving" handling below, which this block
				## never received (CASE 1 and CASE 2 are separate code
				## paths — this is why holding a storable item still
				## showed both "[F] Store item" and "[E] Open X" together).
				## Only fall back to E when F has nothing to say (not
				## holding a storable item) — while ANYTHING is held, E is
				## bound to the held item's own action above, never to
				## this shelf's on_e_interact(), so showing it alongside a
				## working F prompt was misleading.
				if nearby_shelf.has_method("get_e_prompt"):
					var ep: String = nearby_shelf.get_e_prompt()
					if ep != "": shelf_lines.append(ep)
			if not shelf_lines.is_empty():
				var shelf_pos: Vector3 = nearby_shelf.global_position + Vector3(0.0, 2.3, 0.0)
				if nearby_shelf.has_method("get_prompt_world_pos"):
					shelf_pos = nearby_shelf.get_prompt_world_pos()
				entries.append({ "text": "\n".join(shelf_lines), "world_pos": shelf_pos, "dist": 0.0 })

		# Generic F-capable interactable nearby (Aug 2026 Option A) — e.g.
		# the Research Station chute's feed prompt while holding an item it
		# can accept. Separate panel above the body, mirroring the shelf
		# block above; only appears when get_f_prompt() has something to say.
		var f_body: Node3D = _nearest_f_interactable()
		if f_body != null:
			var f_line: String = f_body.get_f_prompt()
			if not f_line.is_empty():
				var f_pos: Vector3 = f_body.global_position
				if f_body.has_method("get_prompt_world_pos"):
					f_pos = f_body.get_prompt_world_pos()
				var f_entry: Dictionary = { "text": f_line, "world_pos": f_pos, "dist": 0.0 }
				## Hold-to-feed ring (Aug 2026) — the chute prompt carries a
				## hold_progress (0 = icon only, 1 = complete) so InteractPrompt
				## draws the fill ring around the F/X icon during the hold.
				if f_body is ResearchStationChute:
					f_entry["hold_progress"] = (
						clampf(_chute_feed_elapsed / CHUTE_HOLD_DURATION, 0.0, 1.0)
						if _chute_feed_state == ChuteFeedState.HOLDING else 0.0)
				entries.append(f_entry)

		# Basket held → "[E] Add to Basket" over each nearby storable item.
		# CASE 2 further down never runs while something is held (this whole
		# block returns before reaching it), so this can only live here.
		# Reuses _tracked_bodies — the same Area3D-maintained set CASE 2 uses —
		# rather than polling detect_area every frame.
		if "is_basket_container" in held_item:
			for body in _tracked_bodies:
				if not is_instance_valid(body):
					continue
				if not body.is_in_group("basket_storable"):
					continue
				if body.is_in_group("shelved"):
					continue
				if body is RigidBody3D and (body as RigidBody3D).freeze:
					continue
				var bd: float = body.global_position.distance_to(player.global_position)
				if bd > MAX_PROMPT_DIST:
					continue
				entries.append({
					"text":      "[E] Add to Basket",
					"world_pos": body.global_position,
					"dist":      bd
				})

		# Cooking Pot held → "[E] Add to Pot" over each nearby storable food
		# item, PLUS the nearest Stove's own prompt (its normal toggle text,
		# or "DONE"/connection text — [E] now interacts with it normally,
		# confirmed Aug 2026 revert) PLUS a separate "[F] Place Cooking Pot"
		# hint when that stove has an open slot (placement moved from [E]
		# to [F] the same pass). Nothing shows above the held pot itself.
		if "is_cookpot_container" in held_item:
			for body in _tracked_bodies:
				if not is_instance_valid(body):
					continue
				if not body.is_in_group("cookpot_storable"):
					continue
				if body.is_in_group("shelved"):
					continue
				if body is RigidBody3D and (body as RigidBody3D).freeze:
					continue
				var bd: float = body.global_position.distance_to(player.global_position)
				if bd > MAX_PROMPT_DIST:
					continue
				entries.append({
					"text":      "[E] Add to Pot",
					"world_pos": body.global_position,
					"dist":      bd
				})
			var nearby_stove: Node = _find_nearest_stove()
			if nearby_stove != null:
				var stove_pos: Vector3 = (nearby_stove as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
				if nearby_stove.has_method("get_interact_prompt"):
					var stove_txt: String = nearby_stove.get_interact_prompt()
					if not stove_txt.is_empty():
						entries.append({"text": stove_txt, "world_pos": stove_pos, "dist": 0.0})
				if nearby_stove.has_method("has_open_slot") and nearby_stove.has_open_slot():
					entries.append({"text": "[F] Place Cooking Pot", "world_pos": stove_pos, "dist": 0.0})

		# Give to NPC — holding a giveable item (dish, produce, can, or
		# bottle) → "[E] Give <item> to <name>" over each nearby NPC.
		# Mirrors the basket/cookpot blocks above exactly.
		if NPCItemUser.is_giveable(held_item):
			for npc: Node in get_tree().get_nodes_in_group("npc"):
				if not is_instance_valid(npc):
					continue
				var nd: float = (npc as Node3D).global_position.distance_to(player.global_position)
				if nd > MAX_PROMPT_DIST:
					continue
				entries.append({
					"text":      "[E] Give %s to %s" % [held_item.get_display_name(), String(npc.npc_name)],
					"world_pos": (npc as Node3D).global_position + Vector3(0.0, 1.8, 0.0),
					"dist":      nd
				})

		if _focus_glow != null:
			_focus_glow.set_target(null)
		if entries.is_empty():
			prompt.hide_prompt()
		else:
			prompt.set_prompts(entries)
		return

	# ═════════════════════════════════════════════════════════════════════════
	# CASE 2 — Empty-handed: show prompts for nearby interactables
	# ═════════════════════════════════════════════════════════════════════════

	# Purge stale / freed entries (Jolt may skip body_exited on layer change)
	var stale: Array = []
	for body in _tracked_bodies:
		if not is_instance_valid(body):
			stale.append(body)
	for body in stale:
		_tracked_bodies.erase(body)

	var candidates: Array = []
	for body in _tracked_bodies:
		if not is_instance_valid(body):
			continue
		# Shelved items — no prompt; access via shelf menu (E)
		if body.is_in_group("shelved"):
			continue
		if body is RigidBody3D and (body as RigidBody3D).freeze:
			continue
		if not (body.is_in_group("interactable") or body.is_in_group("pickup")):
			continue
		## Aug 2026 (correction) — same gap as _nearest_generic_interactable()'s
		## Pass 1: this candidate builder ALSO has two passes (this one,
		## driven by _tracked_bodies/Area3D signals; the StaticBody3D group
		## scan below it). Grow Light's exclusion previously only lived in
		## the second pass — if a grow light's body_entered ever fires on
		## this Area3D (same "unreliable, not nonexistent" caveat as
		## everywhere else in this file), it was appearing as a prompt
		## candidate here regardless of Ctrl state.
		if body.is_in_group("grow_light") and not FocusMode.is_active():
			continue
		var d: float = body.global_position.distance_to(player.global_position)
		if d > MAX_PROMPT_DIST:
			continue
		candidates.append({ "node": body, "dist": d })

	## Also include nearby StaticBody3D interactables — Jolt Area3D misses them.
	## (Same fix as _try_interact pass 2 — keeps prompts and interaction in sync.)
	##
	## IMPORTANT: We also call set_player_in_range() here because Jolt's Area3D
	## body_entered/body_exited signals never fire for StaticBody3D nodes.
	## Without this, generators (StaticBody3D + "interactable") never receive
	## set_player_in_range(true), so their _process polling and fuel banner
	## never activate.  We track which static nodes are currently in-range so
	## we can fire set_player_in_range(false) when they leave.
	var static_in_range_now: Dictionary = {}

	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node):
			continue
		## StaticBody3D (generators, stoves, etc.) OR a frozen RigidBody3D
		## (e.g. a CookingPot resting on a Stove — the detect_area-based scan
		## above explicitly skips frozen bodies, so without this a frozen pot
		## would never get a prompt at all). The two passes never overlap:
		## the first pass already excludes frozen bodies, so nothing here
		## can be double-added.
		var is_frozen_rigid: bool = node is RigidBody3D and (node as RigidBody3D).freeze
		if not (node is StaticBody3D or is_frozen_rigid):
			continue
		if node.is_in_group("shelved") or node.is_in_group("shelving"):
			continue   ## Shelves handled separately above
		## Aug 2026 — Grow Light produces no prompt at all outside Focus
		## Mode. A standard farming setup (many trays, a grow light over
		## each) fills the view with hovering prompts fast; Ctrl/Focus
		## Mode is the intended way to reach one specifically, so it's
		## fully absent otherwise rather than just de-prioritized. Water
		## Hookup is NOT included in this — fewer of them per bunker,
		## unchanged behavior (see this plan's own scope note).
		if node.is_in_group("grow_light") and not FocusMode.is_active():
			continue
		var sn3: Node3D = node as Node3D
		var sd: float = sn3.global_position.distance_to(player.global_position)

		if sd <= MAX_PROMPT_DIST:
			static_in_range_now[sn3] = true
			## Fire set_player_in_range(true) only on first entry, not every frame.
			if not _static_in_range.has(sn3):
				if sn3.has_method("set_player_in_range"):
					sn3.set_player_in_range(true)
			## Add to prompt candidates
			var already: bool = false
			for existing: Dictionary in candidates:
				if existing["node"] == sn3:
					already = true
					break
			if not already:
				candidates.append({ "node": sn3, "dist": sd })

	## Fire set_player_in_range(false) for any static nodes that left range.
	for gone_node in _static_in_range:
		if not static_in_range_now.has(gone_node) and is_instance_valid(gone_node):
			if gone_node.has_method("set_player_in_range"):
				gone_node.set_player_in_range(false)
	_static_in_range = static_in_range_now

	## Aug 2026 fix — "shelving" group objects (Shelving, End Table, Dresser)
	## used to rely ENTIRELY on Pass 1's _tracked_bodies (Area3D signal-
	## based). That's fragile to spawn timing: a body that spawns already
	## inside the player's Area3D (exactly what happens placing furniture
	## via Build Mode while standing next to it) never fires body_entered,
	## so it never joined _tracked_bodies and never got a prompt until the
	## player walked away and back. CASE 1's _nearest_shelf() already avoids
	## this with a direct group scan every frame — this does the same thing
	## here, but collects every nearby shelving object (not just the single
	## closest) so multiple can appear alongside other prompts, capped by
	## MAX_VISIBLE_PROMPTS same as everything else.
	for node: Node in get_tree().get_nodes_in_group("shelving"):
		if not is_instance_valid(node):
			continue
		var shelf3: Node3D = node as Node3D
		if shelf3 == null:
			continue
		var shelf_d: float = shelf3.global_position.distance_to(player.global_position)
		if shelf_d > MAX_PROMPT_DIST:
			continue
		var shelf_already: bool = false
		for existing: Dictionary in candidates:
			if existing["node"] == shelf3:
				shelf_already = true
				break
		if not shelf_already:
			candidates.append({ "node": shelf3, "dist": shelf_d })

	# Closest first so nearest panel renders on top
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["dist"] < b["dist"])

	# Cap to the N closest so the screen never gets crowded with prompts.
	if candidates.size() > MAX_VISIBLE_PROMPTS:
		candidates = candidates.slice(0, MAX_VISIBLE_PROMPTS)

	var entries: Array = []
	var entry_bodies: Array = []   ## Parallel to entries[] — Focus Mode below
	for cand: Dictionary in candidates:
		var body: Node3D = cand["node"] as Node3D
		var lines: Array[String] = []

		if body.is_in_group("pickup") and body.has_method("get_prompt_text"):
			var pt: String = body.get_prompt_text()
			if pt != "": lines.append(pt)
		elif body.is_in_group("pickup"):
			lines.append("[F] Pick up")

		if body.is_in_group("shelving"):
			var fp: String = ""
			if body.has_method("get_f_prompt"):
				fp = body.get_f_prompt()
			if fp != "":
				lines.append(fp)
			else:
				## Aug 2026 fix — only show "[E] Open X" when there's nothing
				## for F to say instead (i.e. not holding a storable item).
				## Previously both always showed together, which was
				## misleading: while ANYTHING is held, E is bound to the held
				## item's own action (CASE 1 above), never to this object's
				## on_e_interact() — so "[E] Open X" promised something E
				## wouldn't actually do whenever a storable item was held.
				if body.has_method("get_e_prompt"):
					var ep: String = body.get_e_prompt()
					if ep != "": lines.append(ep)
		elif body.is_in_group("interactable") and not body.is_in_group("pickup"):
			if body.has_method("get_f_prompt"):
				var ifp: String = body.get_f_prompt()
				if not ifp.is_empty():
					lines.append(ifp)
			if body.has_method("get_interact_prompt"):
				var ip: String = body.get_interact_prompt()
				if ip != "": lines.append(ip)
			elif body.has_method("get_prompt_text"):
				var pt: String = body.get_prompt_text()
				if pt != "": lines.append(pt)
		elif body.is_in_group("interactable") and body.has_method("get_interact_prompt"):
			var ip: String = body.get_interact_prompt()
			if ip != "": lines.append(ip)

		if lines.is_empty():
			continue

		var prompt_pos: Vector3 = body.global_position
		if body.has_method("get_prompt_world_pos"):
			prompt_pos = body.get_prompt_world_pos()

		var icons: Array = []
		if body.has_method("get_slot_icon_descriptors"):
			icons = body.get_slot_icon_descriptors()

		entries.append({
			"text":      "\n".join(lines),
			"world_pos": prompt_pos,
			"dist":      cand["dist"],
			"icons":     icons,
		})
		entry_bodies.append(body)

	## Aug 2026 v2 — Focus Mode, broadened. Previously only tagged whatever
	## E would fire on (_resolve_current_e_target(), now removed), which
	## meant pickup-only objects with no on_interact() at all — Test
	## Crate ("pickup" group only), Fuel Can ("interactable" group but no
	## on_interact(), only on_use() for while held) — never got a Focus
	## Mode prompt even though F still works on them and they show fine
	## normally. Focus target is now simply the CLOSEST entry with an
	## actual displayable prompt: entries[] is already built in
	## candidates' closest-first order, so that's just index 0.
	##
	## Aug 2026 v3 (corrected — a prior version of this was lost to a
	## merge, then broadened per direct instruction) — Grow Light (both
	## tiers, "normal" and "pro" — same GrowLight.gd script either way,
	## both join the single "grow_light" group regardless of tier) and
	## Water Hookup are unconditional #1 Focus Mode priority whenever
	## EITHER is anywhere in the current prompt set at all — not the
	## previous narrower "only if the closest entry happens to be a
	## FarmingTray" swap. Both are mounted awkwardly (grow lights on the
	## ceiling directly above their tray, water hookups high on the wall)
	## and would otherwise almost never be entries[0] on raw distance
	## alone — this unconditional-while-Ctrl-is-held rule is the entire
	## reason Focus Mode is useful for reaching either. Deliberately does
	## NOT touch _nearest_generic_interactable() (real E dispatch) at
	## all — outside Focus Mode, both return to ordinary fair-distance
	## priority, i.e. close to never winning, by design.
	var focus_idx: int = -1
	if not entries.is_empty():
		focus_idx = 0
		for i: int in entry_bodies.size():
			if entry_bodies[i].is_in_group("grow_light") or entry_bodies[i].is_in_group("water_hookup"):
				focus_idx = i
				break
	for i: int in entries.size():
		entries[i]["is_focus_target"] = (i == focus_idx)

	## Focus Mode target glow (Aug 2026) — same Ctrl check already used by
	## _nearest_generic_interactable()'s E-interact parity fix. Applies to
	## ANY current focus target, not just Grow Light/Water Hookup — the
	## glow follows is_focus_target generically, whatever object that
	## happens to land on.
	if _focus_glow != null:
		if focus_idx != -1 and FocusMode.is_active():
			_focus_glow.set_target(entry_bodies[focus_idx])
		else:
			_focus_glow.set_target(null)

	if entries.is_empty():
		prompt.hide_prompt()
	else:
		prompt.set_prompts(entries)

# ─── Storable check ───────────────────────────────────────────────────────────
## An item is storable if it is in the inventory_item group AND its can_store()
## method returns true (or doesn't exist — assumed storable).
## Items like FuelCan override can_store() → false to block inventory storage.
func _item_is_storable(item: RigidBody3D) -> bool:
	if not item.is_in_group("inventory_item"):
		return false
	if item.has_method("can_store"):
		return item.can_store()
	return true

# ─── Nearest shelf via group scan (Area3D misses StaticBody3D reliably) ───────
func _nearest_shelf() -> Node3D:
	var shelves: Array      = get_tree().get_nodes_in_group("shelving")
	var closest: Node3D     = null
	var closest_dist: float = 2.5   ## Max reach (flat XZ distance, metres)
	var player_xz: Vector2  = Vector2(player.global_position.x, player.global_position.z)
	for shelf: Node in shelves:
		if not is_instance_valid(shelf):
			continue
		if shelf is Node3D:
			var s3: Node3D    = shelf as Node3D
			var shelf_xz: Vector2 = Vector2(s3.global_position.x, s3.global_position.z)
			var d: float = shelf_xz.distance_to(player_xz)
			if d < closest_dist:
				closest_dist = d
				closest = s3
	return closest

## Distance-only twin of _nearest_shelf() — same flat-XZ metric (reach
## along the shelf's whole vertical face, not full 3D distance to its
## origin — see the header comment above). Used by the E-handler's
## shelf-fairness check below.
## Returns INF if no shelf is in range.
func _nearest_shelf_distance() -> float:
	var shelf: Node3D = _nearest_shelf()
	if shelf == null:
		return INF
	var player_xz: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	var shelf_xz: Vector2  = Vector2(shelf.global_position.x, shelf.global_position.z)
	return shelf_xz.distance_to(player_xz)

# ─── Nearest generic F-capable interactable (Aug 2026 Option A) ────────────
## Non-shelving "interactable" bodies that implement the F contract
## (get_f_prompt + on_f_interact) get F dispatch the same way shelves do.
## Excludes the shelving group (already handled by _nearest_shelf() above)
## and requires get_f_prompt() to be currently non-empty, so a body with
## nothing F can do right now (e.g. ResearchStationChute with nothing
## held — its forwarded get_chute_f_prompt() returns "") never claims the
## key. Same flat-XZ 2.5 m reach as _nearest_shelf().
func _nearest_f_interactable() -> Node3D:
	var player_xz: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	var closest: Node3D     = null
	var closest_dist: float = 2.5
	for body: Node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(body):
			continue
		if not (body is Node3D):
			continue
		var b3: Node3D = body as Node3D
		if b3.is_in_group("shelving"):
			continue
		if not (b3.has_method("get_f_prompt") and b3.has_method("on_f_interact")):
			continue
		if b3.get_f_prompt().is_empty():
			continue
		var d: float = Vector2(b3.global_position.x, b3.global_position.z).distance_to(player_xz)
		if d < closest_dist:
			closest_dist = d
			closest = b3
	return closest

func _f_interactable_distance(body: Node3D) -> float:
	var player_xz: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	return Vector2(body.global_position.x, body.global_position.z).distance_to(player_xz)

## E while holding a Basket — finds the nearest "basket_storable" world item
## in reach and stashes it, instead of calling the basket's own on_use().
func _try_add_nearest_to_basket(basket: Node) -> void:
	## held_item / shelved / frozen filtering now lives in
	## InteractionProximityScan (Phase 1, Aug 2026) — see its header comment.
	var closest: RigidBody3D = _proximity.nearest_body_in_group("basket_storable") as RigidBody3D

	var hud: Node = get_tree().get_first_node_in_group("hud")

	if closest == null:
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Nothing nearby to store")
		return

	if not basket.try_add_item(closest):
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Basket full")

## Called when the player presses [E] while holding a Cooking Pot.
## Confirmed Aug 2026 priority order:
##   1. Held pot has a finished dish → retrieve it. Always wins over
##      everything else below.
##   2. A nearby Stove → interact with it normally (the manual on/off
##      toggle). This REVERTS the earlier "E is entirely blocked near a
##      stove while holding the pot" behavior — placement moved to [F],
##      see _try_place_held_cookpot_on_stove().
##   3. Otherwise, stash the nearest "cookpot_storable" item (unchanged).
func _try_use_held_cookpot(pot: Node) -> void:
	if pot.has_method("is_dish_ready") and pot.is_dish_ready():
		_try_take_dish_from_held_pot(pot)
		return
	var stove: Node = _find_nearest_stove()
	if stove != null and stove.has_method("on_interact"):
		stove.on_interact()
		return
	_try_add_nearest_to_cookpot(pot)

## Places a HELD Cooking Pot onto `stove` via [F] (moved from [E], confirmed
## Aug 2026). Returns false if the stove filled up between the caller's
## check and this call, so the caller falls through to normal shelf/drop
## handling instead of silently doing nothing.
func _try_place_held_cookpot_on_stove(pot: Node, stove: Node) -> bool:
	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)
	if not stove.try_place_pot(pot):
		return false
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false
	return true

## Identical mechanism to _try_add_nearest_to_basket() — "cookpot_storable"
## group instead of "basket_storable", pot.try_add_item() instead of
## basket.try_add_item().
func _try_add_nearest_to_cookpot(pot: Node) -> void:
	## held_item / shelved / frozen filtering lives in
	## InteractionProximityScan (Phase 1, Aug 2026) — see its header comment.
	## Predicate additionally excludes empty Food Cans/Water Bottles
	## (confirmed Aug 2026 fix) — filtering during the SEARCH itself means
	## an empty item sitting closest doesn't block the action entirely; the
	## next-nearest ELIGIBLE item is found instead.
	var closest: RigidBody3D = _proximity.nearest_body_in_group(
		"cookpot_storable",
		func(b: Node) -> bool: return not CookingPot.is_item_empty(b)
	) as RigidBody3D

	var hud: Node = get_tree().get_first_node_in_group("hud")

	if closest == null:
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Nothing nearby to store")
		return

	if not pot.try_add_item(closest):
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Pot full")

## Stove is a StaticBody3D — Jolt's Area3D.get_overlapping_bodies() is
## unreliable for those (same caveat _try_interact()'s Pass 2 already
## documents), so this uses a group scan, not detect_area.
func _find_nearest_open_stove() -> Node:
	return _proximity.nearest_in_group("stove", MAX_PROMPT_DIST,
		func(n: Node) -> bool: return n.has_method("has_open_slot") and n.has_open_slot())

## Like _find_nearest_open_stove(), but doesn't care whether it has an open
## slot — used for the [E] toggle-passthrough, which just wants to interact
## with whatever stove is nearby, not place anything on it.
func _find_nearest_stove() -> Node:
	var closest: Node        = null
	var closest_dist: float  = MAX_PROMPT_DIST
	var player_pos: Vector3  = player.global_position
	for node: Node in get_tree().get_nodes_in_group("stove"):
		if not is_instance_valid(node):
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

## Same group-scan reasoning as _find_nearest_open_stove().
func _find_nearest_stove_with_pot() -> Node:
	return _proximity.nearest_in_group("stove", MAX_PROMPT_DIST,
		func(n: Node) -> bool: return ("pot_ref" in n) and n.pot_ref != null)

## Same group-scan/range reasoning as _find_nearest_open_stove(), reused
## by both the Give prompt (Change 1) and its dispatch (Change 2).
func _find_nearest_npc() -> Node:
	return _proximity.nearest_in_group("npc", MAX_PROMPT_DIST)

## Shared cleanup for "this item just left my possession entirely, and
## an NPC now has (or had) ownership of it" — used by both a destroyed-
## item Give and a Snatch. Deliberately does NOT call
## InventoryManager.remove_item()/retrieve_item() — see
## InventoryManager.clear_slot()'s own doc comment for why; in short,
## both of those force the item into world-pickup state and would fight
## an NPC's already-completed item.pickup(npc.hold_point) reassignment
## (Snatch) or error on an already-freed item (destroyed-item Give).
## is_instance_valid(held_item) gates the knocked_out-disconnect the same
## way — a freed item has no live signal to disconnect from.
func _release_item_to_npc() -> void:
	if is_instance_valid(held_item) and held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)
	if _held_from_slot != -1 and inventory != null:
		inventory.clear_slot(_held_from_slot)
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false

## Give/Snatch transfer — the one correct way to move the held item into
## an NPC's hands, for any reason other than a normal world-drop.
## Deliberately mirrors _quick_drop(): disconnect knocked_out, clear the
## inventory slot via remove_item() if the item came from one (this is
## what actually empties the inventory list — deactivate_item() does
## NOT, it's for knockouts, which intentionally keep the item in
## inventory), clear held_item/_held_from_slot/_is_holding_e, refresh the
## HUD selection. The only difference from a real drop: item.pickup(npc.
## hold_point) instead of item.drop(world, floor_position).
func release_held_item_to_npc(npc: Node) -> bool:
	if held_item == null:
		return false
	if npc == null or not is_instance_valid(npc):
		return false
	if not ("hold_point" in npc) or not ("held_item" in npc):
		return false

	_is_holding_e = false
	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	var item: RigidBody3D = held_item
	var slot: int = _held_from_slot
	held_item       = null
	_held_from_slot = -1

	## Physically transfer FIRST, then clear the slot — matches
	## clear_slot()'s own doc comment: it's meant to run AFTER an NPC's
	## pickup() has already reassigned the item, not before.
	## Deliberately clear_slot(), NOT remove_item() — remove_item() calls
	## item.drop() internally, which is the actual cause of the item
	## visibly dropping instead of transferring (it unfreezes physics/
	## enables gravity/emits `dropped` as an intermediate step, one line
	## before pickup() below would have overridden it anyway).
	item.pickup(npc.hold_point)
	npc.held_item = item

	if slot != -1 and inventory != null:
		inventory.clear_slot(slot)

	_update_hud_selection()
	return true

## Give dispatch. NPC.receive_item_from_player() may free `item`
## internally (single-serving items are consumed and destroyed on the
## spot) — do not touch `item` after a true return, same caution this
## file already applies around consume_as_food()-adjacent calls elsewhere.
func _try_give_to_nearest_npc(item: RigidBody3D) -> void:
	var target: Node = _find_nearest_npc()
	if target == null or not target.has_method("can_receive_item") or not target.can_receive_item(item):
		return
	if not release_held_item_to_npc(target):
		return
	if target.has_method("on_item_given"):
		target.on_item_given(item)

## External clear — called by Player.on_item_snatched() when an NPC has
## just taken the held item away entirely outside this system's own
## input handling (relationship Snatch feature, NPC-owned). Unlike
## _try_give_to_nearest_npc()'s conditional clear, this is unconditional:
## by the time the caller reaches this, the item has already been
## physically reassigned to the NPC (item.pickup(npc.hold_point),
## npc.held_item = item) regardless of item type, so there's no
## "did it survive" branch to make — it's simply gone from this side.
func clear_held_item_external() -> void:
	_release_item_to_npc()

## Mirrors _try_pickup()'s tail exactly (signal connect, held_item/_held_from_slot
## bookkeeping, set_player call) — the only difference is the item comes from
## Stove.try_remove_pot() instead of a detect_area scan.
func _try_pickup_pot_from_stove(stove: Node) -> void:
	var pot: Node = stove.try_remove_pot()
	if pot == null:
		return
	held_item       = pot
	_held_from_slot = -1
	_tracked_bodies.erase(held_item)
	if "from_inventory" in held_item:
		held_item.from_inventory = false
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)
	if held_item.has_method("set_player"):
		held_item.set_player(player)

## Scans "cooking_pot" — covers a pot on a stove AND a standalone pot sitting
## on the ground with a ready dish still in it.
func _find_nearest_ready_pot() -> Node:
	return _proximity.nearest_in_group("cooking_pot", MAX_PROMPT_DIST,
		func(n: Node) -> bool: return n.has_method("is_dish_ready") and n.is_dish_ready())

## Read-only peek at whatever _try_interact() would actually interact
## with, without triggering it — the ONE shared scan used by
## _try_interact() itself, _nearest_interact_distance() (kept as a thin
## distance-only wrapper below, several callers only need the number),
## and the shelf E-priority fairness check below. Returns { "node":
## Node3D or null, "dist": float (INF if nothing eligible) }.
##
## Aug 2026 — added the grow-light-over-tray override: a GrowLight sits
## on the ceiling directly above its FarmingTray (the intended setup), so
## the tray is almost always physically closer to the player and would
## otherwise always win here. Deliberately narrow — only overrides when
## a FarmingTray specifically would otherwise win and a grow light is
## also in reach. Every other pair of nearby interactables (shelves,
## generators, anything else near a grow light) still resolves by
## genuine fair distance, unaffected.
func _nearest_generic_interactable() -> Dictionary:
	var bodies: Array       = detect_area.get_overlapping_bodies()
	var closest: Node3D     = null
	var closest_dist: float = INF

	for body in bodies:
		if body.is_in_group("interactable") and body.has_method("on_interact"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			## Aug 2026 (correction) — Grow Light exclusion originally only
			## landed in Pass 2 below. Jolt's Area3D overlap detection for
			## StaticBody3D is unreliable, NOT nonexistent — this pass can
			## and evidently does catch it in real testing, at which point
			## Pass 2's exclusion never runs because `closest` is already
			## claimed here first. Inlined the Ctrl check directly (rather
			## than reordering `focus_mode_active`'s declaration, which sits
			## after this pass) to keep this a minimal, contained fix.
			if body.is_in_group("grow_light") and not FocusMode.is_active():
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	var static_reach: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
	var nearest_focus_priority: Node3D     = null
	var nearest_focus_priority_dist: float = INF
	## Aug 2026 v2 — Focus Mode E-interact parity. Grow Light/Water Hookup
	## priority moved back here from being purely a display concern, but
	## gated behind Ctrl so it ONLY applies while Focus Mode is actually
	## active — plain E presses are still pure fair distance, unaffected.
	## Without this, E could interact with something different than
	## whatever Focus Mode was highlighting the whole time Ctrl was held
	## (reported: Water Hookup/Grow Light correctly shown as the only
	## prompt, but E still hit the nearer Wall Light/tray instead).
	var focus_mode_active: bool = FocusMode.is_active()
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node):
			continue
		if not (node is StaticBody3D):
			continue
		if not node.has_method("on_interact"):
			continue
		if node.is_in_group("shelved"):
			continue
		## Aug 2026 — mirrors the CASE 2 prompt-visibility exclusion above:
		## Grow Light isn't interactable at all outside Focus Mode, not
		## just de-prioritized. Without this, a player standing right next
		## to a grow light with nothing else nearby could still interact
		## with it via plain E (ordinary fair-distance competition against
		## nothing), even though no prompt for it was ever shown — a
		## confusing mismatch between what's visible and what E does.
		if node.is_in_group("grow_light") and not focus_mode_active:
			continue
		var n3: Node3D = node as Node3D
		var d: float = n3.global_position.distance_to(player_pos)
		if focus_mode_active and (node.is_in_group("grow_light") or node.is_in_group("water_hookup")) \
				and d < static_reach and d < nearest_focus_priority_dist:
			nearest_focus_priority_dist = d
			nearest_focus_priority = n3
		if d < static_reach and d < closest_dist:
			closest_dist = d
			closest = n3

	## Mirrors focus_idx's own priority exactly (nearest of either group
	## wins if Ctrl is held) — see that function's comment for the full
	## reasoning on why both are treated identically. Ctrl not held →
	## nearest_focus_priority stays null → this is a no-op, ordinary fair
	## distance stands, matching "essentially never wins outside Focus
	## Mode" by design.
	if nearest_focus_priority != null:
		closest      = nearest_focus_priority
		closest_dist = nearest_focus_priority_dist

	return { "node": closest, "dist": closest_dist }

## Thin distance-only wrapper — several existing callers (the ready-dish
## fairness check below) only need the number, not the node.
func _nearest_interact_distance() -> float:
	return float(_nearest_generic_interactable()["dist"])


## Spawns a DishItem from the pot's serve_dish() result and puts it directly
## in the player's hand — mirrors _try_pickup_pot_from_stove()'s tail.
## Aug 2026 (Job Progress Bar) — split into a trigger (this) and a
## completion (_finish_take_dish()). is_dish_ready() is a non-destructive
## status check, safe to call at trigger time; serve_dish() itself (which
## actually clears the pot's ready-dish state) is deferred to completion
## so a cancelled job leaves the pot untouched.
func _try_take_dish(pot: Node) -> void:
	if not (pot.has_method("is_dish_ready") and pot.is_dish_ready()):
		return
	start_job(pot as Node3D, JOB_DEFAULT_DURATION, Callable(self, "_finish_take_dish").bind(pot), "Plating Dish...")

func _finish_take_dish(pot: Node) -> void:
	if not is_instance_valid(pot):
		return
	var result: Dictionary = pot.serve_dish()
	if result.is_empty():
		return

	var dish_script: GDScript = load("res://scripts/world/items/DishItem.gd")
	var dish: RigidBody3D = RigidBody3D.new()
	dish.set_script(dish_script)
	dish.collision_layer = 1
	dish.collision_mask  = 1
	dish.continuous_cd   = true

	## Must be set BEFORE add_child() — DishItem._ready() reads
	## hydration_value to pick its visual model, and add_child() fires
	## _ready() synchronously. Setting these after add_child() (the old
	## order) meant _ready() always saw the pre-assignment default value.
	dish.fill_value      = result["value"]
	dish.bonus_pct       = result["bonus_pct"]
	dish.dish_name       = String(result.get("name", "Cooked Dish"))
	dish.hydration_value = float(result.get("hydration", 0.0))

	var world_root: Node = get_tree().get_root()
	world_root.add_child(dish)
	dish.global_position = (pot as Node3D).global_position

	held_item       = dish
	_held_from_slot = -1
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)
	if held_item.has_method("set_player"):
		held_item.set_player(player)

## Called when the player presses [E] while HOLDING a Cooking Pot that has
## a finished dish inside — takes priority over placing/toggling/grabbing.
## The pot is dropped at the player's feet (same position _quick_drop()
## uses, since the player can only hold one item at a time) and the new
## Dish takes its place in hand. Mirrors _try_take_dish()'s world-pot flow
## with a drop step first.
## Aug 2026 (Job Progress Bar) — same trigger/completion split as
## _try_take_dish() above; serve_dish() and the drop-then-spawn sequence
## are both deferred to _finish_take_dish_from_held_pot() so a cancelled
## job leaves the held pot exactly as it was (still in hand, dish intact).
func _try_take_dish_from_held_pot(pot: Node) -> void:
	if not (pot.has_method("is_dish_ready") and pot.is_dish_ready()):
		return
	## job_range large — the pot follows the player's hand, so "walking
	## away" from it isn't a real concept; movement itself cancels the job
	## regardless (see start_job()'s own comment).
	start_job(pot as Node3D, JOB_DEFAULT_DURATION, Callable(self, "_finish_take_dish_from_held_pot").bind(pot), "Plating Dish...", 999.0)

func _finish_take_dish_from_held_pot(pot: Node) -> void:
	if held_item != pot or not is_instance_valid(pot):
		return   ## defensive — held item changed out from under the job somehow
	var result: Dictionary = pot.serve_dish()
	if result.is_empty():
		return

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	var drop_pos: Vector3 = player.global_position + \
		player.global_transform.basis.z * -1.5 + Vector3(0.0, 0.2, 0.0)
	pot.drop(_world_root, drop_pos)
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false

	var dish_script: GDScript = load("res://scripts/world/items/DishItem.gd")
	var dish: RigidBody3D = RigidBody3D.new()
	dish.set_script(dish_script)
	dish.collision_layer = 1
	dish.collision_mask  = 1
	dish.continuous_cd   = true

	## See _finish_take_dish()'s identical comment — must be set before
	## add_child() fires _ready().
	dish.fill_value      = result["value"]
	dish.bonus_pct       = result["bonus_pct"]
	dish.dish_name       = String(result.get("name", "Cooked Dish"))
	dish.hydration_value = float(result.get("hydration", 0.0))

	_world_root.add_child(dish)
	dish.global_position = drop_pos

	held_item       = dish
	_held_from_slot = -1
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)
	if held_item.has_method("set_player"):
		held_item.set_player(player)

# ─── World Interaction ────────────────────────────────────────────────────────
func _try_interact() -> void:
	## Seated players always stand, regardless of what else is nearby —
	## checked first, before any proximity scan, so a chair can never lose
	## a closest-distance comparison to some other interactable.
	if player.seated_chair != null and is_instance_valid(player.seated_chair):
		player.seated_chair.on_interact()
		return

	## Aug 2026 — scan itself moved into _nearest_generic_interactable()
	## (shared with _nearest_interact_distance() and the shelf E-priority
	## fairness check) so "what would fire" and "what actually fires" can
	## never disagree.
	var best: Dictionary = _nearest_generic_interactable()
	var closest: Node3D = best["node"]
	if closest != null:
		closest.on_interact()

## Read-only peek at the distance to whatever _try_pickup() would grab,
## without actually grabbing it — used purely to fairly compare against the
## stove-with-pot special case above. Returns INF if nothing is eligible.
func _nearest_pickup_distance() -> float:
	return _proximity.nearest_distance_in_group("pickup")

# ─── Pickup from world ────────────────────────────────────────────────────────
func _try_pickup() -> void:
	## Shelved items — block direct pickup via F; use shelf menu (E) to retrieve.
	## Frozen-body / shelved / held-item filtering now lives in
	## InteractionProximityScan (Phase 1, Aug 2026) — see its header comment.
	var closest: RigidBody3D = _proximity.nearest_body_in_group("pickup") as RigidBody3D

	if closest == null:
		return

	## NPC takeaway notification — look this up BEFORE reassigning
	## held_item below, since find_holder() checks each live NPC's own
	## held_item field for a match.
	var taken_from: Node = NPCItemUser.find_holder(closest, get_tree())

	held_item = closest
	_held_from_slot = -1   ## Fresh from world — not in any inventory slot yet
	# Remove from tracked set immediately — Jolt may not fire body_exited when
	# collision_layer changes at pickup, leaving a ghost entry that shows prompts.
	_tracked_bodies.erase(held_item)
	# Mark as world-held so knockout distance check is active
	if "from_inventory" in held_item:
		held_item.from_inventory = false
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)
	# Pass player reference so items that need facing direction (e.g. flashlight) can track it.
	if held_item.has_method("set_player"):
		held_item.set_player(player)

	if taken_from != null and taken_from.has_method("on_item_taken_by_player"):
		taken_from.on_item_taken_by_player()

# ─── Knocked out ──────────────────────────────────────────────────────────────
func _on_item_knocked_out() -> void:
	# If it was an inventory item, deactivate it in-slot (don't clear the slot)
	if _held_from_slot != -1 and inventory != null:
		inventory.deactivate_item(_held_from_slot)

	held_item = null
	_held_from_slot = -1
	_is_holding_e = false
	# Don't clear selected_slot — the slot still has the item, just knocked out
	_update_hud_selection()

# ─── Quick Drop ───────────────────────────────────────────────────────────────
func _quick_drop() -> void:
	if held_item == null:
		return

	_is_holding_e = false

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	var drop_pos: Vector3 = player.global_position + \
		player.global_transform.basis.z * -1.5 + Vector3(0.0, 0.2, 0.0)

	var dropped_item: RigidBody3D = held_item   ## captured before nulling below

	if _held_from_slot != -1 and inventory != null:
		# Item was from inventory — remove it from the slot before dropping
		inventory.remove_item(_held_from_slot, drop_pos)
		# remove_item calls item.drop() internally, so we're done
	else:
		# World item — just drop it
		held_item.drop(_world_root, drop_pos)

	held_item = null
	_held_from_slot = -1

	## Aug 2026 fix — re-add to the tracked set immediately. Jolt's Area3D
	## body_entered only fires on a genuine boundary crossing; an item
	## dropped back roughly where it was picked up never physically leaves/
	## re-enters detect_area's collision volume (it was just reparented away
	## and back), so body_entered never refires. Without this, a dropped
	## item's prompt — and for anything with get_slot_icon_descriptors()
	## like CookingPot, its icon row — stayed invisible until the player
	## actually walked out of range and back in. Mirrors the explicit
	## _tracked_bodies.erase() already done at pickup, just in reverse.
	if is_instance_valid(dropped_item):
		_tracked_bodies[dropped_item] = true

# ─── Drop In Place (Aug 2026) ────────────────────────────────────────────
## Same shape as _quick_drop() above (knocked_out cleanup, inventory-slot
## clear via remove_item() when it came from one, re-tracking the dropped
## body) with exactly ONE difference: drop_pos is the item's own CURRENT
## position (wherever the hold point currently has it) rather than a
## freshly computed spot ~1.5m in front of the player. _quick_drop()'s
## forward-offset placement is meant for a deliberate player action (F
## with nothing to interact, G with a full inventory, scroll-to-full-
## inventory, etc.) where snapping to a clear spot in front of the player
## reads as intentional. For an INVOLUNTARY drop (stamina hitting 0), the
## item should simply fall out of the player's hand where it already is,
## not visibly hop to a new location — see Player.gd's stamina-exhaustion
## drop, the only current caller.
func drop_in_place() -> void:
	if held_item == null:
		return

	_is_holding_e = false

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	var drop_pos: Vector3 = held_item.global_position   ## wherever it's currently held — no reposition

	var dropped_item: RigidBody3D = held_item   ## captured before nulling below

	if _held_from_slot != -1 and inventory != null:
		inventory.remove_item(_held_from_slot, drop_pos)
	else:
		held_item.drop(_world_root, drop_pos)

	held_item = null
	_held_from_slot = -1

	## Mirrors _quick_drop()'s own re-tracking fix — see that function's
	## comment for why this is needed.
	if is_instance_valid(dropped_item):
		_tracked_bodies[dropped_item] = true
