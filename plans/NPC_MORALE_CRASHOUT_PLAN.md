# NPC morale, relationships & crash-outs — design plan (Sep 2026)

Status: **phases 1–5 implemented (Sep 2026)**. Player treatment of residents (held Bandage/Splint/Antibiotics → `NPC.receive_treatment`) and laziness/harsh-leadership payoffs are in. Remaining: combat hook-up (attacks, killing = game over), rescue events. It
comes from Brannon's brief (2026-09-28) plus an audit of the current code.

## The brief, in one paragraph

Mood and relationships are the point of the game, not decoration. Over a
playthrough the bunker's *conditions* (light, power, water quality, food
quality...) slowly push each resident's mood up or down, at rates set by
their traits. When mood gets low enough, a resident may **crash out**. What
that looks like depends on their **relationships**. With a bad relationship
(to the player or another resident) they turn angry: sabotage, hurting
someone, eventually attacking. With a good relationship to the player
they go into overdrive to fix things, or break down alone without hurting
anyone. How the player treats people over the whole game decides whether
the end-game collapse is survivable. Every change must be visible and
explained in the resident's activity log, readable by a new player.

## Audit: where the current code stands

| Area | Today | Gap |
|---|---|---|
| Mood target | `82 − needs shortfall + thoughts.total()` | Driven mostly by hunger/thirst/energy. Bunker conditions (light, power, water/food quality) aren't inputs. |
| Mood speed | moves 4 pts/game-hour toward target | Far too fast. It can go from content to miserable in well under a game day. |
| Random drift | ±1/h × neuroticism, every tick | Arbitrary noise. Remove it. |
| Contagion | pulls toward nearby residents' mood | Keep, but slow it down. |
| Thoughts (moodlets) | meals, sleep, chats, gifts, clutter, pain, loneliness | A good base for **short-term feelings**. They shouldn't be what crashes someone out. |
| Traits | resilience, sociability, work ethic, neuroticism, optimism | Only scale mood recovery and drift. They should scale sensitivity to each condition. |
| Relationships | −100..100; from chats, gifts, snatching, proximity | Few player verbs. No memory of *why*. Changes aren't all logged. |
| Crash-out | — | Doesn't exist. |
| Log | some mood/label crossings | Needs every change, with the reason and amount, in plain words. |

## Proposed model

### 1. Two layers of mood

- **Morale (slow).** The long-term state of mind. It moves by fractions of a
  point per game hour and follows **sustained conditions** (see 2). A bad
  day dents it and a bad week breaks it. **Crash-outs read morale only.**
- **Feelings (fast).** Today's thoughts (hot meal, bad chat, slept on the
  floor). They colour dialogue and small choices, and repeated feelings feed
  morale slowly: many cold-can days lower morale, one can doesn't.
- The displayed "Mood" = morale + a small, capped share of feelings. The
  panel shows both in words ("Holding up, but worn down by the dark").

### 2. Bunker conditions: what actually drives morale

A per-resident `NPCConditions` component samples every game hour and keeps
**slow rolling averages** (roughly 1–3 game days) of:

| Condition | Source |
|---|---|
| Light | light level where they spend their time (sustained darkness hurts) |
| Power | outages and brownouts they lived through |
| Water | quality of what they drank (WaterQuality) |
| Food | quality of what they ate (fresh > hot meal > can > spoiled/none) |
| Rest | bed vs chair vs floor, hours slept |
| Space | beds per resident, clutter, cleanliness |
| Safety | injuries, deaths in the bunker, threats |
| Company | good vs bad interactions, loneliness |

Each condition has a **trait-weighted sensitivity**. Neurotic residents feel
darkness more, resilient ones everything less, optimists recover faster.
Morale drifts toward the weighted sum. It rises again when conditions
improve, so a player who fixes things sees recovery.

### 3. Relationships with memory

- Every change is an **event** with a reason, amount and time: "You gave me
  water when I was parched (+6)", "You took my food (−8)". Significant ones
  are kept as memories (debts and grudges) and decay slowly.
