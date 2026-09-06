# Status Screen Redesign

The Tab screen is the player's general status workspace. It is not a large
version of the medical tooltip and it does not replace the ambient HUD.

## Approved presentation

- Centered desktop panel, bounded to 1420 × 820 at 1080p.
- Warm charcoal surfaces, worn brass dividers, ivory hierarchy, functional
  bunker blue selection, and state colors only where they convey meaning.
- Header: player/status identity, concise whole-player state, and close.
- Persistent summary: Health, Food, Water, Stamina, Sleep, including reduced
  cap labels.
- Four tabs: Overview, Health, Needs, Inventory.
- Overview uses three large actionable cards rather than duplicating every
  detail.
- Health uses a body-region column, condition-card column, and selected
  condition/treatment column.
- Needs uses detailed value/cap cards and exposes the existing cap-reason
  sentence.
- Inventory inspects the established four quick slots with persistent 3D
  preview viewports and `ItemPresentation` details.

All icons in this implementation are drawn by `BunkerSymbolTexture.gd` from
Godot primitives. No bitmap UI art is added.

## Gameplay contracts preserved

- The screen is non-modal. World simulation continues and left-stick player
  movement remains available.
- `PlayerMedical`, `PlayerStats`, `InventoryManager`, and the player continue
  to own their respective values.
- Health text and colors reuse `PlayerMedical` public presentation helpers.
- Bandage → Bleeding, Antibiotics → Open Wound, Splint → Fractured/Broken.
- Treatment delegates to each item's existing `apply_to_target()` function.
- Treatment searches only the held item and four carried slots. It does not
  pull items remotely from room storage.
- Trauma Kit remains a whole-body emergency action and is not misrepresented
  as an individual-condition treatment.
- Inventory is inspect-only; opening Status never changes the held slot.

## Input and performance

- Mouse clicks and normal keyboard focus work throughout.
- Q/E and LB/RB cycle tabs.
- D-pad and right stick duplicate directional navigation.
- Left stick remains player movement.
- A/Enter selects; B/View/Tab/Escape closes.
- The workspace and its four preview viewports are created during MainWorld
  startup, behind the loading presentation.
- A 0.25-second refresh updates existing controls. Condition cards rebuild
  only when the condition set on the selected body region changes.
