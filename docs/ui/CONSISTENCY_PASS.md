# UI consistency pass — September 2026

Approved scope: all 35 recommendations from the consistency audit. Baseline
`038ae2981179177a417118af46f2f8b6609250cf`. Work belongs on `testing`; `main`
remains the player-tested baseline until explicit promotion. No force pushes.

## Recoverable checkpoints

1. **Shared foundations**: authoritative palette, native control skin, motion
   preference/timings, interruptible fades, preview updates, bounded layout,
   controller ownership and range/scroll helpers. Device-family integration.
   Validation: Godot 4.7.2; isolated motion/layout contracts passed;
   device UI/owner contracts passed 2,396 checks over six resolutions.
2. **Screen-family integration**: bounded layouts across Build, Storage, Pause,
   Graphics, Confirmation, Zone Customization, Power, Research, Status and NPC;
   Build's approved 440 x 760 left rail; input-aware recurring hints; restrained
   interruptible tab/detail transitions; retained Shop cart rows with exact
   focus/scroll restoration; Reduced UI Motion in Graphics; and immediate logical
   close with a short visual exit that a reopen can cancel. Validation: the full
   Godot 4.7.2 UI screen-smoke set passes.
3. **Final verification and documentation**: shared presentation formatting,
   retired-notice cleanup, screen-family reference, 35-point traceability,
   automated integration coverage and explicit visual/input limits.

Shared presentation formatting now owns integer grouping, signed currency,
percentages, item-name fallbacks, charge/battery wording and water-quality
wording. It receives values only and never mutates gameplay state. The obsolete
`TransientNotice` has no executable callers and was removed; `NotificationManager`
remains the sole toast/history owner.

The implementation portion of the approved consistency pass is complete on
`testing`. Promotion to `main` remains a separate, explicit approval step.

## Post-pass polish

- Build Mode is an exclusive workspace: entering it logically closes other
  active UI surfaces through their own lifecycle, fades the pooled world
  interaction prompts, and suppresses new prompts until Build exits.
- Cursor ownership is reconciled centrally. Keyboard/mouse menus request a
  visible cursor; controller menus hide it; gameplay captures it when no menu
  remains. Build retains its deliberate in-world cursor during placement and
  requests the OS cursor only while its catalog or Shop needs it.
- Desktop-density tokens keep the approved type scale while tightening
  vertical button padding. Graphics, Power Load Order, Pause, Storage,
  confirmation, Research, NPC, Shop and ordinary device-inspector controls use
  the denser information-first rhythm; preview-led and medical layouts retain
  their specialized geometry.
- Scrollable content reserves a shared right-side gutter, keeping controls and
  text clear of the scrollbar in Graphics, Build, Storage, Power and ordinary
  device inspectors at all six tested viewport sizes.
- Build placement keeps its custom cursor, clears interaction prompts, and
  separates the persistent clock, compact SHOP shortcut, placement helper,
  toolbar and toast lane without changing the approved Build workflow.
- Storage omits redundant empty-slot and capacity-bar copy. Power and water
  inspectors use compact single-line status rows, uppercase allocation tiers,
  and consistent POWER ON / POWER OFF actions whose chrome reflects state.
- Build category buttons use one fixed symbol canvas, the object viewport owns
  the retired footer space, and every shared prompt renderer is dismissed by
  group while Build is open so no world prompt can be republished or frozen.
- Left-stick motion is blocked from UI focus globally while remaining available
  to player movement. D-pad and right stick own UI selection, and explicit
  neighbor maps keep Storage navigation aligned with its visible slot grid.
- Device footers retain one concise input line. Stored Water reuses the shared
  inspector-card treatment, while generator output uses the shared amber value
  treatment and preserves the divider above its power action.

## Controller and content-density follow-up

- Shared directional focus now prefers the visible row/column. Power Terminal
  regression checks cover Load Order → Zone Network, both shoulder buttons,
  and direct movement between a consumer's decrement/increment controls.
- Primary tabs in Power, Research, NPC, Status, Graphics and Shop participate
  in shared LB/RB cycling. Build chooses categories while Construct is open
  and tool modes while it is closed; Undo remains an explicit action.
- Scrollbars are explicitly included in focus discovery because Godot keeps
  them as internal children. They accept D-pad/right-stick scrolling and can
  be entered and left through spatial navigation. Native option popups retain
  their focus surface while shared navigation continues blocking left-stick
  focus and providing right-stick selection.
- Construct removes the redundant placement-state box. Category icons use a
  16 px canvas, 3 px text gap and compact shared button chrome. Actual category
  bounds are checked at all six target resolutions.
- Research removes its redundant station-state header box and uses a smaller
  shared icon well and close button, leaving more space for content.
- Storage and Inventory share ItemStateMeter drawing and ItemPresentation
  state extraction: circular liquid fill, quality-colored droplet, battery
  segments and charge dots. Storage retains exact quantities in its detail
  text, physical slot mapping and transfer ownership.
