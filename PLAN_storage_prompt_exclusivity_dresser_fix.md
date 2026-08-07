# Plan: Storage Prompt Exclusivity Rule + Dresser/End Table UI Fix

**Owner of this plan:** UI Claude instance (HUD/menus/Build Mode/Furniture)
**Scope:** `scripts/world/furniture/LightStorage.gd` (mine — furniture
scope), plus a small, necessary edit to `scripts/player/InteractionSystem.gd`
— flagged since that file is Player-thread-owned, but the fix has to live
in its shared prompt-aggregation logic.

---

## 1. Root cause of the Dresser/End Table bug — found, and it's precise

I traced why Shelving shows a prompt when empty-handed but Dresser/End
Table don't, rather than assuming they're built the same way.

`InteractionSystem._update_prompt()`'s empty-handed branch gathers prompt
candidates from two passes: Pass 1 (bodies the player's `Area3D` is
currently tracking, requires membership in `"interactable"` OR `"pickup"`)
and Pass 2 (a `get_tree().get_nodes_in_group("interactable")` scan for
`StaticBody3D`/frozen bodies, which **explicitly skips anything in the
`"shelving"` group** — its own comment says "Shelves handled separately
above").

**`Shelving.gd` joins BOTH `"interactable"` and `"shelving"`** — so even
though Pass 2 skips it (it's in `"shelving"`), it still qualifies for Pass
1 (it's also in `"interactable"`), and that's the path that actually shows
its prompt today.

**`LightStorage.gd` (the shared base `Dresser.gd`/`EndTable.gd` both
extend) only joins `"shelving"`** — never `"interactable"`. That means it
fails Pass 1's requirement AND gets explicitly skipped by Pass 2. It falls
into the gap between both passes and never becomes a prompt candidate at
all — not "the UI looks different," genuinely never shown. One missing
`add_to_group()` call, precise fix.

(Confirmed this wasn't something I broke — `LightStorage.gd` was written
by a different pass/thread, already correctly implementing the
`StorageUI` contract and the `on_e_interact`/`on_f_interact` duck-type
contract, just missing this one group membership that makes the passive
prompt visible.)

### Step 1.1 — Edit `scripts/world/furniture/LightStorage.gd`

Find this exact block:

```gdscript
func _ready() -> void:
	collision_layer = 5   ## wall/pillar/shelving/table convention
	collision_mask  = 0
	stored.resize(capacity)
	_build_mesh()
	if _is_preview_only:
		return
	add_to_group("shelving")
```

Replace it with exactly this:

```gdscript
func _ready() -> void:
	collision_layer = 5   ## wall/pillar/shelving/table convention
	collision_mask  = 0
	stored.resize(capacity)
	_build_mesh()
	if _is_preview_only:
		return
	add_to_group("shelving")
	## Aug 2026 fix — Shelving.gd joins BOTH "interactable" and "shelving";
	## this file only joined "shelving", which InteractionSystem's Pass 2
	## (the static-body scan) explicitly EXCLUDES on purpose (its own
	## comment claims shelving-group objects are "handled separately" —
	## that separate handling is Pass 1, which requires "interactable" OR
	## "pickup" membership). Without this line, End Table/Dresser fell into
	## the gap between both passes and never became a prompt candidate at
	## all — not a display bug, they were simply never scanned.
	add_to_group("interactable")
```

---

## 2. "X Full" for Dresser/End Table (Shelving already does this correctly)

While tracing this I found `Shelving.gd`'s own `get_f_prompt()` already
returns `"[F] Shelf full"` when full — it's `LightStorage.gd`'s version
that currently returns an empty string in the full case (so today, a full
Dresser/End Table would just silently show nothing for F). Matching
Shelving's existing behavior.

### Step 2.1 — Edit `scripts/world/furniture/LightStorage.gd`

Find this exact block:

```gdscript
func get_f_prompt() -> String:
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null or _interaction_system.held_item == null:
		return ""
	var item: RigidBody3D = _interaction_system.held_item
	if not item.is_in_group("inventory_item"):
		return ""
	if is_full():
		return ""
	return "[F] Store item"
```

Replace it with exactly this:

```gdscript
func get_f_prompt() -> String:
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null or _interaction_system.held_item == null:
		return ""
	var item: RigidBody3D = _interaction_system.held_item
	if not item.is_in_group("inventory_item"):
		return ""
	if is_full():
		return "%s Full" % display_name   ## Aug 2026 — was "", matching Shelving.gd's existing "[F] Shelf full" pattern
	return "[F] Store item"
```

---

## 3. The exclusivity rule: only ONE prompt line when holding a storable item

**The actual danger you flagged is real and worth being precise about**:
while the player is holding ANYTHING, pressing E is bound to the HELD
ITEM's own action (`InteractionSystem`'s CASE 1 branch), never to a
nearby shelf's `on_e_interact()` — that only fires in CASE 2 (empty-
handed). So `"[E] Open Dresser"` showing while something is held was
always describing something E wouldn't actually do in that moment, not
just visually confusing.

**Fix, scoped exactly to what you asked** (storable items specifically):
when a shelf/dresser/end table's `get_f_prompt()` has something to say
(either "Store item" or, after §2, "X Full"), that's the ONLY line shown
— the "[E] Open..." line is suppressed. When `get_f_prompt()` has nothing
to say (empty-handed, or holding something non-storable), "[E] Open..."
shows normally, exactly as today.

**One thing worth flagging, not fixing here**: this only covers storable
items, matching your scoping ("generally smaller items"). A player holding
something NON-storable (a tool, a large item) near a shelf would still see
"[E] Open..." even though E is still bound to that held item's own action
in that state too — the same underlying risk, just outside what you asked
me to change. Let me know if you want that covered as well; it's the same
one-line pattern below, just without the storable-only gate.

### Step 3.1 — Edit `scripts/player/InteractionSystem.gd` (flagged: Player-thread scope, but the fix has to live in this shared aggregation logic)

Find this exact block:

```gdscript
		if body.is_in_group("shelving"):
			if body.has_method("get_f_prompt"):
				var fp: String = body.get_f_prompt()
				if fp != "": lines.append(fp)
			if body.has_method("get_e_prompt"):
				var ep: String = body.get_e_prompt()
				if ep != "": lines.append(ep)
```

Replace it with exactly this:

```gdscript
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
```

---

## 4. Verification checklist

1. Empty-handed, walk up to a Dresser or End Table — confirm "[E] Open
   dresser"/"[E] Open end table" now shows (previously nothing showed at
   all).
2. Press E — confirm the shared `StorageUI` panel opens, showing the
   correct grid/row labels/capacity for that furniture type.
3. Pick up a small storable item (e.g. a seed packet), walk up to a Shelf
   — confirm you now see ONLY "[F] Store item" (or "[F] Shelf full" if
   full), no "[E] Open shelf" line alongside it.
4. Same test near a Dresser/End Table — confirm ONLY "[F] Store item" (or
   the new "Dresser Full"/"End Table Full" text if full) shows.
5. Empty-handed near all three (Shelf, Dresser, End Table) — confirm
   "[E] Open..." still shows normally with no F line, exactly as before.
6. Hold a non-storable item near a shelf — confirm behavior is unchanged
   from before this pass (still shows "[E] Open...", per §3's flagged
   note).
7. Confirm no console errors referencing `LightStorage`, `Dresser`,
   `EndTable`, `Shelving`, or `InteractionSystem`.
