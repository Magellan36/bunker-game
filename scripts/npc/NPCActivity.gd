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

func score(_npc: NPC) -> float: return 0.0
func enter(_npc: NPC) -> void: pass
func tick(_npc: NPC, _delta: float) -> void: pass
func done(_npc: NPC) -> bool: return true
func interruptible() -> bool: return true
func exit(_npc: NPC) -> void: pass
func label() -> String: return "Idle"