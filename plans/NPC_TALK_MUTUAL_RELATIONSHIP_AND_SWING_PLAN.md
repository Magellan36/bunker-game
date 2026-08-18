# Talk: Mutual-Relationship Frequency + Random Conversation Outcomes (Aug 2026)

**File:** `scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd` only.

Every new cross-file call added in this plan goes through a
`has_method()` guard from the start, per what we just learned about
Godot's resolution quirk with newly-added cross-referencing methods
between these two files.

---

## Part A — Talk frequency uses MUTUAL relationship, not one-directional

### 1. `scripts/npc/NPC.gd` — `get_talk_score_mult()` takes the partner node, averages both directions

**Anchor:** the current function:

```gdscript
func get_talk_score_mult(other_id: String) -> float:
	var rel: float = get_relationship(other_id)
	if rel > TALK_RELATIONSHIP_NEUTRAL_HIGH:
		var t: float = clampf((rel - TALK_RELATIONSHIP_NEUTRAL_HIGH) / (RELATIONSHIP_MAX - TALK_RELATIONSHIP_NEUTRAL_HIGH), 0.0, 1.0)
		return lerp(1.0, TALK_SCORE_MULT_MAX, t)
	elif rel < TALK_RELATIONSHIP_NEUTRAL_LOW:
		var t: float = clampf((TALK_RELATIONSHIP_NEUTRAL_LOW - rel) / (TALK_RELATIONSHIP_NEUTRAL_LOW - RELATIONSHIP_MIN), 0.0, 1.0)
		return lerp(1.0, TALK_SCORE_MULT_MIN, t)
	return 1.0
```

Replace with:

```gdscript
## Takes the partner NODE (not just an id) so it can read BOTH
## directions — "mutually high" means averaging this NPC's feeling
## toward them AND their feeling toward this NPC, not just one side.
## The previous version only ever considered the initiator's own
## one-directional relationship.
func get_talk_score_mult(other: Node) -> float:
	if other == null or not is_instance_valid(other):
		return 1.0
	var other_id: String = String(other.npc_id) if ("npc_id" in other) else ""
	if other_id == "":
		return 1.0
	var rel_mine: float = get_relationship(other_id)
	var rel_theirs: float = other.get_relationship(npc_id) if other.has_method("get_relationship") else rel_mine
	var mutual_rel: float = (rel_mine + rel_theirs) / 2.0
	if mutual_rel > TALK_RELATIONSHIP_NEUTRAL_HIGH:
		var t: float = clampf((mutual_rel - TALK_RELATIONSHIP_NEUTRAL_HIGH) / (RELATIONSHIP_MAX - TALK_RELATIONSHIP_NEUTRAL_HIGH), 0.0, 1.0)
		return lerp(1.0, TALK_SCORE_MULT_MAX, t)
	elif mutual_rel < TALK_RELATIONSHIP_NEUTRAL_LOW:
		var t: float = clampf((TALK_RELATIONSHIP_NEUTRAL_LOW - mutual_rel) / (TALK_RELATIONSHIP_NEUTRAL_LOW - RELATIONSHIP_MIN), 0.0, 1.0)
		return lerp(1.0, TALK_SCORE_MULT_MIN, t)
	return 1.0
```

### 2. `scripts/npc/NPCBrain.gd` — `TalkActivity.score()` uses the found partner directly

**Anchor:**

```gdscript
	func score(npc: NPC) -> float:
		if not _is_initiator:
			return 0.0
		if npc.has_method("is_talk_on_cooldown") and npc.is_talk_on_cooldown():
			return 0.0
		if npc.find_talk_partner() == null:
			return 0.0
		return NPC.TALK_BASE_SCORE * npc.get_work_ethic_passive_mult()
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if not _is_initiator:
			return 0.0
		if npc.has_method("is_talk_on_cooldown") and npc.is_talk_on_cooldown():
			return 0.0
		var partner: Node = npc.find_talk_partner()
		if partner == null:
			return 0.0
		var mult: float = npc.get_talk_score_mult(partner) if npc.has_method("get_talk_score_mult") else 1.0
		return NPC.TALK_BASE_SCORE * npc.get_work_ethic_passive_mult() * mult
```

---

## Part B — Random small relationship swing per conversation, with matching log entry

Applies once per participant, independently, ONLY on a natural
completion (duration elapsed) — an interrupted/aborted conversation
(needs took priority, etc.) does not get a swing, since it didn't really
happen properly.

### 1. `scripts/npc/NPC.gd` — the roll + log

**Anchor:** near the Talking section.

Insert:

