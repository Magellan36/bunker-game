# HUD — Implementation Guide

## New Files
| File | Location |
|---|---|
| `HUD.gd` | `scripts/ui/` |
| `CircleFill.gd` | `scripts/ui/` |
| `StatusBars.gd` | `scripts/ui/` |

---

## Scene Tree to Build

Open `HUD.tscn` (or create it fresh). Build this exact tree:

```
CanvasLayer  (HUD.gd)
├── BottomLeft          [Control]
│   └── Bars            [VBoxContainer] (StatusBars.gd)
├── LeftIcons           [VBoxContainer]
│   ├── FoodCircle      [Control] (CircleFill.gd)
│   ├── WaterCircle     [Control] (CircleFill.gd)
│   └── SleepCircle     [Control] (CircleFill.gd)
└── TopRight            [Control]
    └── CashLabel       [Label]
```

---

## Step 1 — CanvasLayer root
1. Open `HUD.tscn`
2. Attach `scripts/ui/HUD.gd` to the root CanvasLayer

---

## Step 2 — BottomLeft (Health + Stamina bars)
1. Add child → **Control** → rename `BottomLeft`
2. Inspector → **Layout > Anchors Preset** → **Bottom Left**
3. Set **Offset Left**: `16`, **Offset Bottom**: `-16`
4. Add child → **VBoxContainer** → rename `Bars`
5. Attach script: `scripts/ui/StatusBars.gd`

---

## Step 3 — LeftIcons (Food / Water / Sleep circles)
1. Add child to CanvasLayer → **VBoxContainer** → rename `LeftIcons`
2. Inspector → **Layout > Anchors Preset** → **Center Left**
3. Set **Offset Left**: `16`, **Offset Top**: `-60`
4. Inspector → **Theme Overrides > Constants > Separation**: `8`
5. Add 3 children, all **Control** nodes:
   - Rename to `FoodCircle`, `WaterCircle`, `SleepCircle`
   - Attach `scripts/ui/CircleFill.gd` to each
6. For each CircleFill in Inspector, set **Label Text**:
   - FoodCircle → `F`
   - WaterCircle → `W`
   - SleepCircle → `Z`

---

## Step 4 — TopRight (Cash)
1. Add child to CanvasLayer → **Control** → rename `TopRight`
2. Inspector → **Layout > Anchors Preset** → **Top Right**
3. Set **Offset Right**: `-16`, **Offset Top**: `16`
4. Add child → **Label** → rename `CashLabel`
5. Label Inspector:
   - **Text**: `$0`
   - **Horizontal Alignment**: Right
   - **Layout > Anchors Preset**: Top Right
   - **Theme Overrides > Font Sizes**: `18`
   - **Theme Overrides > Colors > Font Color**: `#c8c8c8`

---

## Step 5 — Instance HUD in MainWorld
1. Open `MainWorld.tscn`
2. Drag `scenes/ui/HUD.tscn` into the scene tree as a child of MainWorld

---

## Step 6 — Test with placeholder values
Add this temporarily to `MainWorld.gd` to verify everything displays:

```gdscript
func _ready() -> void:
    _setup_lighting()
    # Temp HUD test — remove later
    var hud = $HUD
    hud.set_health(80.0)
    hud.set_stamina(60.0)
    hud.set_food(0.9)
    hud.set_water(0.45)
    hud.set_sleep(0.15)   # This one should pulse red
    hud.set_cash(12500)
```

---

## How to update HUD from game systems (later)
Any script can call:
```gdscript
var hud: CanvasLayer = get_tree().get_first_node_in_group("hud")
hud.set_health(75.0)
hud.set_cash(9999)
```

Add `HUD` to the `hud` group: select CanvasLayer root → Node tab → Groups → add `hud`

---

## Customization
| Property | Where | Effect |
|---|---|---|
| `radius` / `thickness` | CircleFill Inspector | Circle size and ring width |
| `bar_width` / `bar_height` | StatusBars Inspector | Bar dimensions |
| Label Text (F/W/Z) | CircleFill Inspector | Center icon letter |
