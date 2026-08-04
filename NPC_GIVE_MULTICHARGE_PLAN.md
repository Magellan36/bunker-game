# NPC Give — Multi-Charge Items (Aug 2026)

**Owner:** NPC Claude instance (this plan).

**Prerequisite:** requires all four prior NPC plans applied
(`RELATIONSHIPS_GROUNDWORK_PLAN.md`, `NPC_NAMES_ASK_ABOUT_PLAN.md`,
`NPC_GIVE_TAKEAWAY_VISUALIZER_PLAN.md`,
`NPC_TAKEAWAY_BURNOUT_PLAN.md`). Anchors below are written against
`receive_item_from_player()` and `is_giveable()` as the burnout plan and
the original Give plan left them, respectively.

No `InteractionSystem.gd` changes this pass — Give's prompt/dispatch
already works generically off `NPCItemUser.is_giveable()`, so widening
that one classifier is all the Player-subsystem side needs. Fully
contained to NPC subsystem files.

## What this pass changes

Give now accepts `FoodCan` and `WaterBottle` (multi-charge items), not
just single-serving `DishItem`/`FarmProduceItem`. This is exactly the
scenario the per-item marking from the burnout pass was built for: a full
can gets given (transfers one bite, relationship boost, can now has fewer
bites left but isn't destroyed — it stays in the player's hand exactly
like it would after any normal bite, can or bottle). Without a fix, that
same half-full can could be given again to the same NPC for a second
boost. The fix: each item instance tracks **which NPCs have already been
boosted by it** (not a single global flag — the earlier per-item flag
design is replaced here with a per-(item, NPC) record, since re-gifting
the same item to a *different* NPC should still work once for them).

Re-gifting an already-boosted item to the same NPC still transfers
nutrition/hydration — it's still a real feeding action — it just gives
zero additional relationship reward.

**Deliberate scope note:** the same physical can/bottle CAN still boost
several *different* NPCs (one boost each) — only repeat boosts to the
*same* NPC are blocked, matching exactly what was asked. Flagging this
explicitly in case multi-NPC sharing from one item wasn't intended either
— easy to tighten further if so.

---

## 1. `scripts/npc/NPCItemUser.gd` — widen the classifier

**Anchor:** the exact `is_giveable()` function (from the original Give
plan):

```gdscript
## Give (player → NPC) V1 scope: single-serving items only — DishItem and
## FarmProduceItem both resolve fully in one consume_as_food() call, so
## there's no leftover-charge bookkeeping to handle. FoodCan/WaterBottle
## are multi-use (take_bite()/take_drink() are partial) — deliberately
## excluded rather than silently deciding what happens to the remainder.
static func is_giveable(item: Node) -> bool:
	return item is DishItem or item is FarmProduceItem
```

Replace with:

```gdscript
## Give (player → NPC). Reuses the exact same classifiers self-serve
## eating/drinking already uses (is_edible/is_drinkable_bottle), rather
## than re-deriving the logic — this also correctly excludes an
## already-empty can/bottle from being offered as a "gift" for free,
## since both classifiers already require remaining charge.
static func is_giveable(item: Node) -> bool:
	return is_edible(item) or is_drinkable_bottle(item)
```

---

## 2. `scripts/npc/NPC.gd` — per-(item, NPC) boost gating + multi-charge consumption

**Anchor:** the exact `receive_item_from_player()` function (from the
burnout plan):

```gdscript
func receive_item_from_player(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if not NPCItemUser.is_giveable(item):
		return false
	if item.has_meta("npc_gift_used"):
		return false
	item.set_meta("npc_gift_used", true)
	if item is DishItem or item is FarmProduceItem:
		hunger = minf(100.0, hunger + item.consume_as_food())   ## frees the node
	var effective_bonus: float = GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)
	_adjust_relationship("player", effective_bonus)
	gift_saturation = minf(GIFT_SATURATION_MAX, gift_saturation + GIFT_SATURATION_PER_GIFT)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", effective_bonus,
			"received gift (saturation %.2f)" % gift_saturation)
	return true
```

