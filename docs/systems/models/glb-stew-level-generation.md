# Generating Fill-Level GLB Variants From an Empty/Full Pair

When an artist provides two GLB files — one "empty" container and one
"full" (with contents fused into the same mesh as the container, no
separate liquid/content node) — intermediate fill levels can be generated
programmatically rather than requesting more source files:

1. Load both files' POSITION accessors (raw vertex buffers), NOT just the
   `.import` metadata.
2. Diff them: any vertex in the "full" file whose (x,y,z) doesn't appear
   in the "empty" file (compare rounded to ~4 decimal places to avoid
   float-precision false negatives) is content geometry, not container
   geometry. This works regardless of how many separate visual features
   (rim, handles, texture seams) the container has, as long as the
   "empty" file's container geometry is otherwise identical to the "full"
   file's.
3. For N intermediate levels, translate ONLY those isolated vertices'
   Y-coordinate by `target_center - current_center`, where
   `current_center` is the midpoint of the isolated vertices' existing Y
   range and `target_center = current_center * (level / N)` for a linear
   fill progression. Leave every other vertex, the index buffer, UVs,
   normals, and materials untouched — this is a pure per-vertex
   translation, not a remesh, so it can't introduce topology errors.
4. Sanity-check with a side-view scatter plot (X vs Y) of the isolated
   vertices against the container's own vertex silhouette before treating
   any output as final — confirms the levels land inside the container's
   actual interior wall span rather than clipping through the floor or
   poking past the rim.
5. Used for `assets/models/pot-stew-{1,2,3}.glb` (Aug 2026) — see
   `docs/systems/build/README.md`'s Cooking Pot entry.