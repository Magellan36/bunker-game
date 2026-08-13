extends NPCCommandWrapperActivity
class_name CommandRestActivity
## "Take a load off" player command (Part 19). Tries a bed first
## (better rest, per LieActivity), falls back to a chair (SitActivity)
## if no bed is free/reachable. Delegates entirely to whichever inner
## activity is chosen, so arrival/occupancy/energy-regen behavior is
## identical to the needs-driven versions — this only decides which one
## to try, and does so regardless of current Energy (a player command
## should work even if Energy is high, unlike the automatic versions
## which only compete for selection below 60). See
## NPCCommandWrapperActivity.gd for the shared shape.
##
## Deliberate exception: overrides enter() directly instead of just
## _make_inner(), because the bed-vs-chair choice depends on calling
## done() on the bed candidate AFTER entering it (to detect "no bed
## reachable") — _make_inner() alone can't express a decision that
## depends on the result of entering its own candidate. The base's
## _make_inner() default (push_error + return null) is left untouched
## and is never called by this subclass.
func enter(npc: NPC) -> void:
	_inner = LieActivity.new()
	_inner.enter(npc)
	if _inner.done(npc):   ## no bed available/reachable — fall back to a chair
		_inner.exit(npc)
		_inner = SitActivity.new()
		_inner.enter(npc)