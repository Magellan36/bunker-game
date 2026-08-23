# Tool Usage Guide for AI Agents on bunker-game

**Read this before starting any task that touches player models, scenes,
textures, or anything that would normally require manually opening
Blender or the Godot editor.**

This project has live, working MCP (Model Context Protocol) tool access
to Blender, Godot, and this machine's filesystem — not just the sandboxed
code-execution environment most Claude sessions default to. If you're
reading this because a task seems to require "someone to physically open
Blender and check," it almost certainly doesn't — you can probably do it
yourself. This doc exists because agents on this project have
repeatedly failed to realize that, or have fumbled the tools once they
found them. Both problems are avoidable.

## The #1 reason agents miss these tools entirely

**These tools are not visible by default.** They are *deferred* — hidden
behind a `tool_search` call until you explicitly search for and load
them. If you don't call `tool_search`, you will not see Blender, Godot,
or Filesystem tools in your available tool list, and you may incorrectly
conclude you don't have access to them at all.

**Fix:** at the start of any task on this project, proactively call
`tool_search` with relevant keywords — `"blender"`, `"godot"`,
`"filesystem edit file"` — before assuming a capability is unavailable.
If a specific tool call fails with `Tool 'X' not found`, that means the
tool exists but hasn't been loaded into context yet — call `tool_search`
again with a more specific query (often just the exact tool name), then
retry the same call. This is not a dead end; it's one extra step.

Do this *before* telling the user you can't do something, and before
falling back to writing code for them to run themselves. A task like "go
check the mesh in Blender" or "look at the running game" is very likely
directly doable via these tools.

## The second-biggest mistake: confusing two different filesystems

You have **two separate, unrelated filesystems** available, with
similarly-named tools that are easy to mix up:

1. **Your own sandbox** (`bash_tool`, `view`, `str_replace`,
   `create_file`) — a throwaway Linux container that has nothing to do
   with the actual project. Useful for scratch computation (e.g., image
   processing with PIL/numpy) but **files here are not the project**.
2. **The user's actual machine** (`Filesystem:read_text_file`,
   `Filesystem:edit_file`, `Filesystem:write_file`,
   `Filesystem:list_directory`, `Filesystem:search_files`,
   `Filesystem:copy_file_user_to_claude`) — this is the real project at
   `C:\Users\Berkley\Documents\Default Project\bunker-game`. Godot and
   Blender (below) both operate on this same real machine.

**Concrete symptom of getting this wrong:** calling `view` or
`str_replace` on a `C:\Users\...` path fails with "not an absolute
path" — that error means you used a sandbox tool on a real-machine path.
Switch to the matching `Filesystem:` tool instead.

`Filesystem:list_allowed_directories` will show you the real project
root if you're ever unsure which filesystem you're in.

**To view an image or file from the real machine** (e.g. a render, a
texture, a screenshot the user attached that references a project file),
you must first pull it into your own sandbox with
`Filesystem:copy_file_user_to_claude`, then `view` the sandbox copy. You
cannot `view` a `C:\...` path directly.

## Blender (`Blender:execute_blender_code` and friends)

This runs real Python (`bpy`, and `numpy`/`PIL` if imported) **on the
user's actual machine**, inside their actual Blender install. You can
import project assets, inspect/modify meshes, render preview images, and
save results back to disk — all headlessly, without the user touching
anything.

**Critical gotcha — no persistent Python namespace between calls.** Each
`execute_blender_code` call runs in a fresh `exec()` namespace. Variables
and imports from a previous call are gone; you'll get
`NameError: name 'bpy' is not defined` if you forget this. **What does
persist** is Blender's own scene data (`bpy.data.objects`, meshes,
materials you created earlier) — so re-`import bpy` and redefine any
helper functions every call, but don't assume you need to re-import
`.gltf`/`.fbx` files if they're already loaded in the session (check
`bpy.data.objects` first).

