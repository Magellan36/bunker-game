# NPC-NPC Snatch Cooldown + Talk Session Fixes (Aug 2026)

**File:** `scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd` only. The
`Player.gd` crash fix is a **separate file**:
`PLAYER_SUBSYSTEM_GET_HELD_ITEM_VALIDITY_FIX.md`.

---

## Part A — 10s cooldown between NPC↔NPC snatch attempts (same pair)

Prevents the back-and-forth "steal it back" loop — bidirectional, keyed
per-pair, separate from the existing 60s Snatch→Gift cooldown (that one
blocks gifting; this one blocks re-*attempting* a snatch against the same
NPC so soon).

### 1. `scripts/npc/NPC.gd`

**Anchor:** near the Snatch section.

Insert:

```gdscript
# ─── NPC↔NPC Snatch Pair Cooldown (Aug 2026) ────────────────────────────────
const NPC_SNATCH_PAIR_COOLDOWN_SEC: float = 10.0
var _npc_snatch_pair_cooldown: Dictionary = {}   ## other npc_id -> msec of last NPC-NPC snatch involving this pair (either direction)

## Set on BOTH NPCs involved whenever an NPC-NPC snatch happens (see
## SnatchActivity.tick()) — bidirectional, so the victim can't
## immediately retaliate either.
func start_npc_snatch_pair_cooldown(other_id: String) -> void:
	_npc_snatch_pair_cooldown[other_id] = Time.get_ticks_msec()

func is_npc_snatch_pair_on_cooldown(other_id: String) -> bool:
	if not _npc_snatch_pair_cooldown.has(other_id):
		return false
	return (Time.get_ticks_msec() - _npc_snatch_pair_cooldown[other_id]) < int(NPC_SNATCH_PAIR_COOLDOWN_SEC * 1000.0)
```

### 2. `scripts/npc/NPC.gd` — gate NPC candidates in `find_snatch_target()`

**Anchor:** the NPC-candidate loop:

```gdscript
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if get_relationship(other.npc_id) > SNATCH_RELATIONSHIP_THRESHOLD:
			continue
		var held: Node = other.held_item
```

Replace with:

```gdscript
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if get_relationship(other.npc_id) > SNATCH_RELATIONSHIP_THRESHOLD:
			continue
		if is_npc_snatch_pair_on_cooldown(other.npc_id):
			continue
		var held: Node = other.held_item
```

### 3. `scripts/npc/NPCBrain.gd` — `SnatchActivity` starts the pair cooldown

**Anchor:** in `tick()`, right after the existing snatch-cooldown/hostile-log
update block (from the previous plan):

```gdscript
		if _target != null and is_instance_valid(_target):
			var target_id: String = "player" if _target.is_in_group("player") else _target.npc_id
			npc.start_snatch_cooldown_against(target_id)
			npc.update_hostile_log()
```

Replace with:

```gdscript
		if _target != null and is_instance_valid(_target):
			var target_id: String = "player" if _target.is_in_group("player") else _target.npc_id
			npc.start_snatch_cooldown_against(target_id)
			npc.update_hostile_log()
			if not _target.is_in_group("player"):
				npc.start_npc_snatch_pair_cooldown(target_id)
				_target.start_npc_snatch_pair_cooldown(npc.npc_id)   ## bidirectional
```

---

## Part B — Talk: cooldown between sessions + needs take priority

### 1. `scripts/npc/NPC.gd` — session cooldown

**Anchor:** near the Talking section.

Insert:

```gdscript
## Randomized cooldown after ANY talk session ends (natural completion or
## interrupted) before this NPC can talk OR be talked to again. Without
## this, nothing stopped the same two NPCs immediately re-initiating the
## instant one conversation ended — which is what "randomly interrupted
## with brief Idles, several instances back to back" actually was: not a
## bug in the non-interruptibility logic itself, just nothing preventing
## rapid re-triggering. Same pattern already used for Relaxing.
const TALK_COOLDOWN_MIN_SEC: float = 30.0
const TALK_COOLDOWN_MAX_SEC: float = 90.0
var _talk_cooldown_until_msec: int = 0

func start_talk_cooldown() -> void:
	var cooldown_sec: float = randf_range(TALK_COOLDOWN_MIN_SEC, TALK_COOLDOWN_MAX_SEC)
	_talk_cooldown_until_msec = Time.get_ticks_msec() + int(cooldown_sec * 1000.0)

func is_talk_on_cooldown() -> bool:
	return Time.get_ticks_msec() < _talk_cooldown_until_msec
```

