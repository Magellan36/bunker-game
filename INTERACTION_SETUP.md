# Interaction System — Implementation Guide

## New Files
| File | Location |
|---|---|
| `InteractionSystem.gd` | `scripts/player/` |
| `PlacementIndicator.gd` | `scripts/world/` |
| `TestCrate.gd` | `scripts/world/` |

---

## Step 1 — Add Input Actions
**Project → Project Settings → Input Map** — add these two new actions:

| Action | Key |
|---|---|
| `place_item` | F |

(You already have `interact` = E from before)

---

## Step 2 — Update Player.tscn

Open `Player.tscn`. Add these children to the `Player` (CharacterBody3D) root:

### A) InteractionSystem node
1. Add child → **Node3D** → rename to `InteractionSystem`
2. Attach script: `scripts/player/InteractionSystem.gd`

### B) RayCast3D (child of InteractionSystem)
1. Select `InteractionSystem` → add child → **RayCast3D** → rename to `InteractRay`
2. Inspector:
   - **Target Position**: `(0, 0, -2)` (shoots forward)
   - **Enabled**: ON
   - **Collision Mask**: 1 (hits layer 1 objects)

### C) HoldPoint (child of InteractionSystem)
1. Select `InteractionSystem` → add child → **Node3D** → rename to `HoldPoint`
2. Leave position at (0,0,0) — the script sets it automatically

### D) PlacementIndicator (child of InteractionSystem)
1. Select `InteractionSystem` → add child → **Node3D** → rename to `PlacementIndicator`
2. Add a child to it → **MeshInstance3D** (leave mesh empty — script builds it)
3. Attach script to `PlacementIndicator`: `scripts/world/PlacementIndicator.gd`

---

## Step 3 — Add "world" group to MainWorld

The interaction system needs to find the world root to reparent items on drop.

1. Open `MainWorld.tscn`
2. Click the root `MainWorld` node
3. **Node tab** (next to Inspector) → **Groups** → type `world` → Add

---

## Step 4 — Create TestCrate.tscn

1. **Scene > New Scene** → root: **RigidBody3D** → rename to `TestCrate`
2. Add children:
   - `MeshInstance3D` → BoxMesh, size `(0.6, 0.6, 0.6)`
     - Material: StandardMaterial3D, brown/tan color (`#8B6914`), Roughness 0.85
   - `CollisionShape3D` → BoxShape3D, size `(0.6, 0.6, 0.6)`
3. Attach script: `scripts/world/TestCrate.gd`
4. Inspector on root RigidBody3D:
   - **Mass**: 5.0
   - **Collision Layer**: 1
   - **Collision Mask**: 1
5. Save as `scenes/world/TestCrate.tscn`

---

## Step 5 — Place Test Crates in MainWorld

1. Open `MainWorld.tscn`
2. Instance `TestCrate.tscn` 3–4 times (drag from FileSystem into scene)
3. Spread them around the bunker floor at various positions
4. Set each Y position to `~0.3` so they sit on the floor

---

## Step 6 — Hit F5 and Test

| Action | Input |
|---|---|
| Walk up to crate | WASD |
| Pick up | E (tap) |
| Quick drop | E (tap again) |
| Enter placement mode | Hold E |
| Move placement target | Move mouse |
| Confirm place | F |

### What to expect:
- Crate snaps with a satisfying bounce into player's hands
- A pulsing green disc appears when holding E
- Disc follows mouse position on the floor, clamped to ~2.5 units from player
- F places the item at the disc location, frozen in place

---

## Troubleshooting

**Can't pick up crate — nothing happens:**
→ TestCrate not in `pickup` group. Open TestCrate.tscn, select root, Node tab → Groups → add `pickup`
→ OR: confirm `_ready()` in TestCrate.gd has `add_to_group("pickup")`

**Item flies off on pickup:**
→ RayCast3D `collision_mask` doesn't match the crate's `collision_layer`. Both should be 1.

**Placement disc doesn't appear:**
→ PlacementIndicator node path is wrong. Make sure it's a direct child of InteractionSystem named exactly `PlacementIndicator` with a `MeshInstance3D` child.

**Item drops through the floor:**
→ After drop, collision re-enables but Jolt physics needs a frame to register. This is normal — if it falls through consistently, set crate CollisionShape to slightly larger than mesh.

**"world" group error in output:**
→ You forgot Step 3. Add `world` group to MainWorld root node.
