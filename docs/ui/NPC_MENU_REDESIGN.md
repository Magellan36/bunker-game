# Resident Profile UI

The NPC interaction menu is a resident relationship surface, not a generic
device inspector. Its visual anchor is the resident's actual animated model;
identity and live needs remain visible while the player talks, issues requests,
checks health, or reviews history.

## Layout contract

- Maximum desktop shell: `1420 × 820`, centered with safe 1080p margins.
- The bunker remains visible through a restrained backdrop.
- The left column persists across every tab: animated resident view,
  player-facing relationship scale, and personality words.
- The right column always retains Health, Energy, Food, Water, and Mood.
- The profile always opens on Overview. No tab opens to a blank page.
- Tabs are Overview, Talk, Requests, Health, and Activity Log.

## Preserved gameplay contracts

- `NPC.get_dialogue_line()` remains the normal Talk action.
- Ask About continues to use `get_relationship_dialogue_line()` for the player
  and every result from `get_other_npc_topics()`.
- Quick requests still dispatch `EatActivity`, `DrinkActivity`, and
  `CommandRestActivity`.
- All six prior work orders and their specialized unavailable-reason messages
  are retained.
- Health reads each resident's own `NPCMedical` component and reuses
  `get_status_detail_text()` rather than maintaining a second medical model.
- Activity Log remains newest-first, live-updates hostile entries, and keeps
  the captured in-game timestamp as its tooltip.
- `UIProximityClose` follows the live NPC. Walking away closes the profile.
- Left-stick movement stays available. D-pad and right stick navigate;
  controller shoulder buttons switch tabs.

## Animated resident view

`NPCPortraitViewport.gd` instantiates the existing `AdventurerModel.tscn` in
an isolated SubViewport. It copies the gender already resolved on the live NPC
and therefore does not reroll the resident on inspection. The existing idle
animation, warm key light, cool rim light, and small presentation plinth run
only while the profile is open.

The world NPC is never reparented, paused, hidden, or otherwise used as the
preview object. Future appearance customization should extend the same
resolved-appearance copy step rather than introduce a separate portrait asset.

The viewport disables MSAA, honors the configured 3D render scale, and stops
both rendering and model processing on close.

## Asset provenance

The panel shell, relationship meter, state colors, progress bars, and added
symbols are rendered from Godot Controls or drawing primitives. No new bitmap
or generated UI assets are introduced by this implementation.
