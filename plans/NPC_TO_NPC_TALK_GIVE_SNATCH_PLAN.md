# NPC↔NPC Talking, Give-to-Friend, and Generalized Snatch (Aug 2026)

**Files:** `scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/npc/NPCItemUser.gd`, `scripts/ui/menus/AdminMenu.gd`.
No Player-subsystem changes — `on_item_given()`'s new parameters default
to the existing player-Give behavior, so `InteractionSystem.gd`'s call
site needs no changes at all.

## Design recap (per your answers)

- **Talking**: opportunistic, scored like Relaxing — but the score is
  multiplied by a relationship curve: flat 1.0x between -15 and +15,
  scaling up to 2.5x by +100, down to 0.2x by -100. Only ever considered
  between NPCs already close together (no travel phase — see below for
  why that matters). Non-interruptible once both parties are locked in.
- **Give-to-friend**: donor needs relationship ≥ +25 with a friend whose
  matching need is low. Chance to even attempt it scales with
  relationship strength above +25, mirroring Snatch's exact curve shape
  (5% at +25, 50% at +100).
- **Snatch (NPC→NPC)**: identical trigger to the player version — an
  NPC who is hungry/thirsty AND dislikes someone (≤ -50) prefers
  snatching from them over a normal search. When multiple disliked
  targets qualify, picks the nearest one currently holding a matching
  item (player counts as just another candidate in that same pool).

---

## Part A — Generalize Snatch (player + NPC targets, one system)

### 1. `scripts/npc/NPC.gd` — duck-typed interface parity

**Anchor:** add near the top of the Relationships/Snatch area.

```gdscript
## Gives NPC the same get_held_item() interface Player already has, so
## SnatchActivity/find_snatch_target() can treat both as interchangeable
## targets without branching on type anywhere.
func get_held_item() -> Node:
	return held_item
```

### 2. `scripts/npc/NPC.gd` — generalize the chance formula

**Anchor:** the current `get_snatch_chance()`:

```gdscript
func get_snatch_chance() -> float:
	var rel: float = get_relationship("player")
	if rel > SNATCH_RELATIONSHIP_THRESHOLD:
		return 0.0
	var t: float = clampf(
		(SNATCH_RELATIONSHIP_THRESHOLD - rel) / (SNATCH_RELATIONSHIP_THRESHOLD - RELATIONSHIP_MIN),
		0.0, 1.0)
	return lerp(SNATCH_CHANCE_AT_THRESHOLD, SNATCH_CHANCE_AT_MIN, t)
```

Replace with:

```gdscript
## Generalized to any target_id (npc_id or "player") — same curve, just
## no longer hardcoded to the player specifically.
func get_snatch_chance_toward(target_id: String) -> float:
	var rel: float = get_relationship(target_id)
	if rel > SNATCH_RELATIONSHIP_THRESHOLD:
		return 0.0
	var t: float = clampf(
		(SNATCH_RELATIONSHIP_THRESHOLD - rel) / (SNATCH_RELATIONSHIP_THRESHOLD - RELATIONSHIP_MIN),
		0.0, 1.0)
	return lerp(SNATCH_CHANCE_AT_THRESHOLD, SNATCH_CHANCE_AT_MIN, t)

## Kept for the F7 debug button, which is still specifically about the player.
func get_snatch_chance() -> float:
	return get_snatch_chance_toward("player")
```

### 3. `scripts/npc/NPC.gd` — generalize target-finding

**Anchor:** the current `find_player_snatch_target()`:

