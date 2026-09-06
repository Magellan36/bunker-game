# HUD Status Icon Polish

## Scope

This is intentionally a light presentation pass, not a HUD redesign. It does
not change the needs gauge, badge positions, 50px footprint, stacking order,
effect duration, medical severity, healing progress, infection progress, or
tooltip contracts.

## Presentation

- Blank gray centers now fall back to semantic, code-rendered ivory symbols.
- The circular face uses the approved charcoal surface family with one quiet
  worn-brass keyline.
- Existing semantic ring colors remain the primary information channel.
- Ring under-edges improve separation against bright and dark bunker scenes.
- Imported icons supplied by future effects still take precedence over the
  automatic fallback symbol.

Medical fallback mapping:

| Effect identifier | Symbol |
| --- | --- |
| `bleeding` | Blood drop |
| `open_wound_*` | Bandage; infection symbol while its outer infection ring is active |
| `fractured_*`, `broken_*` | Broken bone |
| `burn_*` | Flame |
| Other medical condition | Medical cross |

Ordinary fallback mapping recognizes temperature/warmth, work/repair,
sleep/fatigue, and poison/sickness identifiers. Unknown effects use the general
status symbol instead of returning to a featureless placeholder.

## Restrained motion

- New badge: 160ms fade-and-settle plus a very soft blue arrival bloom.
- Medical severity, healing, and infection rings ease toward live values
  instead of stepping between simulation updates.
- Refreshed ordinary timers smoothly return to their renewed duration.
- When an effect disappears, remaining badges glide into their new slots.
- Active healing: a slow sheen travels only inside the existing blue healed
  portion of the medical ring.
- Critical unresolved medical condition: a low-opacity red breathing halo.
- Final 15% of a timed effect: its existing ring gains a slight amber pulse.
- Removed badge: 120ms fade-and-settle; gameplay state is removed immediately.

No particles, perpetual badge bobbing, layout motion, flashing text, or needs
gauge animation was added.

## Files

- `scripts/ui/hud/StatusEffectIcon.gd`
- `scripts/ui/hud/StatusEffectsContainer.gd`
- `scripts/ui/common/BunkerSymbolTexture.gd`
