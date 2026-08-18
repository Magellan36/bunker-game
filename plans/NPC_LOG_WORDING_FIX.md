# Fix: Action Log Wording — "you/your" → NPC Name / "the player" (Aug 2026)

**File:** `scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`.

The log is a third-person, objective record for one specific named NPC —
not the NPC speaking to the player. Every "you"/"your" needs to become
either the NPC's own name (when it referred to the NPC) or "the player"
(when it referred to the player). Six lines, each shown with old → new.

**Anchor 1** — `on_item_given()`, new-gift branch:

```gdscript
	log_action("Player gave you %s (%+.1f relationship)" % [item.get_display_name(), applied])
```

Replace with:

```gdscript
	log_action("Player gave %s to %s (%+.1f relationship)" % [item.get_display_name(), npc_name, applied])
```

**Anchor 2** — `on_item_given()`, repeat-gift branch:

```gdscript
		log_action("Player gave you %s (fed only, no relationship change)" % item.get_display_name())
```

Replace with:

```gdscript
		log_action("Player gave %s to %s (fed only, no relationship change)" % [item.get_display_name(), npc_name])
```

**Anchor 3** — `on_item_taken_by_player()`:

```gdscript
	log_action("Player took %s from you (%+.1f relationship)" % [item.get_display_name(), applied])
```

Replace with:

```gdscript
	log_action("Player took %s from %s (%+.1f relationship)" % [item.get_display_name(), npc_name, applied])
```

**Anchor 4** — `request_job_while_relaxing()`:

```gdscript
	log_action("Player interrupted your relaxation (%+.1f relationship)" % applied)
```

Replace with:

```gdscript
	log_action("Player interrupted %s's relaxation (%+.1f relationship)" % [npc_name, applied])
```

**Anchor 5** — `_check_label_crossings()`:

```gdscript
		log_action("Relationship with you became \"%s\"" % rel_label)
```

Replace with:

```gdscript
		log_action("Relationship with the player became \"%s\"" % rel_label)
```

**Anchor 6** — `SnatchActivity.tick()`, success branch (`NPCBrain.gd`):

```gdscript
					npc.log_action("Snatched an item from your hands")
```

Replace with:

```gdscript
					npc.log_action("Snatched an item from the player's hands")
```

No other lines need changes — "Relaxed for X min", "Job (Harvest)",
"Passed out (0 energy)", "Woke up", and the contagion/mood entries never
referred to "you" in the first place (they're implicitly about this NPC,
same as a diary entry doesn't need to keep repeating its own author).
