# UI redesign — first implementation pass

## Decision

Character creation is the isolated first implementation of the approved visual
system. It establishes code-native tokens, component proportions, responsive
behavior and controller focus without prematurely restyling the rest of the
project.

The redesign anchor is the approved device-panel direction: warm lived-in
survival, large robust controls, clear wording, poppy functional icons, readable
status colour, restrained project blue, darker worn brass, and warm ivory text.
The interface should feel maintained and inhabited—not sleek sci-fi glass, not a
sepia military cliché, and not a collection of unrelated AI-generated widgets.

## First-pass scope

- Rebuild character creation with native Godot containers and controls.
- Preserve its actual Adventurer preview and existing gender data flow.
- Add an opt-in theme; do not change project-wide UI styling.
- Support desktop keyboard/mouse and controller.
- Add local responsive metrics and scrolling.
- Track every temporary AI-authored icon and make it release-blocking.
- Add automated structural, input and multi-resolution regression checks.

Not in this pass: shared inspector panels, build mode, shop, interaction prompts,
loading screen, or wider character options. Those remain subsequent migrations
based on the same anchor.

## Approved token baseline

| Token | Value | Intent |
|---|---:|---|
| Canvas | `#101717` | Warm near-black bunker backdrop |
| Panel | `#181D1D` | Solid charcoal surface |
| Neutral control | `#202524` | Robust inactive button |
| Hover | `#29383D` | Blue-charcoal response |
| Selected | `#263F50` | Clear project-blue selection surface |
| Selected edge | `#66BFFF` | Poppy state signal |
| Primary | `#294B64` | Blue completion action |
| Worn brass | `#88734E` | Structure and dividers, used sparingly |
| Ivory | `#F0E4C7` | Warm primary text |
| Focus | `#F4E6BF` | High-contrast controller/keyboard ring |

Baseline radii are 12 px for panels and 8 px for buttons at 1920×1080.
Focus uses a 3 px outline expanded by 4 px so it remains separate from selected
state. Motion should later use short 100–180 ms response transitions; this first
pass relies on native state changes and does not add animation infrastructure.

## Component rules established here

1. Prefer one strong title, one short instruction and direct action labels.
2. A selected state must not rely on colour alone: fill, border and icon all
   change together.
3. Reserve the trailing-icon area in button content margins so text never sits
   beneath selection or arrow artwork.
4. Keep primary progression separate from option scrolling.
5. Controller focus and mouse hover are distinct states; focus remains obvious
   on selected and unselected controls.
6. Layout belongs to containers. Scripted sizing is limited to token scaling,
   safe outer width and declared minimum targets.
7. Status colours communicate operation and resources. Brass communicates
   structure; it is not the default highlight colour.

## Artwork policy

The final game contains zero AI-authored artwork. Development placeholders are
permitted only when their filename, embedded metadata/comment and manifest entry
identify them unambiguously. `assets/ui/placeholders/redesign/manifest.json` is
the source of truth and `tools/tests/check_ui_placeholders.py --release` is the
release gate.

Later inspector passes should retain the approved accompanying icons for
Running, Grid online and Stored water/water fill, but those assets are not part
of this character-creation change.

## Next implementation sequence

1. Review character creation visually in the target Godot 4.7/.NET project.
2. Tune typography only after the intended final/licensed font is confirmed.
3. Migrate one representative inspector panel and extract genuinely shared
   primitives from the two proven screens.
4. Migrate water and farm-tray panels as a coherent family.
5. Build mode and the new category/subcategory/cart shop are a separate workflow
   pass, not a skin over the current toolbar.
6. Revisit loading, interaction prompts and other menus after the shared
   component library has real consumers.
