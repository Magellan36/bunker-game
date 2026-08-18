# Editing a Solid-Color-Swatch GLB Texture (e.g. Removing a Label)

Some imported assets (seen so far: `can.glb`) use a "swatch atlas"
texture — a grid of flat solid-color (or gently gradiented) rectangles,
where each mesh face's UVs point at a single point within one swatch,
rather than a traditional unwrapped/painted texture. Recoloring a part
of the model (e.g. removing a printed-looking label) means editing the
texture, not the mesh:

1. Read the mesh's actual TEXCOORD_0 accessor and cross-reference against
   POSITION (e.g. group by height) to find out which swatch pixels the
   part you want to change actually samples — don't guess from looking
   at the texture image alone, different parts can sample very similar-
   looking swatches.
2. Identify the swatch's full pixel block (scan a row/column to find
   where the color changes) — you'll usually want to repaint the whole
   block, not just the exact sampled pixel, in case of mipmapping/filter
   bleed at render time.
3. Prefer sourcing the replacement color from elsewhere already IN the
   same texture (e.g. an unused region of the same gradient column, or
   another already-grey swatch) over inventing a new color — keeps the
   result visually consistent with the rest of the asset's existing
   style.
4. If the source `.glb` references its texture by an external relative
   path (`images[].uri`) rather than embedding it, request that texture
   file directly rather than trying to extract it from the `.glb` (it's
   not in there).
5. When producing the new `.glb`, consider embedding the modified image
   into the binary chunk (`images[].bufferView` instead of `.uri`) even
   if the source used an external reference — removes a fragility point
   for whoever loads the asset later.
6. Used for `assets/models/can-empty.glb` (Aug 2026) — see
   `docs/systems/build/README.md`'s Food Can entry.