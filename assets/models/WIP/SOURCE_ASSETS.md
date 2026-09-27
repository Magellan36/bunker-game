# Archived model source packs

This directory preserves the original vendor packs (Unity/Unreal FBX, Blender
sources, and duplicate textures). The game uses the prepared assets outside
this directory, principally `assets/models/player`.

`.gdignore` keeps these archives out of Godot's automatic import and exports.
Several vendor FBX files embed the author's absolute `C:/Dropbox/...` texture
paths; importing them on a clean machine produces missing-texture errors.
No active game script, scene, material, or animation resource was found to
reference this directory in the Linux migration audit.

To develop a new asset, open the original source in Blender, resolve its textures,
and export a portable GLB/FBX into the appropriate active asset directory.
Keep texture references relative. Blender import remains enabled project-wide;
the Linux setup helper configures the installed Blender executable.
Do not remove `.gdignore` just to use an archive: doing so imports every vendor
variant again, including the variants with broken paths.
