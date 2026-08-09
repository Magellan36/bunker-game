# Cleaning: Prefer Light Storage Over Shelving for Light Items (Aug 2026)

**File:** `scripts/npc/NPC.gd`.

**Re-clone the repo fresh before starting.** Verify the anchor below
against the live file before editing — confirmed present and unchanged
from the last plan as of this writing.

---

## Context

Right now `find_cleaning_destination()` picks the single nearest
candidate across the whole `"shelving"` group with no regard for type —
so a fuel can could get routed to a farther-but-nearer-than-the-dresser
real Shelving object even when an End Table/Dresser also has room.
Brannon wants light items to prefer light storage specifically: try an
End Table/Dresser first, and only fall back to a general Shelving object
once every light-storage candidate is full (or none exist).

## Fix

**Anchor:** the entire existing `find_cleaning_destination()`:

```gdscript
## Nearest member of the matching destination group(s). For trash,
## returning null here (no receptacle exists) is expected and handled
## gracefully by CleaningActivity — it just abandons and sets the item
## back down.
func find_cleaning_destination(is_trash: bool, item: RigidBody3D = null) -> Node:
	var group_names: Array = ["trash_receptacle"] if is_trash \
		else ORGANIZE_DESTINATION_GROUPS.get(_classify_organizable_item(item), ["shelving"])
	var best: Node = null
	var best_d: float = INF
	for group_name: String in group_names:
		for candidate: Node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(candidate):
				continue
			if not is_trash and item != null and candidate.has_method("has_room_for") and not candidate.has_room_for(item):
				continue   ## skip a full/ineligible container — this check was the whole gap
			var d: float = NPCItemUser.flat_distance(global_position, (candidate as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = candidate
	return best
```

Replace with:

```gdscript
## Nearest member of the matching destination group(s). For trash,
## returning null here (no receptacle exists) is expected and handled
## gracefully by CleaningActivity — it just abandons and sets the item
## back down.
##
## Aug 2026 — light items now prefer a LightStorage (End Table/Dresser)
## over a general Shelving object, even when a nearer shelf has room.
## Two-pass search: try LightStorage-only first; only fall back to
## considering every candidate (Shelving included) once no LightStorage
## has room. Heavy items and trash are unaffected — LightStorage can
## never take a heavy item anyway (has_room_for()'s own inventory_item
## gate already blocks it), so a LightStorage-only pass would just be a
## wasted search for them, never chosen for either.
func find_cleaning_destination(is_trash: bool, item: RigidBody3D = null) -> Node:
	var group_names: Array = ["trash_receptacle"] if is_trash \
		else ORGANIZE_DESTINATION_GROUPS.get(_classify_organizable_item(item), ["shelving"])

	var prefer_light_storage: bool = not is_trash and item != null \
		and _classify_organizable_item(item) == "light"
	if prefer_light_storage:
		var light_pick: Node = _nearest_cleaning_destination(group_names, item, is_trash, true)
		if light_pick != null:
			return light_pick
	return _nearest_cleaning_destination(group_names, item, is_trash, false)

## Shared nearest-candidate search behind find_cleaning_destination().
## light_storage_only, when true, additionally requires the candidate be
## a LightStorage instance (End Table/Dresser) — the light-item
## storage-preference pass above; false searches every candidate in
## group_names as before (shelves included).
func _nearest_cleaning_destination(group_names: Array, item: RigidBody3D, is_trash: bool, light_storage_only: bool) -> Node:
	var best: Node = null
	var best_d: float = INF
	for group_name: String in group_names:
		for candidate: Node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(candidate):
				continue
			if light_storage_only and not (candidate is LightStorage):
				continue
			if not is_trash and item != null and candidate.has_method("has_room_for") and not candidate.has_room_for(item):
				continue   ## skip a full/ineligible container — this check was the whole gap
			var d: float = NPCItemUser.flat_distance(global_position, (candidate as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = candidate
	return best
```

Stop and report on anchor mismatch — no improvisation.

No other file needs to change — `has_viable_destination_for_category()`
(the "is there ANY storage for this category" check used for the
skip-hopeless-items logic and the specific unavailable-reason errors)
is deliberately left as a looser "is there room somewhere" check, not a
preference order — it only needs to answer yes/no, and this tweak is
purely about which specific destination gets *picked* once the answer
is yes.

## Testing

1. Place one End Table/Dresser and one real Shelving object, both with
   room, with the Shelving object noticeably CLOSER to a loose fuel can
   than the End Table/Dresser is. Ask an NPC to clean — confirm it walks
   past/ignores the closer shelf and delivers the can to the End
   Table/Dresser instead.
2. Fill that one End Table/Dresser to capacity, leave the Shelving
   object with room, repeat with a fresh fuel can — confirm it now goes
   to the Shelving object (correct fallback).
3. With two End Tables/Dressers, fill the nearer one, leave the farther
   one with room, plus a Shelving object closer than both — confirm the
   NPC still prefers the farther-but-viable End Table/Dresser over the
   nearer Shelving object.
4. Confirm heavy items (Test Crate, Can Case, Water Case) are
   unaffected — they should route to Shelving exactly as before, never
   attempting an End Table/Dresser pass at all.

## Documentation updates

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
81. With both an End Table/Dresser and a closer real shelf available,
    ask an NPC to clean a light item (e.g. fuel can) — confirm it
    prefers the End Table/Dresser over the closer shelf. Fill all
    light storage, repeat — confirm it falls back to the shelf.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Light Items Prefer Light Storage Over Shelving (Aug 2026)

- find_cleaning_destination() now does a two-pass search for "light"
  classified items: LightStorage (End Table/Dresser) only first, and
  only falls back to considering general Shelving objects once no
  LightStorage candidate has room. Heavy items and trash are unaffected.

Files touched: `scripts/npc/NPC.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
