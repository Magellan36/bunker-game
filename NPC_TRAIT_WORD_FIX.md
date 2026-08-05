# Fix: "Kind" Never Actually Became "Open" (Aug 2026)

**File:** `scripts/npc/NPC.gd` only.

This was agreed on a while back (Sociability's high-band word "Kind"
implies a value judgment; "Open" better captures fast relationship
reactivity in both directions) but the edit never actually landed —
confirmed by reading the live file, still says "Kind."

**Anchor:**

```gdscript
	"sociability": {"low": "Distant",     "mid": "Reserved",      "high": "Kind"},
```

Replace with:

```gdscript
	"sociability": {"low": "Distant",     "mid": "Reserved",      "high": "Open"},
```

Also clean up a stale comment a few lines above it, left over from before
Sociability was actually wired up:

**Anchor:**

```gdscript
## FUTURE WORK — sociability could scale contagion strength (a "how much
## this NPC affects/is affected by others" multiplier), work_ethic could
## scale skill-gain rate or job willingness, neuroticism could scale mood's
```

Replace with:

```gdscript
## FUTURE WORK — sociability is wired (scales relationship-change rate,
## including Give/Takeaway/Snatch — see _sociability_trait_mult()).
## work_ethic could scale skill-gain rate or job willingness, neuroticism could scale mood's
```

No other files need changes — `get_personality_words()`, the E-panel
Personality line, and `NPCDebug` all already read from this dictionary.
