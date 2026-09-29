# Weapons handoff (2026-09-28, fists added later that day)

## Working agreement (Brannon, 2026-09-28)

Three sessions, one feature: Weapons (local), Animation polish (local), NPC system
polish review (local). Work as one team:

- Each session builds and verifies its own area once, then commits and pushes.
  Don't re-verify another session's pushed work, and skip checks that are ~99%
  certain to pass. Brannon tests game loads and small tweaks himself.
- Message only when it changes someone else's work: a new or changed API, a
  request, or a real bug you found. No "looks good" review rounds.
- Never edit another session's files; ask the owner instead.

Brannon split the remaining weapons work three ways. This file is the contract
between the sessions, so nobody edits someone else's area.

| Area | Owner | Files |
|---|---|---|
| Weapon gameplay (ammo, reload, hits, whip, variants, shop entries) | Weapons session (local) | `scripts/weapons/WeaponItem.gd`, `WeaponController.gd`, `WeaponEffects.gd`, `WeaponReticle.gd`, `scenes/weapons/*`, `assets/models/weapons/*`, `tools/tests/Weapons*` |
| Player and NPC weapon animation | Animation polish session (local) | `scripts/weapons/PistolAnimationLayer.gd` (handed over), `scripts/player/Adventurer*`, `assets/models/player/**`, `tools/anim_pipeline/**` |
| NPCs using weapons (when/why, targeting, damage → health/medical) | NPC system polish session (cloud) | `scripts/npc/**`, `scenes/npc/**`, `docs/systems/npc/**` |

Need a change in someone else's area? Ask them (local: SendMessage; cloud: a
note in your commit message plus ask Brannon to relay). Don't patch it yourself.

## Gameplay API (stable, owned by the weapons session)

`WeaponItem` (extends PickupableItem, one per weapon, `weapon_kind` in
`revolver | knife | hatchet | pipe | bat | crowbar`):

- `signal attack_started(kind: String, variant: int)`: emitted on every committed
  attack. `kind` is `weapon_kind`, or `"pistol_whip"` when the revolver is empty.
  `variant` is 0 for the regular attack and 1 for the occasional alternate melee
  swing (about 30%, never twice in a row; `attack_variant_chance`).
- `strike_delay` (export): seconds from the press to melee contact. Placeholders:
  bat 0.22, crowbar 0.16, others 0.10, whip uses the same field. **Animation
  session:** set these to the real contact frame of the clips you pick (edit the
  weapon `.tscn` values, or tell the weapons session).
- `signal aim_changed(aiming: bool)`, `signal dry_fired`, `signal hit_resolved(hit)`,
  `is_firearm()`, `ammo`, `aiming`.
- `grip_anchor: Node3D`: set it to a hand marker and the weapon follows it every
  physics tick (`sync_held_pose()`). While it's set, the placeholder procedural
  swing wobble on the model is disabled, so the hand animation owns the motion.
- Models: grip at the origin, striking end/barrel along local -Z. Bat 0.84 m,
  crowbar 0.60 m, Webley 0.31 m.
- `try_attack(direction: Vector3) -> bool` needs `is_held`, `aiming == true`, and
  no cooldown/reload. The holder is the first CharacterBody3D above the hold point.
- Hits call `receive_weapon_hit(context)` on the collider or its nearest ancestor
  that has it. context = `{damage, position, direction, kind, source, collider}`,
  where `kind` can be `"pistol_whip"`, and `source` is the attacker's CharacterBody3D.

Empty revolver: every attack is a pistol whip (14 damage, 1.3 m reach, 0.55 s
interval, no ammo, no case). Reloading (E) still works; a reload animation clip is
still to come from Brannon.

## Fists (unarmed combat, owned by the weapons session)

`scripts/weapons/Fists.gd`: a Node3D you add as a child of any CharacterBody3D.
It has the same API as WeaponItem (`set_aiming`, `try_attack(dir)`, `cancel_action`,
`aiming`, `attack_started`, `hit_resolved`, `aim_changed`).

