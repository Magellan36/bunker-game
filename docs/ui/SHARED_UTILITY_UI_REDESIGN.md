# Shared Utility UI Redesign

This pass brings the game's repeated confirmation surface and ambient trash-item context card into the approved 2026 bunker UI family. Both are built entirely from Godot `Control` nodes and `BunkerSymbolTexture` primitives.

## Confirmation dialog

`scripts/ui/common/ConfirmDialogUI.gd` is the sole confirmation component. It preserves the existing `confirmed`, `cancelled`, `open()`, `close()`, and `is_open()` contracts while adding optional labels, semantic tone, and symbol arguments.

| Caller | Tone | Confirm action | Safe action |
|---|---|---|---|
| Bunker excavation | Purchase | Excavate · $1,500 | Cancel |
| Lower-quality purifier filter | Warning | Replace filter | Keep current |
| Rendering-driver restart | Warning | Restart now | Not now |
| Exit to desktop | Danger | Exit game | Stay here |

The safe action receives initial keyboard/controller focus. D-pad and right stick navigate the real buttons, A/Enter activates, and B/Escape cancels. Focus and mouse mode are restored to the underlying UI on close.

The shell is sized once immediately and again after Godot's first container
layout pass, then clamped to the visible viewport. This prevents the transient
first-open overflow previously shared by storage, build, and shop panels.
Message-less confirmations use a compact height; bunker excavation deliberately
omits the redundant “excavate the selected rock tile” explanation.

## Trash-item context card

`scripts/ui/common/TrashBagInfoPanel.gd` remains proximity-driven, non-modal, and input-transparent. The redesign adds:

- bounded four-row presentation so large bags never become oversized;
- a clear nearby/held state and separate item-count badge;
- human-readable fill, quality, fuel, battery, use, serving, and material data;
- context-sensitive procedural item symbols;
- automatic refresh when a nearby bag's contents change;
- world anchoring above the bag with viewport-edge clamping.

The existing TrashBag record schema, pickup behavior, scan radius, and `MainWorld` setup connection are unchanged.
