# Fix: Unqualified NPC.gd Consts Referenced from NPCBrain.gd (Aug 2026)

**File:** `scripts/npc/NPCBrain.gd` only.

`TALK_BASE_SCORE` and `GIVE_TO_FRIEND_BASE_SCORE` are declared on
`NPC.gd`, but `TalkActivity`/`GiveToFriendActivity` are inner classes of
`NPCBrain.gd` — they need the `NPC.` qualifier to see them, same reason
`NPCBrain.EatActivity.new()` needs the `NPCBrain.` prefix when called
from outside that file.

**Anchor:** `TalkActivity.score()`:

```gdscript
	func score(npc: NPC) -> float:
		if not _is_initiator:
			return 0.0   ## the forced partner-side instance is never itself a scoring candidate
		if npc.find_talk_partner() == null:
			return 0.0
		return TALK_BASE_SCORE * npc.get_work_ethic_passive_mult()
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if not _is_initiator:
			return 0.0   ## the forced partner-side instance is never itself a scoring candidate
		if npc.find_talk_partner() == null:
			return 0.0
		return NPC.TALK_BASE_SCORE * npc.get_work_ethic_passive_mult()
```

**Anchor:** `GiveToFriendActivity.score()`:

```gdscript
	func score(npc: NPC) -> float:
		if not npc.has_needy_friend():
			return 0.0
		return GIVE_TO_FRIEND_BASE_SCORE * npc.get_work_ethic_passive_mult()
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if not npc.has_needy_friend():
			return 0.0
		return NPC.GIVE_TO_FRIEND_BASE_SCORE * npc.get_work_ethic_passive_mult()
```

No other lines reference either const, so no other changes needed.