- Storage uses the inspector keyboard/controller footer. Esc/E closing is
  shared across in-game menus; Status uses Q/R for keyboard tab cycling.
  Build's existing closing/proximity rules remain unchanged.

Validation: Godot 4.7.2 isolated import and seven screen smokes; shared
consistency contracts; inventory meter parity; and device/owner contracts
across six resolutions. These are automated geometry/input/state checks,
not a claim of physical-controller or GPU appearance acceptance. The optional
C# editor bridge is excluded; existing font-cache/ObjectDB exit diagnostics
in supplemental screen fixtures remain separate from GDScript failures.

## Inspector framing follow-up

Stored Water and allocation controls reuse a full-width amber inspector card.
An explicit scrollbar lane in the outer margin keeps detail boxes aligned with
the status row at every tested resolution, including when scrolling is needed.
The remaining Storage Capacity card is removed; Contents and its item viewport
receive the freed space. Shared scrollbar thumbs use ivory in normal, hover
and pressed states. Generator backup copy now states the automatic-start rule
in plain language, and unregistered rated-load readings display `0 W`.

Godot 4.7.2 validation: 2,352 device/owner checks with no failures across all six
target resolutions, plus the Build/Storage/controller screen smoke.

## Research and power history follow-up

Research progress reads the owner's clock each frame, independently of the
slower material/tree refresh. Its retained smooth bar targets individual whole
percentages; research timing, material consumption and pause/resume stay with
ResearchStation. Tests exercise consecutive 1% updates without rebuilding the
bar or advancing the owner's clock.

Power history uses a fixed 60-second axis, continuous movement between samples,
a restrained load-area fill and endpoint, and eased scale changes with headroom
and hysteresis. Capacity dashes are six pixels with four-pixel gaps, independent
of sample density. Unchanged refreshes do not restart motion, recorded historical
values remain exact, and Reduced UI Motion suppresses interpolation/scrolling.
Power Terminal summaries use player-facing equipment counts and overload status;
solver node/edge/reachability counts are removed. Missing power readings show
`0 W`, including absent battery supply. Load-order rows retain their compact
layout and share the amber framing of inspector allocation controls.

Godot 4.7.2 targeted checks cover dash length/density, constant sample spacing,
inter-sample scrolling, unchanged-refresh stability, zero readings, player-facing
copy, and research's 1% updates. Visual/controller acceptance remains an in-game
review; headless checks do not substitute for GPU appearance review.

## Checkpoint commits

| Commit | Scope |
| --- | --- |
| `e084840117b486f2138d5da3b942932608b33bf7` | Shared consistency, motion, layout, focus and device-family foundations |
| `71e6ea77a69f8e61ae9d7e3b2374e10fbb8a1196` | Bounded screen layouts, Build rail dimensions and Reduced UI Motion setting |
| `adfdcf30be7e232c2266c96f1dd76dbfe82701e3` | Retained Shop cart rows with exact focus and scroll preservation |
| `5882d2a3354c9cef80364aa86e74f88c499f9b8b` | Input-aware hints, restrained transitions and interruptible screen lifecycle |
| `96e5b1a25b4ec5ca77dff293812d56a9f2ed7727` | Shared formatting and official-notification cleanup |
| `3b6fa18faf89d84dd29f85ff4197ef7ed410f5aa` | Build cursor, prompt dismissal and collision-free Build HUD lanes |
| `fc018493bb3e532a690a93e572321234f12868af` | Shared scrollbar gutter and category-icon sizing |
| `2b740d0f650bedc59b83bdcc1e0108d0e3baf860` | Compact Storage/device information and unified power-state presentation |
| `e87ed2f09bf61b661d3270140fcb993229fe59aa` | Fixed Build icon sizing, prompt ownership, inspector cards and controller navigation |

Every commit is a non-force descendant of the prior `testing` checkpoint.
`main` remains at the approved baseline until explicit promotion.

## Screen-family reference

| Family | Identity and behavior retained | Shared consistency applied |
| --- | --- | --- |
| World HUD | Compact always-on survival information over the world | Typography, formatting, focus-safe animation and shared icons |
| Device inspectors | Slender right rail; world visible; movement enabled; real-host walk-away close | Bounded docking, native controls, controller ownership and lifecycle |
| Build | 440 x 760 left catalog rail; one-click placement; catalog stays open | Storage-matched bounds, input-aware hints and retained selection |
| Storage | Right-middle in-world rail with physical slot mapping | Bounded layout, shared item presentation and controller scrolling |
| Shop | Distinct category/cart/checkout workspace | Retained cart rows, exact focus/scroll restoration and shared currency |
| System workspaces | Power, Research, Status, NPC and Zone keep their specialist layouts | Viewport bounds, newest-state transitions and consistent focus/selection |
| Menus and modals | Pause, Graphics and Confirmation keep their approved hierarchy | Bounded layout, reduced-motion control and interruptible close/reopen |
| Full-screen flow | Character creation remains full screen and visually distinct | Foundation tokens and controls only; no inspector proportions imposed |

