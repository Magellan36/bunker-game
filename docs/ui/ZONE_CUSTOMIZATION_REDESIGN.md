# Zone Customization Redesign

## Visual contract

Zone Customization is a compact companion to the approved Power Terminal—not a
second dashboard. It uses the same native Godot presentation vocabulary:
charcoal surfaces, ivory hierarchy, worn dark-brass borders, bunker-blue focus,
and green live-state accents. It appears as a centered secondary layer above the
terminal and keeps the underlying power workspace visibly contextual.

Rename mode provides a live zone-identity preview, an 18-character native text
field, character count, clear blank-name behavior, and equal Cancel/Apply
actions. Color mode provides the established sixteen colors as large 4 × 4
controller-friendly swatches, explicit current-color feedback, named tooltips,
and a reminder that selection applies immediately.

## Preserved behavior

- `open_rename(zone_key, current_name)` retains the existing signature.
- Enter or Apply emits `name_changed(zone_key, name)` and closes the popup.
- A blank name still clears the override and restores automatic zone naming.
- `open_color(zone_key, current_display_color)` retains the existing signature.
- Selecting a swatch still immediately emits `color_changed(zone_key, color)`
  and closes the popup.
- The same `DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES` palette remains
  authoritative; no colors or persistence rules were changed.
- The reusable popup remains alive between uses.
- D-pad/right stick navigate, A selects, B/Escape cancels, and the left stick
  remains available for player movement.
- Closing or walking away from the parent Power Terminal also closes this
  companion, preventing an orphaned customization window.

The earlier `ZoneCustomizeUI.gd` remains untouched as a fallback reference.
`PowerTerminalModernUI.gd` now loads `ZoneCustomizeModernUI.gd`.
