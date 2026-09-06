# Inventory HUD redesign

The inventory remains a four-slot, light-item-only quick bar. This pass changes
presentation and feedback only; pickup, `G` storage, mouse-wheel selection,
heavy-item exclusion, and held-item ownership remain in `InteractionSystem` and
`InventoryManager`.

## Approved presentation

- Four compact 72 px slots remain bottom-centred.
- The selected slot gains a signal-blue outline, soft glow, and restrained
  three-pixel lift. Empty slots use a low-contrast dashed ring.
- Item names are not permanently visible. Storing or selecting an item opens a
  one-line identity drawer for one second, then slides and fades it away. The
  drawer matches its slot's exact width and automatically fits longer names.
- Water uses a circular fill arc. Its centre droplet communicates quality using
  the established clean/questionable/unsafe colours. The drawer intentionally
  contains only the item's name; state details remain encoded in the slot.
- Flashlights use four battery bars. At 25% or below, the final occupied bar
  pulses softly in red. This is state-driven and stops when charge changes.
- Finite-use items use green charge pips rather than `2/2` text. Bandages,
  antibiotics, splints, trauma kits, and food cans implement the same item-level
  HUD state contract.
- Liquid, battery, and charge indicators sit inside the preview surface with a
  consistent inset, keeping them clear of both the outer and inner borders.
- Preview SubViewports are allocated once, render only when content changes,
  use the shared premium preview lighting, and normalize models to their actual
  visible AABB.

## Notification ownership

`NotificationManager` is the sole player-facing notification route. Inventory,
storage, cooking, farming, building, wiring, and piping warnings are journaled
in the Bunker Log and use the same toast presentation. The retired inventory
warning label and standalone transient notice were removed. Inventory entries
have their own Bunker Log filter.

Generator, battery, and breaker world-space status banners were also removed;
their interaction prompts and dedicated inspectors remain authoritative. NPC
debug labels are intentionally unchanged.
