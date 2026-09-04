# Build, Shop, and Storage UI Rehaul

Implemented on branch `ui/build-shop-storage-pass` in September 2026.

## Design contract

- In-world inspectors are compact desktop panels over the live game. Storage
  is a 460 px, vertically centered left rail at 1920×1080; it has no
  full-screen dim layer.
- Build catalog is a 440 px left rail. Selecting an item immediately starts
  placement, collapses the catalog, and leaves a small placement summary plus
  the full icon-led build toolbar and Place/Rotate/Cancel/Grid helper strip.
- Supply shop is a separate, centered desktop workspace capped at 1560×900.
  It uses icon-led categories, large preview wells, integrated Add-to-cart
  actions, persistent quantity controls, and a structured checkout summary.
- Shared palette and Control styling live in
  `scripts/ui/common/BunkerPanelStyle.gd`. The theme is charcoal/ivory with a
  worn dark-brass structural edge and project-blue focus/action color.
- These shapes are native Godot Controls and StyleBoxes. No new generated
  image asset is required by this pass.

## Stable gameplay boundaries

### Storage

`StorageUI.gd` still consumes the existing four-method container contract:

1. `get_ui_config()`
2. `get_slot_display(data_index)`
3. `take_for_carry(data_index, interaction_system)`
4. `take_for_inventory(data_index, inventory)`

The world object remains the sole owner of items. `display_order` is applied
only when translating a visual card index back to the physical data index.
This preserves shelving tier order, light-storage identity order, basket
behavior, stacks, signals, and physical item placement.

Adding an item to inventory deliberately leaves the panel open. Primary
carry/drop keeps the container's existing `closes_on_action` behavior.
Selections are checked against the shown item's instance ID immediately before
transfer, so an externally changed slot cannot act on a stale object.

### Build

`BuildWorkspace.gd` is presentation only. Its buttons call the existing
`BuildModeHUD` signals and therefore continue through `BuildModeController` for
construction, deconstruction, moving, duplication, undo, wiring, plumbing,
rotation, validation, spending, and placement. Tile IDs and prices still come
from the established `BuildModeHUD.CATEGORIES` dictionaries.

### Shop

The shop uses the established `FarmingShopHelper.SHOP_ITEM_INFO` IDs, prices,
types, and scene paths. `ShopCart.gd` is session-local presentation state.
`FarmingShopHelper.checkout_order()` is the authoritative transaction:

- validates every line and the 99-item order bound;
- checks the complete order total before mutation;
- finds clear delivery positions near the player;
- instantiates every item detached from the scene tree;
- charges MainWorld once only after preparation succeeds;
- adds the prepared items to the existing world parent.

Failures do not clear the cart or charge cash.

## Preview lifecycle

The existing persistent Construct and Shop SubViewport pools are retained.
They are created with the HUD, populated in staggered chunks while the loading
screen remains above MainWorld, and reused across open/close cycles. This
removes the post-load preview construction hitch and keeps the first catalog
open instant. Storage similarly grows a persistent pool to the largest
container opened and refreshes only when an item signature changes.

`PreviewPresentation.gd` adds a neutral environment and warm/cool studio lights
to the existing isolated preview worlds. Preview textures are 192 px and use
`UPDATE_ONCE`, so the polish does not add a per-frame render pass for every
card. Actual item geometry remains the source of truth.

`UIProximityClose.gd` supports both live-node and fixed-position bindings.
Every in-world inspector therefore keeps the established walk-away-to-close
behavior, including the shared power-priority inspector used by wall lights.

## Controller and keyboard contract

`ControllerUINavigation.gd` owns the shared behavior:

- D-pad and right stick navigate controls.
- A activates the focused control; B closes the topmost closable UI.
- A focused Slider is adjusted directionally.
- ScrollContainer scrollbars become focusable only when scrolling is useful.
- With a scrollbar focused, Up/Down (or Left/Right for a horizontal bar)
  changes its value. Mouse wheel/click/drag and keyboard arrows remain native.
- Left stick remains world movement in ordinary in-world inspectors. Existing
  full-screen menus may explicitly opt it into navigation.
- While any controller navigation root is visible, player facing and the build
  cursor do not also consume the right stick.

Character creation now uses LB/RB to orbit its model preview and LT/RT to zoom,
freeing the right stick for the same navigation role as every other screen.

## Tuning points

- Palette, radii, default button treatments: `BunkerPanelStyle.gd`
- Storage width/height rules: `StorageUI._layout()`
- Build/shop dimensions: `BuildWorkspace._layout()`
- Build subcategories: `BuildCatalogPanel._groups()`
- Shop categories/subcategories: `ShopPanel.CATEGORIES` and `SUBCATEGORIES`
- Preview resolution/lighting: `BuildModeHUD.SUB_VP_SIZE` and
  `PreviewPresentation.configure()`
- Stick deadzone/repeat and scrollbar step: `ControllerUINavigation.gd`

## Verification

Run:

```sh
godot --headless --path . --script res://tools/tests/ui_rehaul_smoke.gd
```

The smoke test loads all touched scripts, instantiates the build/shop/storage
controls, checks desktop geometry and separate workflows, validates cart
quantity/total bounds, confirms storage display-order delegation and transfer
lifecycle, verifies walk-away closure, and verifies UI right-stick ownership
plus focusable-scrollbar adjustment.