```gdscript
func find_player_snatch_target(need_filter: Callable) -> Node:
	var forced: bool = _debug_force_snatch
	_debug_force_snatch = false
	if not forced and get_relationship("player") > SNATCH_RELATIONSHIP_THRESHOLD:
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "not considered", "relationship %.1f is above threshold %.1f" \
				% [get_relationship("player"), SNATCH_RELATIONSHIP_THRESHOLD])
		return null
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return null
	var held: Node = player.get_held_item()
	if held == null or not is_instance_valid(held):
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "not considered", "player isn't holding anything")
		return null
	if not need_filter.call(held):
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "not considered", "player is holding something, but not a matching type")
		return null
	if not forced:
		var chance: float = get_snatch_chance()
		var roll: float = randf()
		if roll > chance:
			if NPCDebug.enabled:
				NPCDebug.log_snatch(self, "roll failed", "chance=%.2f roll=%.2f" % [chance, roll])
			return null
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "roll succeeded", "chance=%.2f roll=%.2f" % [chance, roll])
	return player
```

Replace with:

```gdscript
## Generalized: considers the player AND every other NPC as candidates,
## uniformly — anyone (player or NPC) counts if their relationship with
## THIS NPC is <= threshold and they're currently holding a matching
## item. Ties broken by nearest, per spec. _debug_force_snatch still
## only ever targets the player specifically (see debug_force_snatch()).
func find_snatch_target(need_filter: Callable) -> Node:
	var forced: bool = _debug_force_snatch
	_debug_force_snatch = false

	if forced:
		var player: Node = get_tree().get_first_node_in_group("player")
		return player if player != null and is_instance_valid(player) else null

	var best: Node = null
	var best_d: float = INF

	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player) and player.has_method("get_held_item") \
			and get_relationship("player") <= SNATCH_RELATIONSHIP_THRESHOLD:
		var held: Node = player.get_held_item()
		if held != null and is_instance_valid(held) and need_filter.call(held):
			var d: float = NPCItemUser.flat_distance(global_position, (player as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = player

	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if get_relationship(other.npc_id) > SNATCH_RELATIONSHIP_THRESHOLD:
			continue
		var held: Node = other.held_item
		if held == null or not is_instance_valid(held) or not need_filter.call(held):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, other.global_position)
		if d < best_d:
			best_d = d
			best = other

	if best == null:
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "not considered", "no eligible disliked target holding a matching item")
		return null

	var target_id: String = "player" if best.is_in_group("player") else best.npc_id
	var chance: float = get_snatch_chance_toward(target_id)
	var roll: float = randf()
	if roll > chance:
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "roll failed", "target=%s chance=%.2f roll=%.2f" % [target_id, chance, roll])
		return null
	if NPCDebug.enabled:
		NPCDebug.log_snatch(self, "roll succeeded", "target=%s chance=%.2f roll=%.2f" % [target_id, chance, roll])
	return best
```

