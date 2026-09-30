extends NPCActivity
class_name NPCCommandWrapperActivity
## NPCCommandWrapperActivity.gd (Aug 2026) — shared shape for "player
## pressed a Talk-menu button" wrappers. CommandCleaningActivity,
## CommandRefuelActivity, and CommandGardeningActivity were three
## 100%-identical files (thin delegation to an inner activity) except
## for which inner activity they construct — and, found during THIS
## pass, all three had independently drifted the same way: none of
## them delegated debug_info(), so "Print NPC Job Debug State" silently
## showed nothing for anything running via a player command. Subclasses
## now only need to override _make_inner().
var _inner: NPCActivity = null

func label() -> String:
	return _inner.label() if _inner != null else "Idle"

func score(_npc: NPC) -> float:
	return 0.0   ## command-only — never competes for autonomous pick

func interruptible() -> bool:
	return _inner == null or _inner.interruptible()

func debug_info() -> Dictionary:
	return _inner.debug_info() if _inner != null else {}

func enter(npc: NPC) -> void:
	_inner = _make_inner(npc)
	_inner.enter(npc)
	if _inner.done(npc):
		_inner = null

func tick(npc: NPC, delta: float) -> void:
	if _inner != null:
		_inner.tick(npc, delta)

func done(npc: NPC) -> bool:
	return _inner == null or _inner.done(npc)

## Forward the inner activity's hand-off (e.g. Gardening → "put the soil
## away"). Without this, an ordered job whose inner activity handed off
## never finished: done() waited on a hand-off nobody took, and the resident
## stood holding the item under a stale label (Sep 2026: Finch holding soil
## as "Planting seeds").
func take_handoff() -> NPCActivity:
	return _inner.take_handoff() if _inner != null else null

func exit(npc: NPC) -> void:
	if _inner != null:
		_inner.exit(npc)
	_inner = null

## Subclasses override this ONE method — construct and configure
## whatever inner activity this command backs.
func _make_inner(_npc: NPC) -> NPCActivity:
	push_error("NPCCommandWrapperActivity._make_inner() not overridden")
	return null

## Delegates the hands policy to the inner activity this command would run.
func accepts_held_item(npc: NPC, item: Node) -> bool:
	var probe: NPCActivity = _inner if _inner != null else _make_inner(npc)
	return probe != null and probe.accepts_held_item(npc, item)

func backoff_on_futile() -> bool:
	return false
