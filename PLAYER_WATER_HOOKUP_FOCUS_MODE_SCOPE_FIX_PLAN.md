# Plan: Scope Water Hookup Priority to Focus Mode Only (Aug 2026)

**Owner:** Player subsystem (this plan) — correction to
`PLAYER_WATER_HOOKUP_E_PRIORITY_PLAN.md`.
**File touched:** `scripts/player/InteractionSystem.gd`.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.

---

## Root cause — not a simple bug, an architecture change I built against

Confirmed by reading the current code directly: **Focus Mode no longer
shares its target resolution with real `E` dispatch at all.** My prior
plan put the Water Hookup override inside `_nearest_generic_interactable()`,
which at the time was the single function both `_try_interact()` (real
`E`) and `_resolve_current_e_target()` (Focus Mode's peek) shared — that
was the deliberate "guaranteed to never disagree" design I described and
flagged when I wrote it.

Since then, a separate pass rewrote Focus Mode entirely (see the
in-code comment, "Aug 2026 v2 — Focus Mode, broadened"): `
_resolve_current_e_target()` was **removed**, and Focus Mode now computes
its own `is_focus_target` tag directly from the CASE 2 prompt-entry list
— simplest entry by distance (`entries[0]`), with the grow-light-over-
tray override re-implemented separately on top of *that* list. This new
path never calls `_nearest_generic_interactable()` at all.

So the Water Hookup override I wrote has been doing exactly the opposite
of what you're now seeing described — it's been affecting **only** the
real `E`-press path (`_try_interact()`, still the sole caller of
`_nearest_generic_interactable()`) and has had **zero** effect on Focus
Mode's actual mechanism this whole time. Two separate, independent
priority systems exist now where there used to be one shared one, and I
put the fix in the one that turned out to be the wrong one for what you
actually wanted.

---

## The fix

1. Remove the Water Hookup override from `_nearest_generic_interactable()`
   entirely — restores plain `E` presses to fair-distance-only, exactly
   as they behaved before my prior plan (the grow-light-over-tray
   override there is untouched — you haven't flagged that one as a
   problem, and it should keep applying to both paths).
2. Add the equivalent override to the *actual* current Focus Mode
   mechanism — the `focus_idx` computation in `_update_prompt()` —
   mirroring the existing `farming_tray`→`grow_light` swap pattern
   that's already there for the same reason.

`WaterHookup.gd`'s `"water_hookup"` group registration from the prior
plan is unaffected and still needed — no change to that file.

### Change 1 — remove the override from `_nearest_generic_interactable()`

**Anchor:** verified current lines 1075–1122.

```gdscript
old_str:
	var static_reach: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
	var nearest_grow_light: Node3D     = null
	var nearest_grow_light_dist: float = INF
	var nearest_water_hookup: Node3D     = null
	var nearest_water_hookup_dist: float = INF
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node):
			continue
		if not (node is StaticBody3D):
			continue
		if not node.has_method("on_interact"):
			continue
		if node.is_in_group("shelved"):
			continue
		var n3: Node3D = node as Node3D
		var d: float = n3.global_position.distance_to(player_pos)
		if node.is_in_group("grow_light") and d < static_reach and d < nearest_grow_light_dist:
			nearest_grow_light_dist = d
			nearest_grow_light = n3
		if node.is_in_group("water_hookup") and d < static_reach and d < nearest_water_hookup_dist:
			nearest_water_hookup_dist = d
			nearest_water_hookup = n3
		if d < static_reach and d < closest_dist:
			closest_dist = d
			closest = n3

	if nearest_grow_light != null and closest != null and closest.is_in_group("farming_tray"):
		closest      = nearest_grow_light
		closest_dist = nearest_grow_light_dist

	## Aug 2026 — Water Hookup: unconditional top priority whenever in
	## reach at all, applied AFTER the grow-light override so it wins
	## even in the extremely unlikely case both would otherwise fire the
	## same frame. Deliberately unscoped, unlike the grow-light override
	## above (which only beats one specific named rival, FarmingTray) —
	## a Water Hookup can end up near any number of different wall-
	## mounted objects depending on how a given bunker is furnished, so
	## there's no single fixed rival worth naming; it simply always wins
	## over whatever else is in range. This also means a plain E press
	## (not just Focus Mode's Ctrl-held highlight) now always resolves to
	## the hookup when one's in reach — deliberate, not an oversight; see
	## this plan's own header for why decoupling the two would be worse.
	if nearest_water_hookup != null:
		closest      = nearest_water_hookup
		closest_dist = nearest_water_hookup_dist

	return { "node": closest, "dist": closest_dist }

new_str:
	var static_reach: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
	var nearest_grow_light: Node3D     = null
	var nearest_grow_light_dist: float = INF
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node):
			continue
		if not (node is StaticBody3D):
			continue
		if not node.has_method("on_interact"):
			continue
		if node.is_in_group("shelved"):
			continue
		var n3: Node3D = node as Node3D
		var d: float = n3.global_position.distance_to(player_pos)
		if node.is_in_group("grow_light") and d < static_reach and d < nearest_grow_light_dist:
			nearest_grow_light_dist = d
			nearest_grow_light = n3
		if d < static_reach and d < closest_dist:
			closest_dist = d
			closest = n3

	if nearest_grow_light != null and closest != null and closest.is_in_group("farming_tray"):
		closest      = nearest_grow_light
		closest_dist = nearest_grow_light_dist

	## Aug 2026, then Aug 2026 (correction) — a Water Hookup priority
	## override briefly lived here, but this function is ONLY reached by
	## real E dispatch (_try_interact()) since Focus Mode was rewritten
	## to compute its own is_focus_target independently (see
	## _update_prompt()'s "Aug 2026 v2" comment) — putting the override
	## here made a plain E press always resolve to a nearby hookup, which
	## was never the intent. Moved to _update_prompt()'s focus_idx
	## computation instead, the thing that's actually Focus-Mode-only.
	return { "node": closest, "dist": closest_dist }
```

### Change 2 — add the override to Focus Mode's actual `focus_idx` computation

**Anchor:** verified current lines 807–816.

```gdscript
old_str:
	var focus_idx: int = -1
	if not entries.is_empty():
		focus_idx = 0
		if entry_bodies[0].is_in_group("farming_tray"):
			for i: int in entry_bodies.size():
				if entry_bodies[i].is_in_group("grow_light"):
					focus_idx = i
					break
	for i: int in entries.size():
		entries[i]["is_focus_target"] = (i == focus_idx)

new_str:
	var focus_idx: int = -1
	if not entries.is_empty():
		focus_idx = 0
		if entry_bodies[0].is_in_group("farming_tray"):
			for i: int in entry_bodies.size():
				if entry_bodies[i].is_in_group("grow_light"):
					focus_idx = i
					break
		## Aug 2026 (correction) — Water Hookup: unconditional Focus Mode
		## priority whenever one is anywhere in the CURRENT prompt set
		## (i.e. already within normal prompt range — nothing new opened
		## up here), overriding whatever the distance-based pick above
		## was. Deliberately Focus-Mode-only, unlike the grow-light
		## override just above — a plain E press
		## (_try_interact()/_nearest_generic_interactable()) resolves by
		## fair distance only and is untouched by this. Mounted high on
		## the wall, so it's otherwise almost always farther than
		## lower-mounted wall objects sharing the same wall and would
		## rarely be entries[0] on raw distance alone — this is what
		## makes Ctrl useful for reaching it specifically.
		for i: int in entry_bodies.size():
			if entry_bodies[i].is_in_group("water_hookup"):
				focus_idx = i
				break
	for i: int in entries.size():
		entries[i]["is_focus_target"] = (i == focus_idx)
```

---

## Why this is correct now

- **Matches your stated requirement exactly:** `is_focus_target` is only
  ever read by `InteractPrompt.gd`'s Focus Mode filter (confirmed via
  direct grep — its only consumer), and that filter only applies while
  `Input.is_key_pressed(KEY_CTRL)` is true. A plain `E` press never
  touches this list at all, so this genuinely cannot leak into
  non-Ctrl behavior the way the last version did.
