# Guidance for HANDOVER.md / PROJECT_SUMMARY.md
**For:** the AI working on `bunker-game`. **From:** a review pass across the current docs system (`PROJECT_SUMMARY.md`, `HANDOVER.md`, `docs/systems/*/README.md`, `architecture.json`) done in a separate planning conversation. Overall verdict up front: this docs system is genuinely well-built and already solves most of what it set out to solve — the items below are refinements, not a redesign.

---

## 1. Action item: wire in the merged philosophy/pillars doc

`GAME_PHILOSOPHY.md` and `DESIGN_PILLARS.MD` at repo root have been merged into a single file (attached separately, replaces both). Please:
1. Delete `GAME_PHILOSOPHY.md` and `DESIGN_PILLARS.MD`, replace with the merged `GAME_PHILOSOPHY.md`.
2. Add one line to `PROJECT_SUMMARY.md` §1: *"For design-philosophy/feature-evaluation guidance (human/design reference only, not part of the standard per-task doc chain), see `GAME_PHILOSOPHY.md`."*

This file is explicitly scoped as a **human/design-reference document** — it says so in its own header. It should not be read for routine engineering tasks, only when evaluating whether a new mechanic fits the game's intended direction.

---

## 2. `HANDOVER.md`'s "Current status" section is regrowing toward the exact problem it already says it wants to avoid

The file states its own policy directly: *"This file stays role/workflow/gotchas only, so it doesn't regrow to its old ~620-line length."* Good instinct, and it clearly worked once (the file is 323 lines now, not 620). But the "Current status" section is already accumulating multi-paragraph session-log entries the same way the original bloat presumably happened — the water system entries alone (Phase 1 groundwork + playtest-feedback pass) run to roughly 60 lines, most of which is also fully duplicated in `docs/systems/water/README.md` (which the entries themselves point to: *"Full detail: `docs/systems/water/README.md`"*).

**Concrete recommendation:** apply the same discipline the file already prescribes for `docs/systems/*/README.md` (a `## History` subsection for genuinely historical detail) to itself. Once an entry's content is fully reflected in the relevant system's README:
- Trim the `HANDOVER.md` entry down to one line + a pointer (e.g. *"Water system Phase 1 + playtest-feedback pass — shipped, see `docs/systems/water/README.md`."*)
- Keep the full narrative only for things genuinely specific to *session handoff* (what's unverified, what Brannon needs to test next) rather than implementation detail that already lives elsewhere.

This isn't purely hypothetical upkeep — a few entries are ready for this trim right now:
- **Docs restructure / headless compile-check tool / `GraphicsSettings` autoload confirmations** — these are now just "how the project works," not current status. Safe to delete entirely rather than trim, since they're not pointing at ongoing work.
- **Expanded-area wall/breaker snap bug** and **zone rename + recolor** — both already say "see `docs/systems/build/README.md`" / imply power system docs; can be trimmed to one-liners now.

---

## 3. Specific duplication: the two open power-system follow-ups exist in two places

`docs/systems/power/README.md`'s "Known tradeoffs" section and `HANDOVER.md`'s "Next up" section both describe, in near-identical detail, the same two open items: `_go_offline_true()`'s zero call sites, and the per-zone "sustained brownout" system never being re-audited for the same orphaned-trigger problem. Right now, if either gets investigated and resolved, there's no guarantee both copies get updated — exactly the "doc drift" class of bug the project's own §0 rule treats as equally serious as a code bug.

**Recommendation:** keep the full detail in `docs/systems/power/README.md` (where it already lives, correctly, alongside the related BROWNOUT/TRIPPED fix it was discovered next to). Trim `HANDOVER.md`'s "Next up" copy to a one-line pointer, the same way it already correctly defers to `PROJECT_SUMMARY.md` §1 for the general roadmap list rather than restating it.

---

## 4. Minor, already self-flagged, just bundling it so it doesn't get lost

`docs/systems/graphics/README.md` already notes: `GraphicsSettings.gd`'s own header comment still says "NOT YET REGISTERED AS AN AUTOLOAD" even though it's been registered since `00938b5`. Already correctly deferred as low-risk/cosmetic — no action needed now, just flagging it here so it's on record as a candidate for whenever that file is next opened for something else, in case it isn't already on a running "opportunistic fixes" list somewhere.

---

## Summary

1. Wire in the merged `GAME_PHILOSOPHY.md` (Section 1) — the one genuinely new addition.
2. Establish (and apply now, to the entries called out above) a pruning rule for `HANDOVER.md`'s "Current status" section, mirroring the `## History`-subsection discipline the file already prescribes for system READMEs.
3. De-duplicate the two open power-system follow-ups between `HANDOVER.md` and `docs/systems/power/README.md` — one canonical copy (power README), one pointer (HANDOVER).
4. No urgent action on item 4 — just keep it on whatever running list already exists.

Nothing here changes the overall structure — `PROJECT_SUMMARY.md` § 0's workflow, `docs/systems/*/README.md`, and `architecture.json` are all working as intended and shouldn't be touched beyond the small `PROJECT_SUMMARY.md` §1 addition in Section 1.
