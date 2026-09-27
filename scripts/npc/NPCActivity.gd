extends RefCounted
class_name NPCActivity
## NPCActivity.gd — base class for one thing an NPC can be doing.
## Lifecycle, driven by NPCBrain:
##   score(npc)     — utility score; higher wins. Called on think ticks for
##                    every candidate. Return <= 0.0 for "not now".
##   enter(npc)     — begin (set nav target etc).
##   tick(npc, dt)  — called every physics frame while active.
##   done(npc)      — return true when finished; brain then re-scores.
##   interruptible()— may a higher-scoring candidate cancel this mid-run?
##   exit(npc)      — cleanup (always called, on finish OR interrupt).
##                    Reservations are released by the brain afterwards
##                    automatically; exit() only needs to undo world state
##                    it changed itself (seats, work banners, obstacles).
##   label()        — short display string ("Wandering", "Sitting"...).
##   begin_with_item(npc, item) — optional; only Given* activities (a Give
##                    hand-off) implement this.
##   take_handoff() — optional one-shot successor (Snatch → GivenEat).
##
## Sep 2026 additions (all optional, all with safe defaults):
##   accepts_held_item(npc, item) — can this activity make use of what the
##                    NPC is already carrying? If not, NPCBrain sets the
##                    item down BEFORE enter(). Default: no. Override for
##                    any activity that continues with a held item.
##   is_need()      — a bodily need (eat/drink/rest). Needs may pull an NPC
##                    out of a long job at a safe point when urgent.
##   is_work()      — a chore/job. Forgetfulness only ever diverts work.
##   can_yield_to_need(npc) — is RIGHT NOW a safe moment to abandon this
##                    non-interruptible activity for an urgent need?
##   backoff_on_futile() — should the brain bench this activity for a while
##                    if it ends almost instantly (found nothing to do)?

func score(_npc: NPC) -> float: return 0.0
func enter(_npc: NPC) -> void: pass
func tick(_npc: NPC, _delta: float) -> void: pass
func done(_npc: NPC) -> bool: return true
func interruptible() -> bool: return true
func exit(_npc: NPC) -> void: pass
func label() -> String: return "Idle"
func begin_with_item(_npc: NPC, _item: Node) -> void: pass
func take_handoff() -> NPCActivity: return null

func accepts_held_item(_npc: NPC, _item: Node) -> bool: return false
func is_need() -> bool: return false
func is_work() -> bool: return false
func can_yield_to_need(_npc: NPC) -> bool: return false
func backoff_on_futile() -> bool: return true

## Optional — structured debug snapshot for NPCDebug's on-demand dumps.
## An override should include an "activity" String key.
func debug_info() -> Dictionary: return {}
