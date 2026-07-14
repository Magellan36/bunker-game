# Water system playtest round 2 — task list

1. Pipe cost per length (3x wire's $8/m = $24/m) — WaterPipeDrawMode.COST_PER_M
2. Pipe placement grid-snap (same 0.25 grid as wires/walls) — WaterPipeDrawMode._resolve_destination
3. Undo support for pipes (mirror wire undo) — pipe_placed needs elbow_nodes+midpoint added,
   BuildUndoStack "pipe" case, BuildModeController wrapper + connect
4. Starting hookup on west wall, upper portion, placed like a player would — MainWorld spawn
   after pregen, using WallSnapHelpers._snap_to_nearest_wall + _spawn_placed_object, registered
   into _placed_objects (no undo entry, free of charge)
5. Hookup expansion-lag bug — WaterManager._on_chunk_deconstructed/_restored use call_deferred
   (1 frame) but physics server needs the new/removed StaticBody3D collider to actually be
   processed before a raycast sees it — root cause of "one expansion behind, floating" bug.
   Fix: await get_tree().physics_frame (x2) instead of call_deferred.

Status: implementing 1,2,3,5 now (unambiguous). Asking user for west-wall exact spot (item 4)
before implementing since "upper portion" is ambiguous.
