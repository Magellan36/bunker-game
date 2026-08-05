# Plan: NPC Meter Colors (Match Player HUD Palette)

**Owner of this plan:** UI Claude instance (HUD/menus)
**Scope:** `scripts/ui/npc/NPCTalkMenuUI.gd` only — confirmed via repo
search this is the only place any of the 5 NPC stats (Health/Energy/
Hunger/Thirst/Mood) are rendered as a meter/bar anywhere in the project.

---

## 1. What's there today

The NEEDS section of the NPC talk panel draws all 5 stats as identical
bars that currently **change color based on the current value** —
`theme.ok` (blue) above 50, `theme.warn` (amber) between 25-50, `theme.crit`
(red) below 25 — the same color logic for every stat, no per-stat
identity color at all.

This is a different convention from the player's own `NeedsGauge` (the
concentric-ring HUD), which does the opposite: each ring has ONE **fixed**
identity color regardless of current fill (health is always red, water is
always blue, etc.) — low-value feedback there comes from a separate
mechanism (the screen-edge critical vignette), not from recoloring the
bar itself. Since you're asking to copy the player HUD's colors, this pass
also adopts that same fixed-color convention for consistency — the NPC
bars will stop recoloring by value and just stay their assigned color,
same as the player's rings already do.

## 2. Colors — where each one comes from

| NPC stat | Color | Source |
|---|---|---|
| Health | `Color(0.81, 0.17, 0.17, 1.0)` | Exact copy of player `NeedsGauge.COLOR_HEALTH` |
| Energy | `Color(0.57, 0.33, 0.81, 1.0)` | Exact copy of player `NeedsGauge.COLOR_SLEEP` (the player HUD's purple) |
| Thirst | `Color(0.24, 0.52, 0.90, 1.0)` | Exact copy of player `NeedsGauge.COLOR_WATER` |
| Mood | `Color8(188, 160, 220, 255)` | `#bca0dc` exactly, as you specified — using `Color8` (0-255 ints) instead of manually converting to floats, so it's the exact hex with no rounding |
| Hunger | `Color(0.90, 0.80, 0.20, 1.0)` | **Flagging this one** — the player HUD has no yellow stat to literally copy (health=red, food=orange, stamina=green, water=blue, sleep=purple — no yellow anywhere). Reused the project's other established yellow (the Power panels' top-stripe color) instead of inventing a new one, for consistency with the rest of the UI. If you had a specific yellow in mind, this is a one-line swap. |

---

## 3. Edit `scripts/ui/npc/NPCTalkMenuUI.gd`

### Step 3.1 — Add the color table

Find this exact line:

```gdscript
const BAR_H: float = 14.0
```

Replace it with exactly this:

```gdscript
const BAR_H: float = 14.0

## Aug 2026 — fixed per-stat identity colors, matching the player's own
## NeedsGauge convention (one color per stat, always, regardless of
## current fill — NOT recolored by value the way this panel used to).
## Health/Energy/Thirst are exact copies of NeedsGauge's
## COLOR_HEALTH/COLOR_SLEEP/COLOR_WATER. Hunger has no player-HUD yellow
## to copy (the player has no yellow stat), so it reuses the project's
## other established yellow (Power panels' stripe color) instead of a new
## one. Mood is Brannon's exact #bca0dc via Color8 (0-255 ints), no
## float-rounding.
const NEED_COLORS: Dictionary = {
	"Health": Color(0.81, 0.17, 0.17, 1.0),
	"Energy": Color(0.57, 0.33, 0.81, 1.0),
	"Hunger": Color(0.90, 0.80, 0.20, 1.0),
	"Thirst": Color(0.24, 0.52, 0.90, 1.0),
	"Mood":   Color8(188, 160, 220, 255),
}
```

### Step 3.2 — Use the fixed color when each bar is first built

Find this exact line:

```gdscript
	var fill: ColorRect = ColorRect.new()
	fill.color = theme.ok
```

Replace it with exactly this:

```gdscript
	var fill: ColorRect = ColorRect.new()
	fill.color = NEED_COLORS.get(need, theme.ok)
```

### Step 3.3 — Stop recoloring by value on every refresh

Find this exact line:

```gdscript
			fill.color = theme.ok if v >= 50.0 else (theme.warn if v >= 25.0 else theme.crit)
```

Replace it with exactly this:

```gdscript
			fill.color = NEED_COLORS.get(need, theme.ok)   ## Aug 2026 — fixed per-stat color, no longer recolors by value
```

---

## 4. Verification checklist

1. Open an NPC's talk panel — Health bar red, Energy bar purple, Hunger
   bar yellow, Thirst bar blue, Mood bar the lighter lavender `#bca0dc`.
2. Drain an NPC's needs low (e.g. via the F7 admin menu's "Drain NPC Needs
   -40") and reopen the panel — confirm each bar's color stays the same as
   full health (no more shifting to amber/red at low values) and only the
   fill LENGTH shrinks, matching how the player's own HUD rings behave.
3. Confirm no console errors referencing `NPCTalkMenuUI`.
