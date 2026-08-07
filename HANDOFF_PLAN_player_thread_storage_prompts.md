# Hand-off Plan: Storage Prompt Fixes (Player Thread — InteractionSystem.gd)

**For:** the Claude thread/agent handling Player systems
**From:** UI Claude thread
**File touched:** `scripts/player/InteractionSystem.gd` only — this is your
file, not something the UI thread edits directly. Everything on the
furniture side (`LightStorage.gd`, `Shelving.gd`) is already correct and
needs no further changes.

---

## Context

We're fixing a "which prompt shows near a Shelf/Dresser/End Table"
feature. `LightStorage.gd` (the shared base `Dresser.gd`/`EndTable.gd`
extend) and `Shelving.gd` are both already correct — confirmed by reading
them directly. The remaining bugs are entirely in this file's prompt
logic, and they explain every symptom that got reported:

- Shelving still shows BOTH "[F] Store item" and "[E] Open shelf" while
  holding a storable item.
- Dresser/End Table show nothing at all when empty-handed.
- Dresser/End Table show BOTH E and F while holding a storable (light)
  item.
- Dresser/End Table correctly show ONLY "[E] Open..." while holding
  something too large to store (a crate) — but only in that one case.

## Root cause 1 — I fixed the wrong branch last time

`_update_prompt()` has two entirely separate code paths: **CASE 1**
(`held_item != null`) and **CASE 2** (empty-handed). A previous UI-thread
pass added "only show F if it has something to say, otherwise fall back to
E" — but only inside CASE 2's `"shelving"` handling. **CASE 1 has its own
separate, un-fixed copy of the same F/E logic** ("Shelf nearby — separate
panel above the shelf"), which is the actual code path that runs whenever
the player is holding something. That's why holding a storable item still
shows both lines — the fix only ever applied to the empty-handed case.

## Root cause 2 — CASE 2's shelf discovery is fragile to spawn timing

CASE 2 finds `"shelving"`-group objects via `_tracked_bodies`, a set
populated by the player's `Area3D` `body_entered`/`body_exited` signals.
Those signals only fire on a genuine boundary crossing — a body that
**spawns already inside** the Area3D's volume (exactly what happens when a
player places a Dresser/End Table via Build Mode while standing right next
to where it lands) never triggers `body_entered`, so it never enters
`_tracked_bodies`, so CASE 2 never finds it — until the player walks
away and back (a real crossing). This is the identical class of bug
already fixed elsewhere in this file for `_quick_drop()` (search
"Jolt's Area3D body_entered only fires on a genuine boundary crossing" —
same root cause, different spot).

CASE 1 doesn't have this problem because `_nearest_shelf()` does a direct
`get_tree().get_nodes_in_group("shelving")` scan every frame — no Area3D
dependency at all. That's exactly why holding *anything* (storable or not)
correctly finds a freshly-placed Dresser/End Table, while being
empty-handed doesn't: CASE 1's discovery mechanism is immune to the spawn-
timing issue, CASE 2's isn't.

## The fix

1. Apply the same "F wins, E is the fallback" fix to CASE 1's shelf block
   (currently unfixed — this was the actual gap).
2. Give CASE 2 a genuine group-scan pass for `"shelving"` objects too,
   instead of relying solely on Area3D-tracked `_tracked_bodies` — mirrors
   `_nearest_shelf()`'s already-proven, timing-safe approach, but collects
   ALL nearby shelving objects (not just the single closest) since CASE 2
   supports showing up to `MAX_VISIBLE_PROMPTS` at once.

---

## Step 1 — Fix CASE 1's shelf block

Find this exact block:

```gdscript
		# Shelf nearby — separate panel above the shelf
		var nearby_shelf: Node3D = _nearest_shelf()
		if nearby_shelf != null:
			var shelf_lines: Array[String] = []
			if nearby_shelf.has_method("get_f_prompt"):
				var fp: String = nearby_shelf.get_f_prompt()
				if fp != "": shelf_lines.append(fp)
			if nearby_shelf.has_method("get_e_prompt"):
				var ep: String = nearby_shelf.get_e_prompt()
				if ep != "": shelf_lines.append(ep)
			if not shelf_lines.is_empty():
				var shelf_pos: Vector3 = nearby_shelf.global_position + Vector3(0.0, 2.3, 0.0)
				if nearby_shelf.has_method("get_prompt_world_pos"):
					shelf_pos = nearby_shelf.get_prompt_world_pos()
				entries.append({ "text": "\n".join(shelf_lines), "world_pos": shelf_pos, "dist": 0.0 })
```

Replace it with exactly this:

```gdscript
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
```

## Step 2 — Give CASE 2 a timing-safe shelving scan

Find this exact block (right after Pass 2's static/frozen scan, before the
"Closest first" sort):

```gdscript
	## Fire set_player_in_range(false) for any static nodes that left range.
	for gone_node in _static_in_range:
		if not static_in_range_now.has(gone_node) and is_instance_valid(gone_node):
			if gone_node.has_method("set_player_in_range"):
				gone_node.set_player_in_range(false)
	_static_in_range = static_in_range_now

	# Closest first so nearest panel renders on top
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["dist"] < b["dist"])
```

Replace it with exactly this:

```gdscript
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
```

---

## Verification checklist

1. Empty-handed, walk up to a freshly-placed (same session) Dresser or End
   Table — confirm "[E] Open..." shows immediately, no need to walk away
   and back.
2. Empty-handed near a pre-existing/loaded Shelf — confirm still works as
   before (no regression).
3. Hold a small storable item, walk up to a Shelf — confirm ONLY "[F]
   Store item" (or "[F] Shelf full") shows, no "[E] Open shelf" alongside
   it.
4. Same test near a Dresser/End Table — confirm ONLY "[F] Store item" (or
   "Dresser Full"/"End Table Full") shows.
5. Hold something too large to store (a crate), walk up to a Shelf,
   Dresser, and End Table — confirm all three still correctly show ONLY
   "[E] Open..." (this case already worked, confirm it's unaffected).
6. Confirm opening (E) and storing (F) still function correctly in every
   case above — this pass only changes which TEXT is shown, not what E/F
   actually do.
7. Confirm no console errors referencing `InteractionSystem`.