## Approved 35-point traceability

1. Authoritative warm-charcoal, ivory, worn-brass and blue palette tokens.
2. Shared native-control styling foundation.
3. Shared typography roles.
4. Consistent keyboard/controller focus foundation.
5. Consistent selected-state foundation.
6. Shared icon registry path with replaceable placeholders tracked.
7. Interruptible UI fades.
8. Shared restrained motion timings.
9. Persisted reduced-motion preference foundation.
10. Accurate smooth progress bars with immediate newest targets.
11. Preview swaps do not restart when content is unchanged.
12. Shared bounded panel-layout helper.
13. Shared immediate-logical/short-visual lifecycle helper.
14. Smooth selectable scrollbar stepping.
15. Explicit controller-navigation ownership.
16. Controller range adjustment without ownership conflicts.
17. Real-host proximity close with safe reopen behavior.
18. Ordinary device-family integration without full-screen conversion.
19. Theme synchronization tooling.
20. Dedicated consistency regression contracts.
21. Six-resolution device-inspector/owner harness.
22. Bounded layouts for Build, Storage, Pause, Graphics, Confirmation, Zone,
    Power, Research, Status and NPC.
23. Build catalog locked to the approved 440 x 760 left-rail target.
24. Reduced UI Motion toggle placed in Graphics view-comfort settings.
25. Recurring footer hints switch between real keyboard/controller bindings.
26. Restrained, interruptible tab/detail transitions preserve useful scroll.
27. Shop quantity changes preserve the exact focused control and scroll value.
28. Shop cart rows update in place instead of being destroyed and rebuilt.
29. Logical state changes are immediate while short exits remain visual only.
30. Currency formatting is shared and presentation-only.
31. Grouped integer/percentage formatting is shared and presentation-only.
32. Item-name fallback and serialized item details are shared.
33. Charge/use and battery wording is shared without owning item state.
34. Water-quality wording is shared without owning water simulation state.
35. The caller-free `TransientNotice` is removed; `NotificationManager` remains
    the sole toast, stacking and history owner.

## Verification record

| Gate | Result |
| --- | --- |
| Godot 4.7.2 full editor import/registration | Exit 0; no GDScript parse or compile diagnostics |
| Shared consistency contracts | 0 failures |
| Screen-family smoke suite | 7/7 passed |
| Device inspector/owner contracts | 2,288 checks, 0 failures over six resolutions |
| Formatting-sensitive HUD, inventory, notification and utility smokes | 4/4 success markers; 0 GDScript script errors |
| Supplemental HUD, needs, motion, interaction, loading and generator-inspector smokes | Success markers; 0 assertion failures |
| UI placeholder provenance | Development placeholders are manifest-tracked; release mode intentionally remains blocking |

The tested resolutions are 1280 x 720, 1366 x 768, 1920 x 1080,
2560 x 1440, 3440 x 1440 and 3840 x 2160. The screen smoke runner uses an
isolated non-C# project so optional MCP/editor-bridge failures do not become UI
failures.

## Remaining acceptance limits

Automated headless coverage validates structure, geometry, state ownership,
focus, scroll, lifecycle and formatting. It does not substitute for GPU/editor
appearance review or physical-controller feel. Before promoting `testing`, do a
short Godot 4.7.2 editor pass at 16:9, ultrawide and 4K, plus keyboard/mouse and
controller navigation. Temporary placeholder art remains explicitly permitted
for development and must be replaced or release-approved separately.

## Locked contracts

- Keep the approved warm charcoal/ivory/worn brass/blue design and UI families.
- Ordinary device inspectors: right rail, no backdrop, live world movement,
  real host binding and walk-away close. Full-screen/specialist menus differ.
- Keep gameplay state, purchases, treatments, storage mappings and jobs with
  their current owners. No simulation/save schema changes.
- Build: one-click placement, catalog stays open, left rail matching Storage
  dimensions; virtual pointer remains the deliberate right-stick exception.
- Needs: approved original colors/look, midpoint icons, 45-degree rotation,
  balanced caps and directional depletion. Medical healing layers stay intact.
- Inventory: four light-item slots, original meter/pip meanings, name-only
  transient plates no wider than a tile. Fuel/container prompt meters deferred.
- Low-health vignette, cash transaction feedback and hold-progress complete.
  NPC debug labels preserved. No new asset replacement or gameplay design pass.
- Preview pools/prewarming stay intact. Animation must never delay state or
  replay on unchanged data, nor allow a stale exit to hide a reopened screen.

## Validation environment

The current project declares Godot **4.7**; 4.6 lacks the already-used
`Control.custom_maximum_size` property. Use 4.7.2 for this pass. Isolated
contracts use real UI sources with explicit simulation doubles; they do not
claim to validate the full game, GPU appearance, or physical controller feel.