Every call site that referenced `find_player_snatch_target(...)` (EatActivity/DrinkActivity's `enter()`/`_reacquire_or_finish()`) needs renaming to `find_snatch_target(...)` — same signature, no other changes needed there.

### 4. `scripts/npc/NPCItemUser.gd` — generalize the actual grab

**Anchor:** the current `snatch_from_player()`:

```gdscript
static func snatch_from_player(npc: NPC, player: Node) -> bool:
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return false
	var item: Node = player.get_held_item()
	if item == null or not is_instance_valid(item) or not item.has_method("pickup"):
		return false
	if flat_distance(npc.global_position, (player as Node3D).global_position) > SNATCH_RANGE:
		return false
	item.pickup(npc.hold_point)
	npc.held_item = item
	if player.has_method("on_item_snatched"):
		player.on_item_snatched()
	return true
```

Replace with:

```gdscript
## Generalized to any target (player or NPC). Player targets still go
## through release_held_item_to_npc() (the only path with inventory-slot
## context). NPC targets are simpler — no inventory system to reconcile,
## just a direct physical reassignment plus telling the victim to clear
## their own held_item reference (mirrors what on_item_snatched() does
## for the player, at NPC scale).
static func snatch_from(npc: NPC, target: Node) -> bool:
	if npc.held_item != null:
		return false
	if target == null or not is_instance_valid(target):
		return false
	if flat_distance(npc.global_position, (target as Node3D).global_position) > SNATCH_RANGE:
		return false

	if target.is_in_group("player"):
		if not target.has_method("get_held_item") or not target.has_method("release_held_item_to_npc"):
			return false
		var item: Node = target.get_held_item()
		if item == null or not is_instance_valid(item):
			return false
		return target.release_held_item_to_npc(npc)

	## NPC target
	var item: Node = target.held_item
	if item == null or not is_instance_valid(item) or not item.has_method("pickup"):
		return false
	item.pickup(npc.hold_point)
	npc.held_item = item
	if target.has_method("on_item_snatched_by_npc"):
		target.on_item_snatched_by_npc(npc)
	else:
		target.held_item = null
	return true
```

Every call site of `snatch_from_player(npc, X)` renames to `snatch_from(npc, X)`.

### 5. `scripts/npc/NPC.gd` — victim-side cleanup for an NPC target

**Anchor:** near `on_item_taken_by_player()`.

Insert:

```gdscript
## Called on the VICTIM when another NPC successfully snatches from them
## (NPCItemUser.snatch_from()). Relationship-neutral, same as the player
## version — this is a consequence of an already-bad relationship, not a
## new event that further sours it.
func on_item_snatched_by_npc(thief: NPC) -> void:
	var item: Node = held_item
	held_item = null
	if item != null:
		NPCItemUser.release_item(item)
	log_action("%s snatched an item from %s" % [thief.npc_name, npc_name])
```

### 6. `scripts/npc/NPCBrain.gd` — `SnatchActivity` retargeted

**Anchor:** the entire `SnatchActivity` class — rename every `_player`
reference to `_target`, and every call to `find_player_snatch_target`/
`snatch_from_player` to `find_snatch_target`/`snatch_from`. Everything
else (the continuous re-aim, the dropped-item-chase fallback, the
20-second give-up timer) works unchanged since it was already written
against a generic `Node`, not anything player-specific. The one line
that needs an actual behavior change:

```gdscript
					NPCDebug.log_snatch(npc, "success", "grabbed item from player's hands, handing off to consume")
					npc.log_action("Snatched an item from the player's hands")
```

Replace with:

```gdscript
					NPCDebug.log_snatch(npc, "success", "grabbed item, handing off to consume")
					var target_desc: String = "the player" if _target.is_in_group("player") else _target.npc_name
					npc.log_action("Snatched an item from %s" % target_desc)
```

(The victim's own side of the log — "X snatched an item from you" — is
handled by `on_item_snatched_by_npc()` above for NPC victims, and
`on_item_snatched()`/`InteractionSystem` for the player, unchanged.)

---

## Part B — Talking

No travel phase, deliberately — only ever considered between NPCs
already within `TALK_RANGE`, so both lock in place immediately rather
than walking to meet. This sidesteps the entire "cancelled mid-approach"
failure mode Snatch originally had.

### 1. `scripts/npc/NPC.gd`

**Anchor:** anywhere convenient near the Relationships section.

Insert:

```gdscript
# ─── Talking (Aug 2026) ──────────────────────────────────────────────────
const TALK_RANGE: float = 3.0
const TALK_BASE_SCORE: float = 5.5   ## same tier as Relax/Wander
const TALK_RELATIONSHIP_NEUTRAL_LOW: float = -15.0
const TALK_RELATIONSHIP_NEUTRAL_HIGH: float = 15.0
const TALK_SCORE_MULT_MAX: float = 2.5   ## at relationship +100
const TALK_SCORE_MULT_MIN: float = 0.2   ## at relationship -100

## Flat 1.0x between -15 and +15 (your framing: "neutral" band); scales
## continuously beyond that rather than a hard binary jump, same reasoning
## every other trait/relationship multiplier in this file uses.
func get_talk_score_mult(other_id: String) -> float:
	var rel: float = get_relationship(other_id)
	if rel > TALK_RELATIONSHIP_NEUTRAL_HIGH:
		var t: float = clampf((rel - TALK_RELATIONSHIP_NEUTRAL_HIGH) / (RELATIONSHIP_MAX - TALK_RELATIONSHIP_NEUTRAL_HIGH), 0.0, 1.0)
		return lerp(1.0, TALK_SCORE_MULT_MAX, t)
	elif rel < TALK_RELATIONSHIP_NEUTRAL_LOW:
		var t: float = clampf((TALK_RELATIONSHIP_NEUTRAL_LOW - rel) / (TALK_RELATIONSHIP_NEUTRAL_LOW - RELATIONSHIP_MIN), 0.0, 1.0)
		return lerp(1.0, TALK_SCORE_MULT_MIN, t)
	return 1.0

## Nearest NPC within TALK_RANGE who's actually free to talk right now.
func find_talk_partner() -> Node:
	var best: Node = null
	var best_d: float = TALK_RANGE
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if not other.has_method("is_available_to_talk") or not other.is_available_to_talk():
			continue
		var d: float = NPCItemUser.flat_distance(global_position, other.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best

func is_available_to_talk() -> bool:
	if brain == null:
		return false
	if brain.is_relaxing() or brain.is_talking():
		return false
	return brain.is_current_interruptible()

## Called on the partner by the initiator's TalkActivity. Forces the
## partner into their own (non-initiator) TalkActivity instance.
func start_talk_session(initiator: NPC) -> bool:
	if not is_available_to_talk():
		return false
	brain.force_command(NPCBrain.TalkActivity.new(initiator, false))
	return true

## Called on the partner when the initiator's session timer ends, OR on
## either side if interrupted some other way — ends the local session
## and logs it from this NPC's own perspective.
func end_talk_session() -> void:
	if brain == null or not brain.is_talking():
		return
	var partner_name: String = brain.get_talk_partner_name()
	log_action("Talked to %s" % partner_name)
	brain.end_talk_if_talking()
```

### 2. `scripts/npc/NPCBrain.gd` — brain-level helpers

**Anchor:** near `is_relaxing()` (added in an earlier plan).

Insert:

```gdscript
func is_talking() -> bool:
	return _current is TalkActivity

func is_current_interruptible() -> bool:
	return _current == null or _current.interruptible()

## Reaches into the current TalkActivity instance directly — same-file
## access, no privacy concern; used by NPC.end_talk_session().
func get_talk_partner_name() -> String:
	if _current is TalkActivity:
		var t: TalkActivity = _current as TalkActivity
		if t._partner != null and is_instance_valid(t._partner) and ("npc_name" in t._partner):
			return String(t._partner.npc_name)
	return "someone"

func end_talk_if_talking() -> void:
	if _current is TalkActivity:
		(_current as TalkActivity)._partner = null
```

### 3. `scripts/npc/NPCBrain.gd` — the `TalkActivity` class

**Anchor:** add as a new top-level class, and register the reusable
instance in `setup()`'s `_candidates` list.

```gdscript
class TalkActivity extends NPCActivity:
	## NPC↔NPC Talking (Aug 2026). One reusable instance lives in
	## _candidates (constructed with defaults — partner=null,
	## is_initiator=true) for the normal scored/organic path; a SEPARATE
	## one-shot instance gets force_command()'d onto the partner side
	## (partner=initiator, is_initiator=false) via start_talk_session().
	## No travel phase — only ever matched between NPCs already within
	## TALK_RANGE, so both lock in place immediately. Non-interruptible
	## once a partner's actually locked in, same "commit once started"
	## reasoning as every other multi-step activity in this file.
	## FUTURE WORK: relationship-based random conversation OUTCOMES —
	## deliberately not built yet. This pass is groundwork only: both
	## NPCs occupied, facing each other, logged.
	const SESSION_MIN: float = 8.0    ## seconds, real-time — a quick social beat, not a game-hours-scale session like Relaxing
	const SESSION_MAX: float = 20.0

	var _partner: Node = null
	var _elapsed: float = 0.0
	var _duration: float = 0.0
	var _is_initiator: bool = true

	func _init(partner: Node = null, is_initiator: bool = true) -> void:
		_partner = partner
		_is_initiator = is_initiator

	func label() -> String:
		return "Talking" if _partner != null else "Idle"

	func score(npc: NPC) -> float:
		if not _is_initiator:
			return 0.0   ## the forced partner-side instance is never itself a scoring candidate
		if npc.find_talk_partner() == null:
			return 0.0
		return TALK_BASE_SCORE * npc.get_work_ethic_passive_mult()

	func interruptible() -> bool:
		return _partner == null   ## only interruptible in the brief instant before a partner locks in

	func enter(npc: NPC) -> void:
		if _is_initiator:
			_partner = npc.find_talk_partner()
			if _partner == null:
				return
			if not _partner.has_method("start_talk_session") or not _partner.start_talk_session(npc):
				_partner = null
				return
			_duration = randf_range(SESSION_MIN, SESSION_MAX)
			_elapsed = 0.0
		if _partner != null and is_instance_valid(_partner):
			npc.lock_movement()
			var target_pos: Vector3 = (_partner as Node3D).global_position
			target_pos.y = npc.global_position.y
			npc.look_at(target_pos, Vector3.UP)

	func tick(npc: NPC, delta: float) -> void:
		if _partner == null or not is_instance_valid(_partner):
			_partner = null
			return
		npc.halt_movement(delta)
		if not _is_initiator:
			return   ## partner just waits — end_talk_if_talking() (called via the initiator's own end-of-session) clears _partner externally
		_elapsed += delta
		if _elapsed >= _duration:
			if _partner.has_method("end_talk_session"):
				_partner.end_talk_session()
			npc.log_action("Talked to %s" % _partner.npc_name)
			_partner = null

	func done(npc: NPC) -> bool:
		return _partner == null

	func exit(npc: NPC) -> void:
		if _partner != null and is_instance_valid(_partner) and _is_initiator:
			## interrupted some other way — don't leave the partner stuck
			if _partner.has_method("end_talk_session"):
				_partner.end_talk_session()
		_partner = null
```

**Anchor:** `setup()`'s `_candidates` list — add `TalkActivity.new()`.

---

## Part C — Give-to-Friend

New activity — fetch (reuses `grab_loose()`/claim exactly like
`JobActivity`'s fetch phase), travel (continuously re-aims at the
friend, same pattern `SnatchActivity` already established), hand off
(reuses `can_receive_item()`/`on_item_given()` unchanged in spirit, just
generalized to know who the giver actually is).

### 1. `scripts/npc/NPC.gd` — generalize `on_item_given()`

**Anchor:** the current function:

```gdscript
func on_item_given(item: Node) -> void:
	var recipients: Array = item.get_meta("npc_gift_recipients", [])
	var already_boosted: bool = recipients.has(npc_id)
	if not already_boosted:
		recipients.append(npc_id)
		item.set_meta("npc_gift_recipients", recipients)

	var activity: NPCActivity
	if NPCItemUser.is_edible(item):
		activity = NPCBrain.GivenEatActivity.new()
	else:
		activity = NPCBrain.GivenDrinkActivity.new()
	brain.force_command(activity)
	activity.begin_with_item(self, item)

	if already_boosted:
		if NPCDebug.enabled:
			NPCDebug.log_relationship_event(self, "player", 0.0,
				"re-gift, already boosted by this item — fed only, no bonus")
		log_action("Player gave you %s (fed only, no relationship change)" % item.get_display_name())
		return

	var effective_bonus: float = GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)
	var applied: float = _adjust_relationship("player", effective_bonus)
	gift_saturation = minf(GIFT_SATURATION_MAX, gift_saturation + GIFT_SATURATION_PER_GIFT)
	log_action("Player gave you %s (%+.1f relationship)" % [item.get_display_name(), applied])
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", effective_bonus,
			"received gift (saturation %.2f)" % gift_saturation)
```

Replace with:

```gdscript
## giver_id/giver_name default to the player — the existing player-Give
## call site (InteractionSystem.gd) calls this with no extra args and
## needs zero changes. NPC-to-NPC Give (GiveToFriendActivity below)
## passes the donor's npc_id/npc_name instead, so the relationship boost
## lands on the ACTUAL giver, not always "player".
func on_item_given(item: Node, giver_id: String = "player", giver_name: String = "Player") -> void:
	var recipients: Array = item.get_meta("npc_gift_recipients", [])
	var already_boosted: bool = recipients.has(npc_id)
	if not already_boosted:
		recipients.append(npc_id)
		item.set_meta("npc_gift_recipients", recipients)

	var activity: NPCActivity
	if NPCItemUser.is_edible(item):
		activity = NPCBrain.GivenEatActivity.new()
	else:
		activity = NPCBrain.GivenDrinkActivity.new()
	brain.force_command(activity)
	activity.begin_with_item(self, item)

	if already_boosted:
		if NPCDebug.enabled:
			NPCDebug.log_relationship_event(self, giver_id, 0.0,
				"re-gift, already boosted by this item — fed only, no bonus")
		log_action("%s gave %s to %s (fed only, no relationship change)" % [giver_name, item.get_display_name(), npc_name])
		return

	var effective_bonus: float = GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)
	var applied: float = _adjust_relationship(giver_id, effective_bonus)
	gift_saturation = minf(GIFT_SATURATION_MAX, gift_saturation + GIFT_SATURATION_PER_GIFT)
	log_action("%s gave %s to %s (%+.1f relationship)" % [giver_name, item.get_display_name(), npc_name, applied])
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, giver_id, effective_bonus,
			"received gift (saturation %.2f)" % gift_saturation)
```

(This also happens to fix the same "you/your" wording issue from last
time, for the recipient's own log entry — was already fixed for the
player-Give case in the prior wording-fix plan; this generalization
keeps that fix intact.)

### 2. `scripts/npc/NPC.gd` — chance formula + eligibility + search

**Anchor:** anywhere near the Give/Takeaway section.

Insert:

```gdscript
# ─── Give-to-Friend (Aug 2026) ──────────────────────────────────────────────
const GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD: float = 25.0
const GIVE_TO_FRIEND_CHANCE_AT_THRESHOLD: float = 0.05   ## at exactly +25
const GIVE_TO_FRIEND_CHANCE_AT_MAX: float = 0.5          ## at +100 — same curve shape as Snatch, mirrored direction
const GIVE_TO_FRIEND_BASE_SCORE: float = 5.5

func get_give_to_friend_chance(rel: float) -> float:
	if rel < GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD:
		return 0.0
	var t: float = clampf(
		(rel - GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD) / (RELATIONSHIP_MAX - GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD),
		0.0, 1.0)
	return lerp(GIVE_TO_FRIEND_CHANCE_AT_THRESHOLD, GIVE_TO_FRIEND_CHANCE_AT_MAX, t)

## Cheap, deterministic (no item search, no roll) — used by
## GiveToFriendActivity.score() so the full search only runs on enter().
func has_needy_friend() -> bool:
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if get_relationship(other.npc_id) < GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD:
			continue
		if float(other.hunger) < 55.0 or float(other.thirst) < 55.0:
			return true
	return false

## Full search: nearest needy friend (relationship-eligible, matching
## need low) with a matching item actually available in the world, gated
## by one probability roll scaled to that friend's relationship. Returns
## {} if nothing qualifies.
func find_friend_to_help() -> Dictionary:
	var best: Node = null
	var best_d: float = INF
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if get_relationship(other.npc_id) < GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD:
			continue
		if not (float(other.hunger) < 55.0 or float(other.thirst) < 55.0):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, other.global_position)
		if d < best_d:
			best_d = d
			best = other
	if best == null:
		return {}

	var need_filter: Callable = Callable(NPCItemUser, "is_edible") if float(best.hunger) < float(best.thirst) \
		else Callable(NPCItemUser, "is_drinkable_bottle")
	## if only one need is actually low, make sure the filter matches THAT one
	if float(best.hunger) < 55.0 and not (float(best.thirst) < 55.0):
		need_filter = Callable(NPCItemUser, "is_edible")
	elif float(best.thirst) < 55.0 and not (float(best.hunger) < 55.0):
		need_filter = Callable(NPCItemUser, "is_drinkable_bottle")

	var item: Node = NPCItemUser.find_loose_item(self, need_filter)
	if item == null:
		return {}

	var chance: float = get_give_to_friend_chance(get_relationship(best.npc_id))
	if randf() > chance:
		return {}

	return {"friend": best, "item": item}
```

### 3. `scripts/npc/NPCBrain.gd` — `GiveToFriendActivity`

**Anchor:** add as a new top-level class; register `GiveToFriendActivity.new()`
in `setup()`'s `_candidates` list.

```gdscript
class GiveToFriendActivity extends NPCActivity:
	## NPC→NPC Give (Aug 2026). Fetch phase mirrors JobActivity's fetch
	## exactly (find/claim/grab a loose item); travel phase mirrors
	## SnatchActivity's continuous re-aim at a moving target; hand-off
	## reuses can_receive_item()/on_item_given() unchanged in spirit
	## (just told who the giver actually is). Interruptible throughout —
	## unlike Snatch, this is a low-stakes altruistic errand, fine to
	## abandon if something more pressing comes up.
	var _friend: Node = null
	var _loose: RigidBody3D = null

	func label() -> String:
		return "Bringing %s something" % _friend.npc_name if _friend != null and _loose == null and npc_holds_nothing() else "Getting an item for a friend"

	## Small helper avoiding a direct `npc` reference in label() (label()
	## has no npc param) — see note below if your NPCActivity base differs;
	## simplest fallback if this causes issues is just a flat "Helping a friend" label.
	func npc_holds_nothing() -> bool:
		return true

	func score(npc: NPC) -> float:
		if not npc.has_needy_friend():
			return 0.0
		return GIVE_TO_FRIEND_BASE_SCORE * npc.get_work_ethic_passive_mult()

	func interruptible() -> bool:
		return true

	func enter(npc: NPC) -> void:
		var result: Dictionary = npc.find_friend_to_help()
		if result.is_empty():
			return
		_friend = result.get("friend")
		_loose = result.get("item")
		if not NPCItemUser.claim_item(_loose, npc):
			_friend = null
			_loose = null
			return
		npc.set_nav_target(_loose.global_position)

	func tick(npc: NPC, delta: float) -> void:
		if _friend == null or not is_instance_valid(_friend):
			_friend = null
			_loose = null
			return

		if npc.held_item == null:
			## Fetch phase
			if _loose == null or not is_instance_valid(_loose):
				_friend = null
				_loose = null
				return
			if "is_held" in _loose and _loose.is_held:
				NPCItemUser.release_item(_loose)
				_friend = null
				_loose = null
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _loose.global_position) <= NPCItemUser.PICKUP_RANGE:
				if NPCItemUser.grab_loose(npc, _loose):
					_loose = null   ## fetched — travel phase starts next tick
				else:
					NPCItemUser.release_item(_loose)
					_friend = null
					_loose = null
			return

		## Travel phase — friend may have moved, or no longer needs it
		if not (float(_friend.hunger) < 90.0 or float(_friend.thirst) < 90.0):
			_friend = null   ## already fed some other way — no longer needed
			return
		npc.set_nav_target((_friend as Node3D).global_position)
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, (_friend as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
			if _friend.has_method("can_receive_item") and _friend.can_receive_item(npc.held_item):
				var item: Node = npc.held_item
				var friend_name: String = _friend.npc_name
				npc.held_item = null
				item.pickup((_friend as Node3D).hold_point)
				_friend.held_item = item
				_friend.on_item_given(item, npc.npc_id, npc.npc_name)
				npc.log_action("Gave %s to %s" % [item.get_display_name(), friend_name])
			_friend = null

	func done(npc: NPC) -> bool:
		return _friend == null and _loose == null and npc.held_item == null

	func exit(npc: NPC) -> void:
		if _loose != null:
			NPCItemUser.release_item(_loose)
			_loose = null
		if npc.held_item != null:
			## Interrupted mid-errand while actually carrying the item —
			## just let them keep it; they'll finish delivering (or eat it
			## themselves if truly needed) next time this activity re-enters,
			## since held_item persisting is harmless and re-searching from
			## scratch would waste a perfectly good fetched item.
			pass
		_friend = null
```

**Simplify `label()` if the helper feels awkward:** the placeholder
`npc_holds_nothing()` above is a workaround for `label()` not receiving
an `npc` parameter in this codebase's `NPCActivity` interface — if that
turns out clunky in practice, simplest fix is just returning a flat
`"Helping a friend"` from `label()` unconditionally; the exact wording
isn't load-bearing anywhere else.

---

## Part D — F7 debug buttons (optional but recommended given how much testing friction the player-Snatch feature had)

### `scripts/ui/menus/AdminMenu.gd`

Add three rows mirroring `_on_npc_force_snatch_pressed()`'s existing
pattern — find nearest ELIGIBLE pair (ignoring relationship/chance, same
spirit as `debug_force_snatch()`) and force them into the activity
directly. Given the added complexity of "nearest eligible PAIR" (two
NPCs, not one), a reasonable simplification for the debug buttons: just
call `force_talk_debug()`/`force_give_to_friend_debug()`/
`force_npc_snatch_debug()` on the nearest NPC and let it search among
other NPCs using its own normal logic, with the relationship/chance gate
temporarily bypassed via a `_debug_force_*` flag mirroring
`_debug_force_snatch`'s exact pattern. Given the scope already covered
above, implement these three following that established one-shot-flag
convention if you want them — flagging as a nice-to-have rather than
spelling out full code here, since the pattern to copy is already fully
specified by `debug_force_snatch()` earlier in this same file.

---

## Documentation

`docs/systems/npc/README.md` — new sections for Talking and
Give-to-Friend, generalize the existing Snatch section's "only ever
targets the player" framing (now targets either), update the Trait
Effects Reference (Work Ethic's passive multiplier now also applies to
Talking and Give-to-Friend).

**Testing Checklist:**

```
43. Push two NPCs' relationship well above +15 and place them near each
    other — confirm they talk noticeably more often than a neutral pair;
    push another pair below -15 — confirm noticeably less often.
44. Confirm a talking session locks BOTH NPCs in place, facing each
    other, for the session, and both get a "Talked to X" log entry.
45. Interrupt one NPC mid-conversation (F7 force-command something else)
    — confirm the partner doesn't get stuck waiting forever.
46. Set two NPCs' relationship to +40+, drain one's hunger, ensure a
    matching item exists — confirm the well-fed one occasionally fetches
    and delivers it; confirm the recipient's relationship toward the
    DONOR (not the player) goes up, and the donor's own log shows "Gave
    X to Y".
47. Set two NPCs' relationship to -60, drain the hostile one's hunger,
    give the disliked one a matching held item — confirm the hostile one
    snatches from the OTHER NPC (not the player) when eligible, and both
    sides' logs show it correctly.
48. With the player ALSO eligible (bad relationship, holding a matching
    item) alongside an eligible NPC target, confirm the nearest of the
    two gets picked, regardless of which type it is.
```
