# Fix Plan — Shelf Corner Posts Reach Too High Above Top Platform

## Root Cause

`_build_mesh()`'s post-building code (`Shelving.gd:126-127`) — shared by all three shelf variants (Small/Medium/Large don't override this function, only `_init()` tunables) — computes post height as:
```gdscript
var post_h: float = unit_h - 0.2375   ## shortened by 0.45, then increased by 0.1125 + 0.10
var post_y_offset: float = 0.45 * 0.5   ## shift down so top is lower
```
Both constants (`0.2375`, `0.45`) are **stale leftovers from before the Aug 2026 tier-spacing resize** (spacing was 0.45 when these were tuned; it's 0.60 now on every variant, and `unit_h` was independently raised 2.5→3.55 in that same pass for a different reason — top-tier item headroom). Nothing recomputed the post formula when those values changed, so it drifted badly out of sync with the actual shelf geometry.

**Measured on Medium Shelf** (current values: `unit_h = 3.55`, top shelf at `shelf_y[-1] = 2.52`): `post_h = 3.3125`, post top = `post_h*0.5 - post_y_offset + post_h*0.5 = post_h - post_y_offset = 3.0875`. That's **0.5675 m above the top shelf** — matches the reported "reaching too high" exactly. Same formula, same problem, on Small and Large (they share this code, just with their own `shelf_y`/`unit_h`).

## Fix — Derive Post Height Directly From `shelf_y`, Not From `unit_h`

Target, per the request: posts extend above the top platform by **1/6 of the tier spacing** (0.60/6 = 0.10 m — also close to 1/6 of TestCrate's height, 0.48/6 = 0.08, as the secondary reference point given). Computing it from tier spacing rather than hardcoding 0.10 keeps it correct automatically if spacing is ever tuned again — exactly the kind of drift that caused this bug in the first place.

**File:** `scripts/world/furniture/Shelving.gd`, replace lines 126-127:
```gdscript
	var post_h: float = unit_h - 0.2375   ## shortened by 0.45, then increased by 0.1125 + 0.10
	var post_y_offset: float = 0.45 * 0.5   ## shift down so top is lower
```
with:
```gdscript
	## Aug 2026 — rebuilt from shelf_y directly instead of unit_h. The old
	## formula (unit_h - 0.2375) was tuned against the pre-resize 0.45 tier
	## spacing and never recomputed when spacing/unit_h changed in the crate-
	## fit pass, so posts drifted to reaching ~0.57m above the top shelf.
	## Posts now extend exactly 1/6 of the tier spacing above the TOP shelf
	## (≈ 0.10m at the current 0.60 spacing — also close to 1/6 of TestCrate's
	## height, the secondary reference point). post_y_offset (how far the
	## post's bottom sits below floor level, for the embedded/anchored look)
	## is unchanged and independent of this.
	var tier_spacing: float  = (shelf_y[1] - shelf_y[0]) if shelf_y.size() > 1 else 0.60
	var post_top_excess: float = tier_spacing / 6.0
	var post_y_offset: float   = 0.225
	var post_h: float          = shelf_y[shelf_y.size() - 1] + post_top_excess + post_y_offset
```
Everything below this (corner positions, the post/lip mesh-building loop, `post_mi.position = Vector3(corner.x, post_h * 0.5 - post_y_offset, corner.y)`) is **unchanged** — it already derives from `post_h`/`post_y_offset`, so it picks up the corrected value automatically. Slot notches (~line 156-164) are keyed directly to `shelf_y`, not `post_h` — unaffected, no edit needed.

**Verify the math (for the agent, not to re-derive):** Medium — spacing 0.60, excess 0.10, top shelf 2.52 → `post_h = 2.845`; post top = `post_h - post_y_offset = 2.62` = top shelf + 0.10 ✓. Post bottom = `-post_y_offset = -0.225`, unchanged from before (still slightly below floor for the anchored look — not part of this report, deliberately preserved). Small — spacing 0.60, top shelf 1.32 → post top = 1.42 ✓. Large inherits Medium's `shelf_y` — same result as Medium.

## Note on `unit_h` — deliberately left unchanged
`unit_h` (3.55 on Medium/Large, 2.35 on Small) now visually **overshoots** the actual post height by design, not by mistake — it's still doing two other jobs: sizing the collision box (`_build_collision()`, `cshape.position = Vector3(0, unit_h*0.5, 0)`) tall enough to leave headroom for a crate-height item stored on the top shelf, and setting the E-prompt world height (`get_prompt_world_pos`-equivalent, `global_position + Vector3(0, unit_h+0.3, 0)`). Shrinking `unit_h` to match the new shorter posts would remove that headroom and drop the prompt height — out of scope for this report, which is specifically about the visible post bars. Flagging so this gap between "visual post height" and "unit_h-derived collision height" isn't mistaken for a leftover bug later.

## Out of scope
- `unit_h`, collision box sizing, E-prompt height — see note above, intentionally untouched.
- Shelf platforms, slot markers/notches, `unit_w`/`unit_d`/`multi_col_spacing` — none reference `post_h`, none affected.
- Small/Large `_init()` overrides — no changes needed; both inherit the fixed base formula automatically.

## Documentation Updates (same commit)
1. `docs/systems/furniture-items/README.md` — Shelf family section: note post height is now derived live from `shelf_y` (top shelf + 1/6 tier spacing), not from `unit_h`; note `unit_h` intentionally stays taller for collision/headroom/prompt purposes.
2. `HANDOVER.md` — entry: "Shelf Corner Post Height Fix — Aug 2026": symptom (posts towering ~0.57m over the top shelf), root cause (stale hardcoded offsets left over from the pre-resize 0.45 tier spacing, never recomputed when spacing changed), fix (post height now derived directly from `shelf_y` + 1/6 spacing), applies to all three variants automatically via the shared base.

## Verification Checklist (Brannon, in-editor)
1. **Visual:** place a Medium Shelf — corner posts now stop a small amount above the top platform (roughly the height of a stubby ledge, not the tall overshoot from before).
2. **All three sizes:** repeat on Small and Large Shelf — same proportionally-correct short overshoot on each (Small's is shorter in absolute terms since its top shelf sits lower, same 1/6-spacing ratio).
3. **Nothing else moved:** shelf platforms, slot positions, stored items, notches, and post *bottom* embedding all look identical to before — only the top of the post bar changed.
4. **Collision/prompt unaffected:** E-prompt still appears at the same height as before; a crate placed on the top shelf still has the same headroom as before (collision box didn't shrink).
