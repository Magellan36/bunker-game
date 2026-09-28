# NPC morale, relationships & crash-outs — design plan (Sep 2026)

Status: **proposal for review**. Nothing here is implemented yet. It
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
