# Quiet UI audit — every player-facing UI (2026-09-26)

Baseline for `plans/ui-quiet-redesign-plan.md` (Pass column = the five-pass plan). Method: every `.gd` under
`scripts/ui/` plus world scripts that host UI; which ones are actually
instantiated; how each is built; **live captures** of each surface in the
running game (Godot 4.7.2, 1080p; MainWorld with spawned devices and an NPC);
and a baseline run of `tools/tests/quiet_ui_lint.gd` against screens that can
be built standalone. Target language: `docs/ui/QUIET_DESIGN_SYSTEM.md`.

## Already in the quiet language

Rows marked ✅ below were migrated in Pass 1 (2026-09-26).

| Surface | Files | Notes |
|---|---|---|
| Main menu | `scripts/ui/main_menu/*`, `scenes/ui/main_menu/MainMenu.tscn` | Reference. Lint registered (hero-blue exception). |
| Graphics settings | `scripts/ui/menus/GraphicsSettingsPanel.gd` | Reference workspace. Lint registered. Opened from main menu and pause. |

## Inventory (live code only)

Built: **N** = native Controls/containers · **D** = hand-drawn `_draw()` ·
**N+D** = mixed. Lint = baseline violations (– = not standalone-lintable;
needs live capture review).

| # | Surface | Live files (lines) | Built | Archetype | What the capture shows | Prior contract doc | Lint | Pass |
|---|---|---|---|---|---|---|---|---|
| 1 | ✅ Confirm dialog | `common/ConfirmDialogUI.gd` (271) | N | Dialog | Icon well, bordered/blue buttons | SHARED_UTILITY_UI_REDESIGN | 9 | 1 |
| 2 | ✅ Notification toasts | `notifications/NotificationManager.gd` (444) | D | HUD toast | Icon box + domain stripe + severity eyebrow; **covers panel footers** | NOTIFICATION_PAUSE_OVERHAUL | – | 1 |
| 3 | ✅ Key hints | `common/BunkerUIComponents.key_hint`, `BunkerInputHint.gd` | N | Shared | Brass-bordered keycaps (keep, quieter) | CONSISTENCY_PASS | – | 1 |
| 4 | ✅ Tooltips, popups, scrollbars | `common/BunkerControlTheme.gd`, `ControllerUINavigation._prepare_scrollbars` | N | Shared | Bright ivory 16 px scrollbars everywhere except Settings | CONSISTENCY_PASS | – | 1 |
| 5 | ✅ Pause menu + save/load slots | `menus/PauseMenuUI.gd` (304), `notifications/NotificationHistoryUI.gd` (230) | N | Workspace | Filled-blue icon buttons, blue top bar, filter pills, striped log cards, red Exit bar | NOTIFICATION_PAUSE_OVERHAUL | 44 | 2 |
| 6 | ✅ Loading screen | `loading/LoadingScreen.gd` (329), `LoadingBackdropArt.gd`, `LoadingIndicator.gd` | N+D | Moment | Brass bar ornaments, blue code-drawn logo, bordered tip card | LOADING_SCREEN_REDESIGN | 8 | 2 |
| 7 | ✅ Sleep overlay | `menus/SleepOverlay.gd` (126) | N | Moment | Own zzz fade | – | – | 2 |
| 8 | ✅ Game over | `menus/GameOverUI.gd` (102) | N | Moment | Minimal; **loads slot 0 (invalid, slots are 1–3)** | – | – | 2 |
| 9 | ✅ Needs gauge | `hud/NeedsGauge.gd` (289) | D | HUD | Rainbow concentric rings + glyphs; **overlaps build catalog** | NEEDS_GAUGE_REDESIGN | – | 3 |
| 10 | ✅ Clock + cash | `hud/HUD.gd` (247) | N | HUD | Boxed plates, clock pictogram | HUD_TIME_CASH_POLISH | 2 | 3 |
| 11 | ✅ Hotbar | `inventory/InventoryHUD.gd` (341), `common/ItemPreviewKit.gd`, `ItemStateMeter.gd` | D | HUD | Bordered 72 px slots, blue glow selection | INVENTORY_HUD_REDESIGN | – | 3 |
| 12 | ✅ Status effects | `hud/StatusEffectIcon.gd` (361), `StatusEffectsContainer.gd` | D | HUD | Coloured rings + code icons | HUD_STATUS_ICON_POLISH | – | 3 |
| 13 | ✅ Interaction prompts, hold/job glyphs | `hud/InteractPrompt.gd` (848), `InteractionPromptChrome.gd`, `HoldProgressIcon.gd`, `JobProgressGlyph.gd` | N+D | HUD (world-space) | Translucent brass-edged chips; **"Open Research Station" shown twice** | INTERACTION_PROMPT_POLISH | – | 3 |
| 14 | ✅ Device inspector shell | `common/BunkerDeviceInspector.gd`, `scenes/ui/common/DeviceInspectPanel.tscn`, `BunkerInspectorWidgets.gd`, `BunkerInspectorLayout.gd`, `BunkerPriorityControl.gd`, `UIProximityClose.gd` | N | Docked | Icon header, bordered cards, filled blue actions | plans/ui-redesign-device-pass | 3 | 3 |
| 15 | ✅ Generator | `power/GeneratorInspectUI.gd`, `scenes/ui/power/GeneratorInspectPanel.tscn` | N | Docked | Same family | ui-redesign-generator-pass | 9 | 3 |
| 16 | ✅ Battery · breaker · consumer priority | `power/BatteryInspectUI.gd`, `BreakerInspectUI.gd`, `PowerPriorityUI.gd` | N | Docked | Captured battery/breaker: blue fills, bordered rows | ui-redesign-device-pass | via 14 | 3 |
| 17 | ✅ Water dispenser · hookup/sink/purifier | `water/WaterDispenserUI.gd`, `WaterInfoUI.gd` | N | Docked | Same family | ui-redesign-device-pass | via 14 | 3 |
| 18 | ✅ Farming tray | `farming/FarmingTrayUI.gd` | N | Docked | Same family | ui-redesign-device-pass | via 14 | 3 |
| 19 | ✅ Trash bag hover panel | `common/TrashBagInfoPanel.gd` (293) | N | Docked (ambient) | Bordered, icons | SHARED_UTILITY_UI_REDESIGN | – | 3 |
| 20 | ✅ Power terminal | `power/PowerTerminalModernUI.gd` (1774), `PowerTerminalLoadGraph.gd` (215) | N+D | Workspace | Icon tabs (filled blue), green GRID ONLINE pill, icon-headed bordered cards, blue P1 chips | POWER_TERMINAL_REDESIGN | – | 4 |
| 21 | ✅ Zone customize | `power/ZoneCustomizeModernUI.gd` (478) | N | Dialog | Swatch picker | ZONE_CUSTOMIZATION_REDESIGN | – | 4 |
| 22 | ✅ Storage | `inventory/StorageUI.gd` (454), `common/BunkerItemCard.gd`, `ItemPresentation.gd`, `PreviewPresentation.gd` | N | Docked | Bordered item cards, icons | BUILD_SHOP_STORAGE_REHAUL | – | 3 |
| 23 | ✅ Status (player/health/NPCs/inventory) | `medical/StatusScreenUI.gd` (1795), `npc/NPCPortraitViewport.gd` | N | Workspace | Icon tabs, colour stat bars, giant icon cards, STABLE pill | STATUS_SCREEN_REDESIGN | – | 4 |
| 24 | ✅ NPC talk / resident profile | `npc/NPCTalkMenuUI.gd` (1463), `NPCRelationshipMeter.gd`, `NPCPortraitViewport.gd`; NPC `Label3D` overhead labels | N | Workspace | Icon tabs, ON DUTY/NEUTRAL pills, rainbow need bars, filled "Talk" button | NPC_MENU_REDESIGN | – | 4 |
| 25 | ✅ Research station | `research/ResearchStationModernUI.gd` (1055), `ResearchPathCanvas.gd` | N+D | Workspace | Icon tabs, icon material cards, node graph with icons, loud scrollbar | RESEARCH_STATION_REDESIGN | – | 4 |
| 26 | ✅ Build mode (HUD, toolbar, catalog, cursor) | `build/BuildModeHUD.gd` (2077, heavy `_draw`), `BuildWorkspace.gd` (415), `BuildCatalogPanel.gd` (301), `BuildCatalogCard.gd`, `BuildCursor.gd` | N+D | Tool overlay | **Blue frame around the whole screen**, icon chips, blue price chips, boxed icon toolbar; **blank Half/Quarter-wall previews** | BUILD_SHOP_STORAGE_REHAUL | – | 5 |
| 27 | ✅ Supply shop | `build/ShopPanel.gd` (783), `ShopProductCard.gd`, `ShopCart.gd` | N | Workspace | Department icons, product cards, cart | BUILD_SHOP_STORAGE_REHAUL | – | 5 |
| 28 | ✅ Character creation | `scenes/ui/character_creation/*.tscn`, `character_creation/*.gd`, `BunkerRedesignTheme.tres` | N | Moment | Still "BUNKER"; **Godot default font, not Iosevka**; tracked AI placeholder SVG icons; **"Randomise" clipped at 1080p** | docs/systems/character-creation | 25 | 2 |
| 29 | ✅ Admin (F7) | `menus/AdminMenu.gd` (1219) | D | Dev | Hand-drawn triangles, red X box | – | – | 5 |
| 30 | ✅ Debug overlay | `debug/DebugOverlay.gd` (313) | D | Dev | Dev readouts | – | – | 5 |