- **`_try_interact()` is restored to its pre-Water-Hookup-plan behavior**
  exactly — fair distance only, grow-light override still applies
  (unaffected, untouched).
- **The grow-light-over-tray override is untouched in both places** —
  still applies to real `E` dispatch (via `_nearest_generic_interactable()`)
  AND to Focus Mode (via `focus_idx`), exactly as it did before this
  correction. Only the Water Hookup override moved.
- **The `"water_hookup"` group marker itself doesn't need to change** —
  it's just a duck-type tag; which code reads it is what changed.

---

## Verification checklist

1. Stand near a Water Hookup with a closer wall light, **without**
   holding Ctrl — press `E` — confirm it now interacts with whichever
   is genuinely closer (the light, most likely), not always the hookup.
   This is the regression you reported; confirms it's fixed.
2. Same scenario, **hold Ctrl** — confirm the Water Hookup is the one
   prompt that stays visible/highlighted, even though it's farther away.
3. Release Ctrl in that same scenario — confirm normal prompts return
   immediately and `E` still resolves to the closer object, not the hookup.
4. Grow-light-over-tray regression check, both with and without Ctrl —
   confirm unaffected by this change (should still always beat its tray
   in both cases, exactly as before).
5. Water Hookup with nothing else nearby, Ctrl held and released —
   confirm it's still the (only, obviously correct) target either way.