**Workflow that actually works:**
1. Import the real asset with `bpy.ops.import_scene.gltf(filepath=...)`
   or `.fbx(...)`, using the real `C:\...` path (Blender's Python can
   read any path on the machine, unlike the `Filesystem:` tool's
   sandboxed allowlist).
2. Inspect/modify directly (`bpy.data.objects[...].data.vertices`, etc).
3. **Render a preview and actually look at it** before believing your
   own reasoning about what a change will look like — set up a camera
   and light once, render to a file, then `Filesystem:copy_file_user_to_claude`
   + `view` it. Don't skip this step to save time; several serious wrong
   turns in this project's history came from reasoning about geometry
   changes without ever rendering them.
4. Only write back to the *actual* game asset file once you've visually
   confirmed the change looks right in a preview render — treat the
   live project files as something to update deliberately, not
   iteratively.

**Known quirks worth knowing up front:**
- glTF import auto-converts Y-up to Blender's Z-up — after import,
  "height" is the Z axis, not Y. Check `object.dimensions` /
  bounding-box axes before assuming which axis means what.
- UV texture coordinates: `pixel_y = (1 - v) * image_height` (V is
  flipped relative to image row order).
- Getting exact screen-to-mesh correspondence (e.g. "what texture pixel
  is this visible spot on the render") requires a real raycast +
  barycentric UV interpolation from the camera through the pixel — not
  just eyeballing crops. Don't guess-and-check crop coordinates by hand
  more than once or twice; if that's not converging, switch to
  raycasting from a camera you control, or overlay a coordinate grid on
  a render and read exact pixel coordinates back off it.
- If numpy processing seems to hang or get killed, you're probably using
  `np.vectorize(colorsys.rgb_to_hsv, ...)` or similar — that's not
  actually vectorized, it's a slow per-pixel Python loop. Use
  `matplotlib.colors.rgb_to_hsv`/`hsv_to_rgb` (genuinely vectorized) for
  full-resolution image work instead.

## Godot (`godot:*` tools)

Also operates on the user's real, actual Godot editor — the same editor
window they can see and interact with. Key tools and what they're
actually for:

- `godot:editor-application-set-state` (`isPlaying: true/false`,
  `scene: "main"|"current"`) — start/stop a play session. This is how
  you playtest without the user pressing anything.
- `godot:script-validate` — compile-check GDScript changes. **Run this
  after every script edit**, before playtesting. Catches syntax errors
  for free.
- `godot:filesystem-reimport` — force Godot to notice changed/new files
  on disk (new assets, edited `.import` files). Call this after writing
  files directly via `Filesystem:write_file` rather than through the
  editor.
- `godot:scene-create` / `godot:node-create` / `godot:node-find` /
  `godot:node-delete` — build and inspect scene trees. `node-find` with
  `hierarchyDepth` is the way to discover a real imported scene's actual
  node structure (e.g. where the `Skeleton3D` actually lives inside an
  imported FBX) rather than guessing from the source file's authoring
  tool.
- `godot:resource-find` / `godot:resource-delete` — locate and clean up
  resources by `res://` path.
- `godot:console-get-logs` / `godot:runtime-errors-get` — **read the
  caveats below before relying on these.**

**Critical limitation — you cannot see the actual running game.** There
is no screenshot tool for a live play session, and:
- `console-get-logs` only captures the *editor plugin's own* connection
  activity — **not** `print()` output from the separate game process
  Godot spawns on Play.
- `runtime-errors-get` requires the game's own code to have called
  `GodotMcpRuntime.Initialize(b => b.WithRuntimeErrorCapture())` — this
  is **not** currently enabled in this project, so it will report zero
  errors regardless of what's actually happening.

**The workaround that actually works: write diagnostics to a plain file
inside the project directory, then read it back with `Filesystem:`
tools.** `res://` resolves into the real project folder, so:

```gdscript
static func _dup_diag_log(msg: String) -> void:
    var path := "res://_dup_diag.log"
    var existing := ""
    if FileAccess.file_exists(path):
        var rf := FileAccess.open(path, FileAccess.READ)
        if rf != null:
            existing = rf.get_as_text()
            rf.close()
    var wf := FileAccess.open(path, FileAccess.WRITE)
    if wf != null:
        wf.store_string(existing + "[%s] %s\n" % [Time.get_time_string_from_system(), msg])
        wf.close()
```

Add a temporary call to this at the point you need visibility into
(state values, whether a code path ran, resolved NodePaths, etc.),
`filesystem-reimport`, play-test via `editor-application-set-state`,
then `Filesystem:read_text_file` the log. **Clear the log file before
each test run** so you're not reading stale output. Remove the
diagnostic once you've solved the problem — don't leave debug logging
permanently wired into shipped code.

This pattern solved every "why doesn't this show up in-game" mystery in
this project's history — including one where the visible symptom
(T-pose instead of animation) had nothing to do with the actual
diagnosis (a runtime-instantiated node needed a specific hardcoded name
for animation tracks to resolve), which would have been very hard to
guess from the symptom alone without direct runtime state visibility.

**Because you can't see the render, ask the user to look and describe
or screenshot what they see** at natural checkpoints — don't assume
success just because a script ran without errors. "No crash" and
"looks correct" are different claims; only confirm the ones you can
actually verify yourself.

## The general workflow that works

1. **Verify before you build.** Don't write code against assumptions
   about a mesh, rig, or texture — load it in Blender and check
   directly. Several long, expensive detours in this project's history
   came from reasoning about asset structure instead of inspecting it.
2. **Read the asset's own documentation before reinventing a solution.**
   A multi-week custom clipping-avoidance system turned out to be
   solving a problem the asset creator's own README had already
   addressed in one sentence. If a third-party asset pack is involved,
   check for a README/changelog in the pack folder — and its publisher's
   web page — before building a workaround.
3. **Reuse this project's existing solved patterns before inventing new
   ones.** E.g. this project already has a working
   Godot-Humanoid-retarget setup (`bone_map_native.tres`) for handling
   animation compatibility across differently-named skeletons — that
   exact mechanism, copied faithfully, is what made a totally different
   character pack's rig work with the existing animation library on the
   first real test. Look for the established pattern before building a
   new one from scratch.
4. **When something behaves inconsistently or "shouldn't be possible,"
   suspect the tool connection before your own logic** — but verify
   quickly and move on. MCP connectors (Blender, Godot, Filesystem) do
   intermittently hang for several minutes or return null with no
   explanation. If a call hangs or errors strangely, a straightforward
   retry often just works. If it keeps failing identically, that's
   worth flagging to the user rather than silently working around it —
   but don't assume disconnection on the first hiccup.
5. **Clean up scratch/test scenes and files you create for
   verification** (scratch `.tscn` files, temp render PNGs, temporary
   diagnostic logging) once you're done with them — this project's
   asset folders have previously accumulated dozens of leftover debug
   files from exactly this kind of iteration. Don't let temporary
   verification artifacts become permanent project clutter.
6. **Don't delete working systems to build a new one** unless
   explicitly asked to. When this project's scope narrowed (e.g. V1
   dropping character customization), the right move was clearly
   marking the old system as intentionally unused with a note
   explaining why and how to revive it — not deleting it.

## If you're still stuck

If after calling `tool_search` you genuinely don't see Blender/Godot/
Filesystem tools available at all (not just a specific sub-tool), that's
a real connector issue, not a discovery issue — say so plainly to the
user rather than working around it by writing code for them to run
manually. It's a fast, cheap thing for them to check (usually just
restarting the relevant MCP server), and far better than an agent
silently reverting to "I can't do this, here's what you should do
instead" when the actual capability is one `tool_search` call away.