Replace with:

```gdscript
## Give (Part 26 update — multi-charge items). Marking is now per-(item,
## NPC): `npc_gift_recipients` (Array of npc_id strings this exact item
## instance has already boosted). Same can/bottle CAN still boost several
## DIFFERENT NPCs once each — only a repeat boost to the SAME NPC is
## blocked. Meta is written BEFORE any consumption call that might free
## the node (DishItem/FarmProduceItem's consume_as_food() does), so this
## stays safe regardless of item type.
##
## Consumption always happens even on a repeat gift — still real feeding,
## just no relationship reward the second time. Single-serving items
## (Dish/Produce) are destroyed on first give exactly as before, so a
## repeat is structurally impossible for them; the recipient check exists
## mainly for FoodCan/WaterBottle, which persist across multiple gifts.
func receive_item_from_player(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if not NPCItemUser.is_giveable(item):
		return false

	var recipients: Array = item.get_meta("npc_gift_recipients", [])
	var already_boosted: bool = recipients.has(npc_id)
	if not already_boosted:
		recipients.append(npc_id)
		item.set_meta("npc_gift_recipients", recipients)

	if item is DishItem or item is FarmProduceItem:
		hunger = minf(100.0, hunger + item.consume_as_food())   ## frees the node
	elif item.has_method("take_bite"):   ## FoodCan — multi-bite, persists (kept in world, no queue_free even when empty)
		hunger = minf(100.0, hunger + item.take_bite())
	elif item.has_method("take_drink"):   ## WaterBottle — multi-drink, persists
		thirst = minf(100.0, thirst + item.take_drink())
	else:
		return false   ## shouldn't happen given is_giveable() above, but just in case

	if already_boosted:
		if NPCDebug.enabled:
			NPCDebug.log_relationship_event(self, "player", 0.0,
				"re-gift, already boosted by this item — fed only, no bonus")
		return true

	var effective_bonus: float = GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)
	_adjust_relationship("player", effective_bonus)
	gift_saturation = minf(GIFT_SATURATION_MAX, gift_saturation + GIFT_SATURATION_PER_GIFT)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", effective_bonus,
			"received gift (saturation %.2f)" % gift_saturation)
	return true
```

---

## 3. Documentation updates (required — do not skip)

### `docs/systems/npc/README.md`

**3a.** In the **Give / Takeaway** section, find the Give paragraph:

```
**Give.** Player holds a single-serving food item (`DishItem` or
`FarmProduceItem` — see `NPCItemUser.is_giveable()`) and walks up to an
NPC: `[E] Give <item> to <name>` appears (mirrors the Basket/Cooking Pot
held-item prompt pattern in `InteractionSystem.gd` exactly). E consumes
the item into the NPC's hunger immediately
(`NPC.receive_item_from_player()`) and applies a flat +15 relationship
bonus (scaled by Sociability like everything else, via
`_adjust_relationship()`). Deliberately single-serving only —
`FoodCan`/`WaterBottle` are multi-charge items and what happens to a
partially-given can/bottle is a real open question, not silently decided
here.
```

Replace with:

```
**Give.** Player holds any giveable item — `DishItem`, `FarmProduceItem`,
`FoodCan`, or `WaterBottle` (`NPCItemUser.is_giveable()`, reuses the same
`is_edible()`/`is_drinkable_bottle()` classifiers self-serve
eating/drinking already use) — and walks up to an NPC: `[E] Give <item>
to <name>` appears (mirrors the Basket/Cooking Pot held-item prompt
pattern in `InteractionSystem.gd` exactly). E transfers nutrition/
hydration into the NPC immediately (`NPC.receive_item_from_player()`).
Single-serving items (Dish/Produce) are fully consumed and destroyed, one
bite/drink at a time for cans/bottles (mirrors self-serve
`NPCItemUser.eat_held_step()` exactly) — a can/bottle persists in the
player's hand across multiple gifts, getting progressively emptier, same
as it would from repeated self-use.

A successful gift applies a +15 relationship bonus (scaled by Sociability
like everything else, via `_adjust_relationship()`, and by gift
burnout — see below). **Per-(item, NPC) boost gating:** each item
instance tracks which NPCs it's already boosted
(`item.get_meta("npc_gift_recipients")`, an Array of `npc_id`s) — giving
the same can/bottle to the same NPC again still feeds them but grants NO
further relationship reward. The same item CAN still boost several
different NPCs once each — only a repeat to the same NPC is blocked. This
was unreachable for single-serving items before (destroyed on first use)
but matters now that cans/bottles persist across gifts.
```