**Anchor:** `is_available_to_talk()`:

```gdscript
func is_available_to_talk() -> bool:
	if brain == null:
		return false
	if brain.is_relaxing() or brain.is_talking():
		return false
	return brain.is_current_interruptible()
```

Replace with:

```gdscript
func is_available_to_talk() -> bool:
	if brain == null:
		return false
	if brain.is_relaxing() or brain.is_talking():
		return false
	if is_talk_on_cooldown():
		return false
	return brain.is_current_interruptible()
```

**Anchor:** `end_talk_session()`:

```gdscript
func end_talk_session() -> void:
	if brain == null or not brain.is_talking():
		return
	var partner_name: String = brain.get_talk_partner_name()
	log_action("Talked to %s" % partner_name)
	brain.end_talk_if_talking()
```

Replace with:

```gdscript
func end_talk_session() -> void:
	if brain == null or not brain.is_talking():
		return
	var partner_name: String = brain.get_talk_partner_name()
	log_action("Talked to %s" % partner_name)
	brain.end_talk_if_talking()
	start_talk_cooldown()
```

### 2. `scripts/npc/NPCBrain.gd` — `TalkActivity` self-gates on cooldown, and needs interrupt it

**Anchor:** `score()`:

```gdscript
	func score(npc: NPC) -> float:
		if not _is_initiator:
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
		if npc.is_talk_on_cooldown():
			return 0.0
		if npc.find_talk_partner() == null:
			return 0.0
		return NPC.TALK_BASE_SCORE * npc.get_work_ethic_passive_mult()
```

**Anchor:** var declarations — add:

```gdscript
	var _self_npc: NPC = null   ## interruptible() has no npc parameter in this codebase's activity interface — stored here at enter() so it can check this NPC's own needs
```

**Anchor:** `enter()` — add as the first line:

```gdscript
	func enter(npc: NPC) -> void:
		if _is_initiator:
```

Replace with:

```gdscript
	func enter(npc: NPC) -> void:
		_self_npc = npc
		if _is_initiator:
```

**Anchor:** `interruptible()`:

```gdscript
	func interruptible() -> bool:
		return _partner == null   ## only interruptible in the brief instant before a partner locks in
```

Replace with:

```gdscript
	func interruptible() -> bool:
		if _partner == null:
			return true   ## brief instant before a partner locks in
		## Needs take priority over an ongoing conversation — same 55%
		## threshold Eat/DrinkActivity themselves auto-trigger on, so
		## "hungry enough to interrupt" means the same thing everywhere.
		if _self_npc != null and (float(_self_npc.hunger) < 55.0 or float(_self_npc.thirst) < 55.0):
			return true
		return false
```

**Anchor:** `exit()`:

```gdscript
	func exit(npc: NPC) -> void:
		if _partner != null and is_instance_valid(_partner) and _is_initiator:
			## interrupted some other way — don't leave the partner stuck
			if _partner.has_method("end_talk_session"):
				_partner.end_talk_session()
		_partner = null
```

Replace with:

```gdscript
	func exit(npc: NPC) -> void:
		if _partner != null and is_instance_valid(_partner) and _is_initiator:
			## interrupted some other way (including a low-needs abort) —
			## don't leave the partner stuck waiting forever
			if _partner.has_method("end_talk_session"):
				_partner.end_talk_session()
		if _duration > 0.0:
			npc.start_talk_cooldown()   ## covers both natural completion and any interrupt/abort path
		_partner = null
```

No change needed to how the abort actually happens — once `interruptible()`
can return true for low needs, the existing `_think()` switch logic
(`_current.interruptible() and best_score > _current.score(_npc) +
SWITCH_MARGIN`) handles the rest automatically: EatActivity/DrinkActivity
just need to out-score Talk's own re-evaluated score by the normal
margin, same mechanism every other activity switch already uses.

## Testing

```
55. Set two NPCs hostile toward each other with both needing food/water
    — confirm they no longer ping-pong steal the same item back and
    forth; after one snatch, neither can re-target the other for ~10s.
56. Watch a pair of NPCs talk repeatedly over several minutes — confirm
    each conversation now has a real gap (tens of seconds, not
    immediate) before either one starts another, and the log no longer
    shows a rapid burst of back-to-back "Talked to X" entries.
57. Get an NPC mid-conversation, then drain their hunger or thirst below
    55 (F7) — confirm they break off the conversation to go eat/drink,
    and their (former) partner doesn't get stuck waiting.
```
