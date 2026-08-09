# Plan (UI thread) — Focus Mode: Hold Ctrl to Show Only the E Target

## Summary
Hold-to-activate (not toggle), matching the request exactly. While `Ctrl`
is held, `InteractPrompt.gd` shows only the one prompt tagged
`"is_e_target": true` by `InteractionSystem.gd`, hiding every other
currently-active prompt. Release `Ctrl` and everything returns to normal
immediately.

Entirely self-contained in `InteractPrompt.gd` (UI-owned, the one shared
floating-prompt renderer every interactable already goes through — no
per-object changes needed). Depends on the companion Player-thread plan
("Shelf E-Priority Fix + Grow Light Priority + Focus Mode's E-Target
Resolution") for the `is_e_target` tag to ever be `true` — but is safe to
apply in either order: entries without the key default to shown (see
below), so applying this plan first just means Focus Mode has no visible
effect yet, not a crash or a blank screen.

**Scope note (per this session):** only the empty-handed case (CASE 2 in
`InteractionSystem._update_prompt()`) is tagged with real
`is_e_target: true/false` values. Held-item prompts (CASE 1 — basket/
cookpot/give-to-NPC/held-item's-own-action) never set the key at all, and
this plan treats a missing key as "always show" — so Focus Mode has no
effect while holding an item; you'll see the same full prompt set with or
without `Ctrl` held. Collapsing CASE 1 down to one true target was
explicitly scoped out this pass (real extra work — mirroring the basket/
cookpot/give-to-NPC nearest-target selection) and can be a follow-up.

Shares `Ctrl` with the held-item "upright" feature by design — this reads
the key via passive per-frame polling (`Input.is_key_pressed`), which
can't be "consumed"/stolen by another handler regardless of how that one
processes the same key, so there's no real conflict to worry about.

## Files modified
- `scripts/ui/hud/InteractPrompt.gd`

---

## Part 1 — Filter `_active` down to the E-target while Ctrl is held

**old_str:**
```
func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()

	# ── No camera — hide everything ──────────────────────────────────────────
	if camera == null:
		for p: PanelContainer in _pool:
			p.visible = false
		return

	# ── Ensure pool is large enough ──────────────────────────────────────────
	while _pool.size() < _active.size():
		var clone: PanelContainer = _template_panel.duplicate() as PanelContainer
		clone.visible = false
		add_child(clone)
		_pool.append(clone)
		_icon_viewports.append(_build_icon_slots(clone))
		_icon_loaded_sig.append(["", "", ""])

	# ── Phase 1: compute each panel's natural position/size/alpha and update
	## its content. `layouts[i]` is null for a hidden entry, else a Dictionary
	## with pos/size/alpha/priority/dist — Aug 2026, split out of the single
	## loop this used to be so overlap avoidance (Phase 2) can see every
	## panel's real size (post-content-update) before any position is final.
	var layouts: Array = []
	for i: int in _active.size():
		var entry: Dictionary  = _active[i]
		var p: PanelContainer  = _pool[i] as PanelContainer
```
**new_str:**
```
func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()

	# ── No camera — hide everything ──────────────────────────────────────────
	if camera == null:
		for p: PanelContainer in _pool:
			p.visible = false
		return

	## Focus Mode (Aug 2026) — hold Ctrl to collapse every prompt down to
	## the single one E would actually trigger right now. Debugging aid
	## for prompt-priority bugs as well as a normal player-facing
	## decluttering option when several prompts compete for attention. A
	## HOLD, not a toggle — release Ctrl and everything returns to normal
	## immediately, no state to reset.
	##
	## Resolution is entirely Player-owned: InteractionSystem tags exactly
	## one CASE-2 (empty-handed) entry per frame with "is_e_target": true,
	## every other CASE-2 entry gets "is_e_target": false — see
	## InteractionSystem._resolve_current_e_target()'s header for why that
	## tag can never disagree with what E actually does. This file only
	## reads the tag, it never re-derives priority itself.
	##
	## Entries that never set the key at all (every CASE-1 held-item
	## entry — basket/cookpot/give-to-NPC/held-item's-own-action) default
	## to shown via the `true` fallback below: Focus Mode intentionally
	## has no effect while holding an item this pass (see this plan's
	## header for why).
	var focus_mode: bool = Input.is_key_pressed(KEY_CTRL)
	var display_list: Array = _active
	if focus_mode:
		display_list = _active.filter(func(e: Dictionary) -> bool: return bool(e.get("is_e_target", true)))

	# ── Ensure pool is large enough ──────────────────────────────────────────
	while _pool.size() < display_list.size():
		var clone: PanelContainer = _template_panel.duplicate() as PanelContainer
		clone.visible = false
		add_child(clone)
		_pool.append(clone)
		_icon_viewports.append(_build_icon_slots(clone))
		_icon_loaded_sig.append(["", "", ""])

	# ── Phase 1: compute each panel's natural position/size/alpha and update
	## its content. `layouts[i]` is null for a hidden entry, else a Dictionary
	## with pos/size/alpha/priority/dist — Aug 2026, split out of the single
	## loop this used to be so overlap avoidance (Phase 2) can see every
	## panel's real size (post-content-update) before any position is final.
	var layouts: Array = []
	for i: int in display_list.size():
		var entry: Dictionary  = display_list[i]
		var p: PanelContainer  = _pool[i] as PanelContainer
```

## Part 2 — Phase 3 (apply positions) and surplus-hiding use `display_list`

**old_str:**
```
	## Phase 3: apply final positions.
	for i: int in _active.size():
		var p: PanelContainer = _pool[i] as PanelContainer
		var lay: Variant = layouts[i]
		if lay == null:
			p.visible = false
			continue
		var d: Dictionary = lay as Dictionary
		p.position = d["pos"]
		p.modulate = Color(1.0, 1.0, 1.0, float(d["alpha"]))
		p.visible  = true

	# ── Hide surplus pool panels ──────────────────────────────────────────────
	for i: int in range(_active.size(), _pool.size()):
		var p: PanelContainer = _pool[i] as PanelContainer
		if p.visible:
			p.visible = false
```
**new_str:**
```
	## Phase 3: apply final positions.
	for i: int in display_list.size():
		var p: PanelContainer = _pool[i] as PanelContainer
		var lay: Variant = layouts[i]
		if lay == null:
			p.visible = false
			continue
		var d: Dictionary = lay as Dictionary
		p.position = d["pos"]
		p.modulate = Color(1.0, 1.0, 1.0, float(d["alpha"]))
		p.visible  = true

	# ── Hide surplus pool panels ──────────────────────────────────────────────
	for i: int in range(display_list.size(), _pool.size()):
		var p: PanelContainer = _pool[i] as PanelContainer
		if p.visible:
			p.visible = false
```

## Part 3 — Update the `set_prompts()` contract doc comment

Documents the new `is_e_target` key for whoever writes the next entry
producer.

**old_str:**
```
## Primary API — call every frame from InteractionSystem._update_prompt().
## Pass an Array of { "text": String, "world_pos": Vector3, "dist": float,
## "icons": Array (optional, up to 3 entries, each a descriptor Dictionary
## or null) }. Pass [] to hide all panels.
func set_prompts(new_entries: Array) -> void:
```
**new_str:**
```
## Primary API — call every frame from InteractionSystem._update_prompt().
## Pass an Array of { "text": String, "world_pos": Vector3, "dist": float,
## "icons": Array (optional, up to 3 entries, each a descriptor Dictionary
## or null), "is_e_target": bool (optional, Aug 2026 — Focus Mode: true
## for the one entry E would actually trigger right now, false for other
## empty-handed candidates, omitted entirely for held-item entries that
## haven't opted into Focus Mode filtering yet — a missing key defaults
## to shown) }. Pass [] to hide all panels.
func set_prompts(new_entries: Array) -> void:
```

---

## Verification checklist
1. Empty-handed, multiple prompts visible at once (e.g. a shelf + a
   nearby pickup item) — hold `Ctrl`: only one prompt remains, the
   others vanish immediately. Release `Ctrl`: all return immediately.
2. Empty-handed, only prompts that E can't actually act on nearby (e.g.
   only a "pickup"-only item, no interactable) — hold `Ctrl`: confirm all
   prompts disappear (correct — nothing is a real E-target), not that one
   is arbitrarily kept.
3. Holding an item near a shelf (CASE 1) — hold `Ctrl`: confirm prompts
   look identical to `Ctrl` released (no filtering yet, per this pass's
   scope).
4. Confirm no console errors when `_active` is empty and `Ctrl` is held
   (empty `.filter()` on an empty array is a no-op, but worth a quick
   sanity check).
5. Combine with the companion Player-thread plan's checklist items 1–5
   for the full end-to-end verification (shelf-vs-closer-object,
   grow-light-vs-tray, both confirmed under Focus Mode too).

## Documentation updates

### `docs/systems/ui/README.md` — new section
Insert as a new section (e.g. after "Storage UI Icon + Row Label
Redesign"):

```markdown
## Focus Mode (Aug 2026)
Hold `Ctrl` to collapse every active interaction prompt down to the one
`E` would actually trigger right now — a hold, not a toggle. Built as a
debugging aid for prompt-priority bugs (the shelf-unconditional-priority
bug and the grow-light-vs-tray issue were both diagnosed and fixed using
this) that's also just a useful player-facing decluttering option when
several prompts compete for attention near each other.

Entirely a rendering concern in `InteractPrompt.gd` — it filters
`_active` down to whichever entry carries `"is_e_target": true` while
`Ctrl` is held. Resolution of WHICH entry that is stays entirely
Player-owned, in `InteractionSystem._resolve_current_e_target()` (a
read-only peek that mirrors the actual E-handler's priority chain
exactly, so the two can never disagree) — `InteractPrompt.gd` never
re-derives priority itself, it only reads the tag.

**Scope (this pass):** only empty-handed prompts (CASE 2) are tagged
with a real `true`/`false`. Held-item prompts (CASE 1) never set the
key, and a missing key defaults to shown — so Focus Mode currently has
no visible effect while holding an item. Collapsing CASE 1's basket/
cookpot/give-to-NPC multi-target prompts down to one true target is a
reasonable future pass, scoped out here since it requires mirroring each
of those three's own nearest-target selection logic, not just reading a
tag.

Shares the `Ctrl` key with the held-item "upright" feature by design —
this reads the key via passive per-frame `Input.is_key_pressed()`
polling rather than consuming an input event, so the two can't
functionally conflict regardless of how the other one is implemented.
```

### `docs/systems/ui/README.md` — Public API note
Add a line near the existing `InteractPrompt`/`set_prompts()` description
(if the Public API list documents it separately from the code comment)
pointing to the new "Focus Mode" section — skip this if the README
doesn't currently describe `set_prompts()`'s shape at all (some files are
better documented in-code only; check before adding a redundant entry).

### `HANDOVER.md` — new top section
```markdown
# Handover — Focus Mode (Hold Ctrl) for Interaction Prompts (Aug 2026)

## What changed this session
Added Focus Mode: holding `Ctrl` collapses every active interaction
prompt down to the single one `E` would actually trigger, filtering
`InteractPrompt.gd`'s `_active` list by a new `is_e_target` tag. Built
primarily as a debugging tool — used it to find and fix two real bugs in
`InteractionSystem.gd` (separate hand-off plan, Player thread): shelving
was winning `E` unconditionally over genuinely closer interactables, and
grow lights were unreachable because their tray sits directly beneath
them and always won on raw distance. Both fixed there; this prompt-side
change is purely rendering, no priority logic lives here.

Empty-handed only this pass — held-item prompts (baskets, cooking pots,
give-to-NPC, etc.) aren't filtered yet, by design (see
`docs/systems/ui/README.md`'s "Focus Mode" section for the reasoning).

### Files modified
- `scripts/ui/hud/InteractPrompt.gd` — Ctrl polling + `_active` filtering
  in `_process()`; `set_prompts()` doc comment updated for the new
  `is_e_target` key.
- (Companion Player-thread plan, applied separately) —
  `scripts/player/InteractionSystem.gd`: shelf E-priority fairness fix,
  grow-light-over-tray priority, new `_resolve_current_e_target()`.
- `docs/systems/ui/README.md` — new "Focus Mode" section.

### Verification checklist
(see `FOCUS_MODE_PROMPT_FILTER_PLAN.md` for the full checklist)
---
---
```