**3b.** In the same section's Future Work list, find:

```
- Multi-use item Give (FoodCan/WaterBottle) — needs a decision on what
  happens to the remaining charge. The gift-marking and burnout
  infrastructure is already in place for whenever this lands.
```

Replace with:

```
- ~~Multi-use item Give (FoodCan/WaterBottle)~~ — done (Aug 2026): one
  bite/drink per gift, item persists across gifts exactly like self-serve
  consumption, per-(item, NPC) recipient tracking prevents repeat boosts
  to the same NPC from the same item.
```

**3c.** In the **Testing Checklist**, add after the items added by the
burnout plan (renumber as needed):

```
16. Give an NPC a full FoodCan or WaterBottle — confirm the relationship
    boost lands, the item stays in your hand afterward (not destroyed),
    and it now shows fewer bites/less fill remaining. Give the SAME
    item to the SAME NPC again — confirm hunger/thirst still rises but
    NO additional relationship boost (check F7 debug dump — delta should
    log as 0.0/"no bonus"). Give that same partially-used item to a
    DIFFERENT NPC — confirm THAT NPC gets a normal +15-scaled boost (once).
```

### `HANDOVER.md`

Add a new top section once this plan has actually been executed:

```markdown
# Handover — NPC Give: Multi-Charge Items (Aug 2026)

## What changed this session

- **NPCItemUser.gd**: `is_giveable()` widened to reuse `is_edible()`/
  `is_drinkable_bottle()` directly — now covers FoodCan and WaterBottle
  in addition to DishItem/FarmProduceItem.
- **NPC.gd**: `receive_item_from_player()` rewritten — per-(item, NPC)
  recipient tracking (`npc_gift_recipients` meta, an Array of npc_ids)
  replaces the earlier single global `npc_gift_used` flag. FoodCan/
  WaterBottle now take one bite/drink per gift and persist in the
  player's hand across multiple gifts (mirrors
  `NPCItemUser.eat_held_step()`'s exact per-type branching). A repeat
  gift of the same item to the same NPC still feeds them, just grants no
  further relationship reward; the same item can still boost different
  NPCs once each.
- Docs: `docs/systems/npc/README.md` — Give paragraph rewritten, Future
  Work item marked done, new Testing Checklist item.

## Files Modified
- `scripts/npc/NPCItemUser.gd`
- `scripts/npc/NPC.gd`
- `docs/systems/npc/README.md`

## Verification Checklist (for Brannon's in-editor test)
See `docs/systems/npc/README.md` Testing Checklist item 16.
```

---

## Summary of files touched

| File | Change |
|---|---|
| `scripts/npc/NPCItemUser.gd` | `is_giveable()` widened to FoodCan/WaterBottle |
| `scripts/npc/NPC.gd` | `receive_item_from_player()` — multi-charge consumption + per-(item, NPC) recipient gating |
| `docs/systems/npc/README.md` | Give paragraph rewrite, Future Work update, Testing Checklist addition |
| `HANDOVER.md` | New session entry (add after execution, wording above) |

No `InteractionSystem.gd`, `NPCDebug.gd`, `NPCBrain.gd`, `NPCTalkMenuUI.gd`,
`AdminMenu.gd`, or `MainWorld.gd` changes in this pass.
