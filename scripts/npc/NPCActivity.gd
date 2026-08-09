extends RefCounted
class_name NPCActivity
## NPCActivity.gd  (NPC Pass 2, Part 2)
## Base class for one thing an NPC can be doing. Subclasses live inline in
## NPCBrain.gd (wander/sit) and later parts add more (eat/drink/jobs).
## Lifecycle, driven by NPCBrain:
##   score(npc)     — static-ish utility score; higher wins. Called on think
##                    ticks for every candidate. Return <= 0.0 for "not now".
##   enter(npc)     — begin (set nav target etc).
##   tick(npc, dt)  — called every physics frame while active.
##   done(npc)      — return true when finished; brain then re-scores.
##   interruptible()— may a higher-scoring candidate cancel this mid-run?
##   exit(npc)      — cleanup (always called, on finish OR interrupt).
##   label()        — short display string ("Wandering", "Sitting"...), used
##                    by UI in Part 5.
##   begin_with_item(npc, item) — Part 28 — optional; only Given* activities
##                    (a player Give hand-off) implement this. Called once,
##                    right after enter(), whenever this activity is
##                    reached either via NPC.receive_item_from_player()'s
##                    force_command() sequence, or via a take_handoff()
##                    transition (Part 30) from another activity.
##   take_handoff()  — Part 30 — optional. Return a specific NPCActivity
##                    to switch to immediately (checked every tick, right
##                    after tick() runs), instead of finishing via done()
##                    and leaving the choice to normal think-cycle
##                    scoring. Used for SnatchActivity handing off to
##                    GivenEatActivity/GivenDrinkActivity on a successful
##                    grab. Returning non-null MUST be a one-shot — clear
##                    your own reference before returning it, so it never
##                    fires twice.

func score(_npc: NPC) -> float: return 0.0
func enter(_npc: NPC) -> void: pass
func tick(_npc: NPC, _delta: float) -> void: pass
func done(_npc: NPC) -> bool: return true
func interruptible() -> bool: return true
func exit(_npc: NPC) -> void: pass
func label() -> String: return "Idle"
func begin_with_item(_npc: NPC, _item: Node) -> void: pass
func take_handoff() -> NPCActivity: return null

## Optional (Aug 2026) — structured debug snapshot for NPCDebug's on-demand
## dumps. Empty Dictionary means "nothing interesting to show" (the
## default, for every activity that doesn't override this). An activity
## that DOES override it should include an "activity" String key so a
## dump can filter to just the activity type it cares about (see
## CleaningActivity.debug_info() for the pattern).
func debug_info() -> Dictionary: return {}