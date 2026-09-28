# Webley Mk II

User-supplied model from `/mnt/storage/Bunker Game/models/NEW MODELS/revolver_webley_mkii_brown/`.
`webley_mkii.glb` is the original textured gun mesh at frame 1, exported from Blender
5.1.2 with diffuse and tangent normal textures embedded. Source author/license
information was not supplied in the folder; retain the original alongside the project.

Conversion: evaluate the gun mesh at frame 1, bake its world transform, scale all
vertices by 4.36 (0.071 m source length → 0.31 m), glTF Y-up export. Barrel points
along Godot -Z. Material uses source diffuse/normal maps, roughness 0.48, metallic
0.35. Original UVs and topology are preserved. The original .blend and its rig are
untouched. SOURCE_README.txt records source animation frames for future mechanical
animation import; the current game mesh is intentionally the static rest pose.

No AI-generated image/texture content. Gun uses supplied artwork. The procedural
melee silhouettes, casing, and impact dot are temporary development proxies listed
in `docs/systems/weapons/README.md`; replace before final artwork delivery.