```gdscript
const TALK_RELATIONSHIP_DELTA_MIN: int = 1
const TALK_RELATIONSHIP_DELTA_MAX: int = 3

## Called independently on EACH participant at natural conversation end.
## Uniform magnitude 1-3, random sign — routed through
## _adjust_relationship() like every other relationship-affecting event,
## so it's Sociability-scaled the same way Give/Takeaway/etc. already are
## (meaning the logged number won't always be a clean integer — same
## %+.1f convention every other relationship log line already uses).
func apply_talk_relationship_swing(partner_id: String, partner_name: String) -> void:
	var magnitude: float = float(randi_range(TALK_RELATIONSHIP_DELTA_MIN, TALK_RELATIONSHIP_DELTA_MAX))
	var base_delta: float = magnitude if randf() < 0.5 else -magnitude
	var applied: float = _adjust_relationship(partner_id, base_delta)
	var label: String = "Good Conversation" if applied > 0.0 else ("Bad Conversation" if applied < 0.0 else "Neutral Conversation")
	log_action("Relationship with %s %+.1f (%s)" % [partner_name, applied, label])
```

### 2. `scripts/npc/NPC.gd` — `end_talk_session()` learns whether it was natural

**Anchor:** the current function:

```gdscript
func end_talk_session() -> void:
	if brain == null or not brain.is_talking():
		return
	var partner_name: String = brain.get_talk_partner_name()
	log_action("Talked to %s" % partner_name)
	brain.end_talk_if_talking()
	start_talk_cooldown()
```

Replace with:

```gdscript
## natural=true (default) means the conversation actually ran its course
## — a relationship swing applies. natural=false (interrupted some other
## way) skips the swing.
func end_talk_session(natural: bool = true) -> void:
	if brain == null or not brain.is_talking():
		return
	var partner_name: String = brain.get_talk_partner_name()
	log_action("Talked to %s" % partner_name)
	if natural and brain.has_method("get_talk_partner_id"):
		var partner_id: String = brain.get_talk_partner_id()
		if partner_id != "":
			apply_talk_relationship_swing(partner_id, partner_name)
	brain.end_talk_if_talking()
	start_talk_cooldown()
```

### 3. `scripts/npc/NPCBrain.gd` — `get_talk_partner_id()`

**Anchor:** near `get_talk_partner_name()`.

Insert:

```gdscript
func get_talk_partner_id() -> String:
	if _current is TalkActivity:
		var t: TalkActivity = _current as TalkActivity
		if t._partner != null and is_instance_valid(t._partner) and ("npc_id" in t._partner):
			return String(t._partner.npc_id)
	return ""
```

### 4. `scripts/npc/NPCBrain.gd` — wire both sides of natural completion

**Anchor:** `TalkActivity.tick()`'s duration-elapsed branch:

```gdscript
		_elapsed += delta
		if _elapsed >= _duration:
			if _partner.has_method("end_talk_session"):
				_partner.end_talk_session()
			npc.log_action("Talked to %s" % _partner.npc_name)
			_partner = null
```

Replace with:

```gdscript
		_elapsed += delta
		if _elapsed >= _duration:
			if _partner.has_method("end_talk_session"):
				_partner.end_talk_session(true)
			npc.log_action("Talked to %s" % _partner.npc_name)
			if npc.has_method("apply_talk_relationship_swing") and ("npc_id" in _partner):
				npc.apply_talk_relationship_swing(_partner.npc_id, _partner.npc_name)
			_partner = null
```

**Anchor:** `TalkActivity.exit()` — the interrupt-handling branch:

```gdscript
	func exit(npc: NPC) -> void:
		if _partner != null and is_instance_valid(_partner) and _is_initiator:
			## interrupted some other way (including a low-needs abort) —
			## don't leave the partner stuck waiting forever
			if _partner.has_method("end_talk_session"):
				_partner.end_talk_session()
```

Replace with:

```gdscript
	func exit(npc: NPC) -> void:
		if _partner != null and is_instance_valid(_partner) and _is_initiator:
			## interrupted some other way (including a low-needs abort) —
			## don't leave the partner stuck waiting forever; natural=false
			## since this path only ever fires when the conversation did
			## NOT reach its normal duration-elapsed ending (that path
			## already nulls _partner before exit() runs, so this branch
			## is exclusively the "cut short" case).
			if _partner.has_method("end_talk_session"):
				_partner.end_talk_session(false)
```

## Testing

```
60. Push two NPCs' MUTUAL relationship high (both directions, not just
    one) and confirm they talk more often than a pair where only ONE
    side likes the other equally strongly — the one-sided pair should
    now behave closer to neutral frequency.
61. Let several conversations complete naturally — confirm each
    produces a "Relationship with X ±N.N (Good/Bad Conversation)" line
    right after "Talked to X" in both participants' own logs, with
    independent (not necessarily matching) values on each side.
62. Interrupt a conversation via low needs — confirm NO relationship
    swing line appears for either participant, just the normal
    "Talked to X" (or nothing, if it was cut short before ever really
    starting).
```