- Player: `WeaponController` creates one automatically. With empty hands, holding
  RMB (or the right stick) aims and LMB (or RT) punches.
- `attack_started("punch", variant)`: variant 0 is a jab, 1 is a cross. They
  alternate, and a pause over 0.9 s starts again at the jab.
- Hit context: `kind = "punch"`, `variant`, `damage` (jab 5, cross 8), reach 1.1 m,
  and `source`, `position`, `collider` as for weapons.
- `jab_strike_delay` / `cross_strike_delay` (exports, placeholders 0.12 / 0.18 s):
  the animation session sets them to the clips' contact frames.
- NPCs: `var fists = preload("res://scripts/weapons/Fists.gd").new(); npc.add_child(fists)`,
  then `fists.set_aiming(true)` and `fists.try_attack(dir)`, exactly like a weapon.

## Hit reactions (animation + NPC sessions)

Clips (male/female): `PUNCHING HEAD HIT`, `PUNCHING RIB HIT`, `PUNCHING STOMACH HIT`,
`AIMING PISTOL HIT`, in the same source folder.

- Animation session: add a model API such as `play_hit_reaction(context)`. It picks
  the clip from the hit height (`context.position` against the body) and uses
  `AIMING PISTOL HIT` while the victim is aiming a firearm.
- NPC session: call it from `NPC.receive_weapon_hit` and from
  `NPCCombat.apply_player_hit` (player victims).

## Animation session: what to wire

Human-made source clips, male and female each, in
`/mnt/storage/Bunker Game/models/NEW MODELS/Baseball Bat/`:
`Baseball Idle`, `Baseball Swing`, `Baseball Swing adjust`, `Pistol Whip`,
`Shooting Pistol` (`Baseball Idle.fbx` without a suffix is a byte-size duplicate
of the FEMALE one). No reload clip yet.

- Melee hold: `Baseball Idle` while a melee weapon is held (the weapons session
  suggests all of bat/crowbar/pipe/hatchet; knife is your call until it has a clip).
- `attack_started(kind, 0)`: `Baseball Swing`; `attack_started(kind, 1)`:
  `Baseball Swing adjust` (Brannon wants it to play occasionally instead of the
  regular swing, for flavour).
- `attack_started("revolver", 0)`: `Shooting Pistol`, over the existing pistol layer.
- `attack_started("pistol_whip", 0)`: `Pistol Whip`.
- Melee hand attachment: set `grip_anchor` like `PistolAnimationLayer` does for
  the Webley. `PistolAnimationLayer.gd` is yours now; extend or replace it.
- Fists: `PUNCHING IDLE` while Fists `aiming` (use `aim_changed`), `PUNCH JAB` for
  variant 0 and `PUNCH CROSS` for variant 1. This applies to the player and to NPCs
  that hold a Fists node.
- Provenance rule applies: bake only re-expresses keys, any adaptation happens at runtime.

## NPC session: what to wire

Brannon's escalation: light hatred leads to a fist fight (Fists); intense hatred
leads to picking up a weapon and trying to kill another NPC or the player (already
done in 7282f0b).


Weapons aren't connected to NPCs yet. Test targets are the only receivers.

- NPCs holding and using weapons: parent the weapon to an NPC hold point
  (`pickup(hold_point)`), call `set_aiming(true)`, then `try_attack(dir)` from a
  physics tick. Only the player's `WeaponController` handles input; NPCs drive
  `WeaponItem` directly.
- Taking hits: implement `receive_weapon_hit(context)` on the NPC. Deciding what
  damage means (health, medical injuries, morale/relationships toward
  `context.source`) is up to the NPC and medical systems.
- NPC weapon animation: ask the animation session. The pistol layer is currently
  player-only (the controller skips NPCs).
- Weapons are sold in the shop (item ids 22–27, `FarmingShopHelper.SHOP_ITEM_INFO`).
  If NPCs should pick them up or store them, they're normal PickupableItems in the
  `inventory_item` group, with `shelf_item_type = "weapon_<kind>"`.
