# Build / Shop / Storage UI patch

Commit: `6ff7370`  
Expected base: `ade5eb1`

## Preferred: Git patch

From the project root:

```sh
git am /path/to/0001-ui-overhaul-build-shop-and-storage-workflows.patch
```

This preserves the isolated commit and lets Git stop safely if local edits
overlap. Abort a failed application with `git am --abort`.

## Filesystem install

Make a copy/commit of current local work, then extract
`bunker-ui-build-shop-storage-install.zip` directly into the project root and
allow it to merge the included folders. The ZIP contains only files belonging
to this UI pass; it does not contain or remove unrelated project files.

Because this workspace was reconstructed from commit `ade5eb1`, prefer the Git
patch if a local project contains uncommitted changes to `Player.gd`,
`BuildModeHUD.gd`, `ControllerUINavigation.gd`, `StorageUI.gd`,
`BuildModeController.gd`, or `FarmingShopHelper.gd`. Git will expose overlaps
instead of silently replacing them.

## Test

Open/import the project with its normal Godot .NET editor, then run:

```sh
godot --headless --path . --script res://tools/tests/ui_rehaul_smoke.gd
```

In a normal playtest, verify: one shelving object, one basket, repeated
inventory transfers, controller scrollbar focus, build placement/cancel/back,
shop cart persistence, insufficient-cash checkout, and a successful mixed
checkout with clear space around the player.