---

## Documentation updates

### `docs/systems/player/README.md`

Amend the "Water Hookup unconditional E-priority (Aug 2026)" Common-
edits entry from the prior plan — this supersedes it, don't leave both
describing different behavior. Replace the entry's text:

```markdown
old entry text (find and replace in place):
- **Water Hookup unconditional E-priority (Aug 2026,
  `WaterHookup.gd` — flagged: `scripts/world/water/`, not one of the
  three core files).** Mounted high on the wall, so it was almost always
  losing fair-distance comparison in `_nearest_generic_interactable()`
  against lower-mounted wall objects (lights, breaker boxes, etc.)
  physically closer to a player standing on the ground. Given a new
  `"water_hookup"` duck-type marker group (mirrors `"grow_light"`/
  `"farming_tray"`); `_nearest_generic_interactable()` now gives it
  unconditional top priority whenever one's in reach at all — unlike the
  narrow grow-light-over-tray override (which only beats one specific
  named rival), this is deliberately unscoped, since a Water Hookup has
  no single fixed competitor. Because both the real `E` dispatch and
  Focus Mode's highlight share this same function by design, a plain `E`
  press now also always resolves to a nearby hookup, not just Focus
  Mode's Ctrl-held highlight — deliberate, keeps the two from ever being
  able to disagree.

new entry text:
- **Water Hookup unconditional Focus Mode priority (Aug 2026,
  `WaterHookup.gd` — flagged: `scripts/world/water/`, not one of the
  three core files; corrected same session — see below).** Mounted high
  on the wall, so it's almost always farther than lower-mounted wall
  objects sharing the same wall and would rarely win on raw distance
  alone. Given a `"water_hookup"` duck-type marker group (mirrors
  `"grow_light"`/`"farming_tray"`). **Correction:** initially implemented
  inside `_nearest_generic_interactable()`, which at the time was shared
  by both real `E` dispatch and Focus Mode's target resolution — but
  Focus Mode had since been rewritten to compute its own
  `is_focus_target` independently (see `_update_prompt()`'s "Aug 2026 v2"
  comment) and no longer calls that function at all, so the override was
  silently affecting only plain `E` presses, never Focus Mode — the
  opposite of the intent. Moved to `_update_prompt()`'s `focus_idx`
  computation instead (mirrors the existing grow-light-over-tray swap
  already there), which is the thing that's actually gated behind
  `Input.is_key_pressed(KEY_CTRL)`. Plain `E` presses (`_try_interact()`)
  are back to fair-distance-only, unaffected by Water Hookup's presence.
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Water Hookup Priority Corrected to Focus-Mode-Only (Aug 2026)

## What changed this session
Corrected a bug in the prior "Water Hookup Unconditional E-Priority"
plan: it gave Water Hookup unconditional priority whenever in reach,
but implemented it inside `_nearest_generic_interactable()`, which
turned out to be reached only by real `E` dispatch (`_try_interact()`)
— Focus Mode had already been rewritten in a separate pass to compute
its own `is_focus_target` tag independently, no longer calling that
function at all. Net effect: the override was silently controlling
plain `E` presses (making a nearby Water Hookup always win, even
without Ctrl held) while having zero effect on Focus Mode itself — the
exact opposite of the intended scope.

Removed the override from `_nearest_generic_interactable()` (plain `E`
is back to fair-distance-only) and added the equivalent to
`_update_prompt()`'s `focus_idx` computation instead — the thing
`InteractPrompt.gd`'s Focus Mode filter actually reads, and which is
only ever consulted while `Ctrl` is held. Mirrors the existing
grow-light-over-tray swap already present in that same computation.

### Files modified
- `scripts/player/InteractionSystem.gd` — Water Hookup override moved
  from `_nearest_generic_interactable()` to `_update_prompt()`'s
  `focus_idx` computation.
- `docs/systems/player/README.md` — prior Common-edits entry corrected
  in place (not duplicated) to describe the current, correct behavior.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_WATER_HOOKUP_FOCUS_MODE_SCOPE_FIX_PLAN.md` for the full 5-item
checklist)
```
