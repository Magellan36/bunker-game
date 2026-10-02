# Hand-off: move items between slots from the shelf UI

**For:** the UI session ("Game main menu with apocalyptic scene"), owner of
`scripts/ui/**` including `scripts/ui/inventory/StorageUI.gd`.
**From:** NPC system polish review session, 2026-10-02, at Brannon's request.
That session wasn't running when this was written, so this note is the
hand-off. Brannon asked for it to go to you.

## What Brannon wants

When the player presses F on a shelf, the item still goes into the first
free slot (no change there). The shelf UI (`StorageUI`, opened with E on a
shelf) gets a new option to **move** a stored item to another slot of the
same shelf:

- **In the UI:** the item visibly moves from its slot to the chosen slot.
- **On the shelf in the world:** the item physically moves too, in three
  steps so it never clips through the posts or the items beside it:
  1. it slides **outward** (toward the shelf front, along the shelf's facing),
  2. it travels across to the target slot's position, still out in front,
  3. it slides back **inward** into the slot.

## Notes from the NPC side

- **Where it physically lives:** slot placement and its tween are in
  `scripts/world/furniture/Shelving.gd` (`_place_item_in_slot()`,
  `_stack_offset()`, `_stack_rotation()`, the `slots` array of stacks,
  `_slot_nodes` markers). A move API there would likely be something like
  `move_slot(from_idx, to_idx) -> bool`. It would update `slots`, animate
  out → across → in, and emit `item_retrieved` / `item_placed` (or a new
  signal). `get_storage_save_data()` reads `slots`, so saves follow
  automatically. No session owns world furniture in the ownership table,
  so it's yours to change for this.
- **Valid targets:** an empty slot, or a partial stack of the same type
  with room. Use the shelf's own rules (`_get_item_type()`,
  `_get_stack_limit()`). Moving the whole stack of a slot (for example 6
  cans) is probably the nicer default. Your call.
- **Tell residents it was you:** stamp every moved item with
  `item.set_meta("player_placed_h", NPCClock.now())`. Residents re-organize
  storage now (see below), and they leave anything the player placed or
  moved alone for one game day (Brannon's rule). The NPC session stamps the
  same meta on F-placement in `Shelving._try_place_item()` and
  `LightStorage._try_store_held()`.
- **Don't move what a resident is about to take:**
  `NPCItemUser.is_claimed_by_anyone(item)` is true while a resident has
  claimed an item (fetching it to eat, cook or carry). Refuse the move, or
  grey it out, for those.
- **Shelves only.** Dressers and end tables (`LightStorage`) store items
  hidden and have no slot geometry, so moving within them means nothing.
- **Shared file:** the NPC session adds to `Shelving.gd` in the same pass:
  an optional `slot` argument on `npc_try_place_item()`, a
  `can_place_in_slot()` check, and the player-placed stamp. Please keep
  those as they are, or message the NPC session if you need to change them.

## Context: what residents do with storage now (NPC session)

Residents put things away with some sense of where they belong:
- small things (medicine, filters, seeds) go in drawers;
- bulk stores (food and water cases, cans, bottles) are kept together,
  each type in its own rows, leaning toward the kitchen;
- fresh produce, pots and dishes go by the kitchen;
- seeds, soil and fertilizer go by the garden;
- fuel goes by the generator;
- heavy things go on low tiers, small things up high.

As a low-priority job (frequent during preparation), they also move a
stored item when a clearly better spot opens up. They never touch
anything the player placed in the last game day.
