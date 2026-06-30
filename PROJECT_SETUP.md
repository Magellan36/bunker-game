# BunkerGame — Godot 4.6.3 Project Setup Guide

## Folder Structure
```
BunkerGame/
├── scenes/
│   ├── player/       → Player.tscn
│   ├── world/        → MainWorld.tscn
│   └── ui/           → HUD.tscn
├── scripts/
│   ├── player/       → Player.gd
│   ├── world/        → MainWorld.gd, WorldManager.gd
│   ├── ui/           → HUD.gd
│   └── core/         → GameCamera.gd
└── assets/
    ├── textures/
    ├── models/
    └── sounds/
```

---

## Step 1 — Create the Project
1. Open Godot 4.6.3 → **New Project**
2. Name it `BunkerGame`, pick a folder
3. Renderer: **Forward+** (best for 3D lighting/shadows)
4. Copy all files from this zip into your project root

---

## Step 2 — Input Map (REQUIRED)
Go to **Project > Project Settings > Input Map** and add these actions:

| Action Name  | Key        |
|--------------|------------|
| `move_up`    | W          |
| `move_down`  | S          |
| `move_left`  | A          |
| `move_right` | D          |
| `interact`   | E          |

---

## Step 3 — Autoload (WorldManager)
1. **Project > Project Settings > Autoload**
2. Click the folder icon → select `scripts/world/WorldManager.gd`
3. Set Node Name to exactly: `WorldManager`
4. Hit **Add**

---

## Step 4 — Build Player.tscn
1. Scene > New Scene
2. Root node: **CharacterBody3D** → rename to `Player`
3. Add children:
   - `MeshInstance3D` (add a CapsuleMesh or BoxMesh as placeholder)
   - `CollisionShape3D` (add a CapsuleShape3D to match mesh)
   - `Area3D` named `InteractionArea`
     - Add `CollisionShape3D` child to it (small SphereShape3D, radius ~1.2)
4. Attach script: `scripts/player/Player.gd`
5. Add Player to group: select root node → **Node tab > Groups > Add "player"**
6. Save as `scenes/player/Player.tscn`

---

## Step 5 — Build MainWorld.tscn
1. Scene > New Scene
2. Root node: **Node3D** → rename to `MainWorld`
3. Add children in this exact order:
   - `WorldEnvironment`
     - In Inspector: create a new **Environment** resource
     - Set Background Mode to **Sky** or **Color**
   - `DirectionalLight3D` → rename to `DirectionalLight3D`
   - Instance `Player.tscn` as a child (drag from FileSystem)
   - `Camera3D` → rename to `GameCamera`
4. Select `GameCamera`:
   - Attach script: `scripts/core/GameCamera.gd`
   - In Inspector, set **Target Path** → drag the `Player` node into it
5. Select `MainWorld` root:
   - Attach script: `scripts/world/MainWorld.gd`
6. Add a **GridMap** or a flat `MeshInstance3D` (PlaneMesh, size 20x20) as the floor
7. Save as `scenes/world/MainWorld.tscn`

---

## Step 6 — Build HUD.tscn
1. Scene > New Scene
2. Root node: **CanvasLayer**
3. Add child: `Label` → rename to `DebugLabel`
   - Anchor: Top-Left
   - Text: `Pos: 0, 0`
4. Attach script: `scripts/ui/HUD.gd`
5. Save as `scenes/ui/HUD.tscn`
6. Instance HUD.tscn as a child inside `MainWorld.tscn`

---

## Step 7 — Set Main Scene
1. **Project > Project Settings > Application > Run**
2. Set **Main Scene** to `scenes/world/MainWorld.tscn`

---

## Step 8 — Hit Play
Press **F5**. You should see:
- A flat floor
- A capsule/box representing the player
- WASD moves the player
- Camera follows from a 45° overhead angle
- Debug label shows position in top-left

---

## What's Built
| System        | File                  | Status     |
|---------------|-----------------------|------------|
| Player movement | Player.gd           | ✅ Done    |
| Camera follow | GameCamera.gd         | ✅ Done    |
| World root    | MainWorld.gd          | ✅ Done    |
| Global state  | WorldManager.gd       | ✅ Done    |
| HUD           | HUD.gd                | ✅ Done    |

## What's Next (when ready)
- Room/floor system (bunker floors as separate scenes)
- Interactable objects (doors, consoles, loot)
- Inventory system
- NPC/survivor AI
- Resource management (food, water, power)
