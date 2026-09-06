# Interaction Prompt Polish

## Intent

World prompts remain compact, immediate, and physically attached to their
targets. This pass brings them into the approved bunker interface language
without converting them into oversized floating action cards.

The shared treatment uses:

- blue-charcoal translucent shells;
- a thin worn-brass border and soft grounded shadow;
- one brief, complete blue acquisition outline when the target changes;
- a short, one-shot appearance bloom rather than a looping animation;
- ivory action copy, brass metadata, and semantic green/amber/red states;
- tactile keyboard/controller glyphs at essentially their existing size.

## Preserved prompt contracts

This is a presentation-layer change. `InteractionSystem` still resolves the
same targets and passes the same dictionaries to `InteractPrompt`.

- E/F/G actions and keyboard/controller glyph switching are unchanged.
- Multi-line and multi-action prompts remain multi-line.
- World projection, distance fading, focus-mode filtering, overlap avoidance,
  prompt pooling, and visibility rules are unchanged.
- Hold interactions retain their distinct key-ring progress treatment.
- Player and NPC jobs continue to share the approved compact job card.
- Existing BBCode supplied by systems such as water quality remains valid.

## Specialized information

Specialized producers continue to own their data. The shared renderer may add
visual hierarchy, but must never reduce a specialized prompt to a generic
action label.

The cooking pot is the reference case. Its prompt still carries:

- exactly three live 3D ingredient preview circles in insertion order;
- empty circles for unfilled slots;
- partial-charge/quantity badges such as `1/2` or `67%`;
- the resolved dish preview name;
- total Filling and any Diversity bonus;
- the active cooking state and elapsed/required cook time;
- the finished-dish action and hydration value when applicable.

The ingredient circles now use a blue-charcoal center, fine blue inner keyline,
worn-brass outer ring, warmer preview light, and a 48 px render target scaled
into the existing 32 px footprint for cleaner small-scale presentation. The
three-circle composition and cached `UPDATE_WHEN_VISIBLE` behavior remain
unchanged.

Future prompt-producing systems should follow the same rule: provide the full
system-specific information through the existing entry, and let the shared
prompt renderer handle scale, chrome, input glyphs, hierarchy, and motion.

## Motion rules

- New target: 120 ms settle with a two-pixel vertical movement.
- Edge feedback: a single 180 ms blue bloom.
- Hold action: blue progress sweep over a dark track.
- No idle bouncing, scanning line, continuous spin, or universal pulsing.
- Persistent animation should remain reserved for genuine changing state.

## Verification

Run:

```text
godot --headless --path . --script res://tools/tests/interaction_prompt_polish_smoke.gd
```

The smoke test verifies the compact scale, acquisition flash, semantic state
formatting, and the cooking pot's three-slot descriptor/quantity contract.