- **Player verbs** needed to make it feel fair (to be designed together):
  gifts, answering requests, fair vs overbearing commands, sharing scarce
  food/water, keeping promises, insults/praise in dialogue, violence (with
  combat).
- **Resident-to-resident**: chats (existing), snatching (existing), fights,
  helping, rivalry over beds and food, and shared grievances ("we both hate
  how the player treats us"). This enables two residents ganging up.

### 4. Crash-out

Checked about once per game day per resident, only when **morale** is below
a threshold. The chance scales with how far below it is, and with
neuroticism and low resilience. The outcome depends on relationships:

| Morale low + … | Outcome |
|---|---|
| Hostile toward someone (player or resident) | **Hostile crash-out**: shouting, sabotage (break a device, spill water, hoard food). Later, with combat, attacking that person. Two hostile residents who share a target may team up. |
| Good relationship with the player | **Overdrive**: fixes the causes (refuel, clean, cook), extra helpful, pushes past tiredness, then collapses exhausted. |
| Neither | **Breakdown alone**: freaks out, refuses work for a while, hides in a corner. Harmless, but one less pair of hands. |

A crash-out is an episode (hours) with a clear start and end, and it
leaves a lasting memory. Other residents react to it too (fear, sympathy),
which feeds their own relationships and morale.

### 5. Transparency (the new-player test)

- **Activity log:** every morale shift ("Morale ↓ — third day without
  working lights"), relationship event ("You shared your meal +5"), and
  crash-out start/end with its cause.
- **Resident panel:** a morale trend arrow, top 3 reasons, and each
  relationship's recent history.
- **Warning signs** before a crash-out: barks, body language (the lean and
  sitting animations help here), and dialogue.

### 6. Dependencies

- **Combat / weapon system** (not built) for the violent end of hostile
  crash-outs. Everything else can ship first, with violence stubbed as
  sabotage/threats.
- Light-level sampling at a position (lighting system).
- Water-quality and food-quality hooks on consumption (most exist).

## Decisions (Brannon, 2026-09-28)

1. First crash-out in a badly run bunker: **3–5 in-game days** (longer for
   resilient residents).
2. Being killed by a resident is a **game over**.
3. Mood and relationship **numbers stay visible**, alongside words and reasons.
4. Crash-outs **can't be talked down**. Like RimWorld mental breaks, they
   run their course.
5. Relationship verbs: delegated to me (below).

## Relationship verbs (proposal)

Principles:
- **Memorable, not grindy.** A few meaningful moments beat spam. Repeating
  the same kind of act gives diminishing returns (gift saturation already
  works this way).
- **Context multiplies.** The same act means more when it matters: water
  for someone parched, food during a shortage, a kind word on their worst day.
- **Negativity bias.** Hurts are remembered longer than kindnesses (bad
  memories decay about 3× slower), so cruelty has lasting consequences.
- **Everything is logged** with its reason and amount, and big moments
  become named memories shown on the panel ("Remembers: you shared your last
  can (+8)").
- Magnitudes: *small* ±0.5–2, *medium* ±3–6, *large* ±8–15, *defining* ±20+.

### Already in the game (kept, routed through the ledger)
| Act | Effect |
|---|---|
| Time spent near them | small +, slow |
| Giving food/water | medium +, **×2 when they're in real need, ×1.5 during a shortage**, diminishing if repeated |
| Taking food from their hands while hungry | medium − |
| Pulling them off a break for a job | small − (existing −3) |

### Care — the strongest positive levers
| Act | Effect |
|---|---|
| Treating their injury or illness (medical system) | large + ("You patched me up") |
| Giving them a bed of their own, or letting them keep it | medium +; **sleeping in their bed yourself** is small − |
| Serving a hot meal you cooked | medium + (more than a can) |
| "Take a rest" when they're exhausted | small + (considerate) |
| Rescuing them: carrying them when passed out, pulling them from danger | defining + |

### Leadership & fairness — how you run the bunker
| Act | Effect |
|---|---|
| **Workload.** Orders are tracked per day. Reasonable orders are neutral; ordering someone who is exhausted, starving or already overworked is small −; a pattern of it builds "you work us to death" | small − each, becomes a memory |
| **Working alongside them.** The player visibly does chores (refuelling, cleaning, farming) near residents | small +, "pulls their weight" |
| **Favouritism.** Feeding or gifting one resident while another goes hungry | small − with the neglected one ("you feed them but not me") |
| **Hoarding.** Carrying or stockpiling food while residents starve | medium − with the hungry residents |
| **Blame.** Sustained bad conditions slowly erode their relationship with the player as the leader. Visible effort to fix things (repairs, restoring power) cancels it | small −/day, with reasons |

### Talk — new dialogue choices (Talk tab)
| Act | Effect |
|---|---|
| **Check in** (once per day) | small +; **medium +** if their mood is low ("you listened") |
| **Encourage / Joke / Complain together** | reception depends on traits and mood: a joke lands with sociable people and falls flat with a miserable neurotic one |
| **Insult / Threaten** | medium to large −; threats add fear (feeds a hostile crash-out *or* compliance) |
| **Promise** to fix what's bothering them (the dark, dirty water, no beds). The promise becomes a tracked task | **kept** within ~2 days: medium +; **broken**: medium −, "you said you'd fix the lights" |
| **Take sides** in a feud between two residents | + with one, − with the other |

### Physical (with the combat system)
| Act | Effect |
|---|---|
| Shoving or pushing past roughly | small − |
| Hitting, pointing a weapon | large −, fear |
| Hurting their friend, in front of them | − for the victim **and** their friends (third-party effect) |
| Defending them from a crashed-out attacker | defining + |

### Between residents (so feuds and alliances emerge)
| Act | Effect |
|---|---|
| Chats (existing, compatibility-based) | ± small |
| Working the same job together | small + |
| Competing for a bed or the last food | small −; the loser remembers |
| Snatching food (existing) | medium − |
| **Third-party effects:** seeing someone help or hurt their friend, or being targeted in a crash-out | ± scaled by how close they are to the victim |
| **Shared grievance:** two residents who both hate the same person bond over it | small + between them; this is how two of them end up ganging up on the player |

### Why these fit the game
- Most verbs grow out of systems that already exist (medical, beds, food,
  jobs, cooking, the talk panel), so they read naturally and cost little
  new UI.
- Leadership verbs make **planning the bunker a relationship act**, which
  ties the two halves of the game together. A player who neglects the
  bunker but treats people kindly still gets blame, softened. A cruel
  player in a great bunker still makes enemies.
- Promises give the player a concrete way to repair things by fixing the
  problem a resident raised, not by grinding gifts.

## Proposed build order

1. `NPCConditions` + morale layer. Retire the random drift and slow the
   pace. Log every morale change. Harness: a "bad bunker" scenario
   (darkness, outages, dirty water) must lower morale over days, not hours.
2. Relationship event ledger + logging. Wire the existing sources through it.
3. Player verbs for relationships (design pass with Brannon).
4. Crash-out state machine with the three non-violent outcomes (hostile =
   sabotage/threats for now).
5. Resident panel: trends, reasons, relationship history.
6. Combat hook-up once the fighting system exists.

## Open questions for Brannon

1. **Timescale:** in a badly run bunker, how many in-game days until the
   first crash-out? (Proposal: 3–5 days, longer for resilient residents.)
2. **Player death:** is being killed by a resident a game over? (Permanent
   death exists on `testing`.)
3. **Numbers vs words:** should the player ever see mood/relationship
   numbers, or only words and trends?
4. **Recovery:** can a crashed-out resident be talked down, and by whom (the
   player, a friend)?
5. **Player verbs:** which actions should exist for building or ruining a
   relationship with a resident?
