# Crowbar

"Crowbar" by Clint Bellanger, public domain (CC0); see `crowbar_credits.txt`.
Source `crowbar.blend` is in `/mnt/storage/Bunker Game/models/NEW MODELS/Baseball Bat/crowbar.zip`.

Conversion (Blender 5.1.2): camera/lamp removed, transforms applied, uniformly scaled
to 0.60 m, hook end along Godot -Z, origin at the grip 18% from the straight end.
The source carries no colour (white vertex colours, grey materials), so the game
applies a plain dark-steel StandardMaterial3D in `WeaponItem.gd`.