### Dead code (not instantiated anywhere)

| File | Lines | Replaced by |
|---|---|---|
| `scripts/ui/power/PowerTerminalUI.gd` | 1241 | `PowerTerminalModernUI.gd` |
| `scripts/ui/power/ZoneCustomizeUI.gd` | 252 | `ZoneCustomizeModernUI.gd` (only the dead terminal + a comment reference it) |
| `scripts/ui/research/ResearchStationUI.gd` | 930 | `ResearchStationModernUI.gd` |

After the in-game passes, `UIKit.gd`'s hand-drawn helpers, domain themes and
`BunkerRedesignTheme.tres` lose most consumers; retire what nothing uses.

## Cross-cutting findings

1. **One visual family, too loud.** Every in-game workspace shares the
   "redesign v1" vocabulary: icon + eyebrow + title header, filled-blue
   selected tabs with ivory outlines, pills for state, bordered icon cards for
   plain information, per-stat rainbow meters. It is consistent, which makes
   the migration systematic: most changes are in shared helpers
   (`BunkerPanelStyle`, `BunkerUIComponents`, `BunkerInspectorWidgets`).
2. **Layering bugs.** Toasts sit on top of workspace footers (Pause,
   Terminal, NPC). The needs gauge overlaps the build catalog.
3. **Scrollbars** are bright ivory 16 px bars via the shared nav skin.
4. **Icons everywhere** come from `BunkerSymbolTexture` (code-drawn,
   AI-authored geometry) and tracked AI placeholder SVGs. Removing most of them
   is both the design goal and a Steam-disclosure win.
5. **Typography drift.** Character creation renders in Godot's default font.
6. **Functional bugs seen** (fix in the owning pass): duplicate interaction
   prompt, blank catalog previews, GameOver slot 0, clipped Randomise.

## Lint limitations

The tree lint sees native Controls only. `_draw()` surfaces (needs gauge,
hotbar, status effects, toasts, build HUD, admin) are reviewed from live
captures. Passes that replace `_draw()` with native controls bring those
surfaces under lint.


## Out of scope (recorded 2026-09-27)

World-space build feedback — ghost previews, hover highlight, connection
dots, the room/excavation outline, wire/pipe cost `Label3D`s — keeps its
established colours. These are gameplay readability cues in the 3D world
(valid/invalid, connectable), not UI chrome; recolouring them is a gameplay
decision for Brannon, not part of the quiet UI pass.
