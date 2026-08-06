# Per-Plant Harvest Jobs + NPC Action Log (Aug 2026)

**Files:** `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`.

**Note on what this assumes exists:** several anchors below (Give/
Takeaway/Snatch functions, `RelaxActivity`, `PassedOutActivity`'s current
form) come from plans already discussed but not yet confirmed applied.
Written against those specs as the source of truth. If the live file
looks different, adjust the anchor, not the intent.

---

## Part A — Harvest: one job per plant, not per tray

Currently `JobBoard` posts one job per tray (`"harvest_%d" % tray.get_instance_id()`)
and `_complete()` harvests every ready plant in it at once. Changing to
one job per ready plant — a 2x1 tray with both cells ready becomes two
independent jobs, separately claimable (even by two different NPCs at
once).

### `scripts/npc/JobBoard.gd`

**Anchor:**

```gdscript
func _scan_harvest(seen: Dictionary) -> void:
	for tray: Node in get_tree().get_nodes_in_group("farming_tray"):
		if not is_instance_valid(tray) or not ("plant_refs" in tray):
			continue
		var any_ready: bool = false
		for plant in tray.plant_refs:
			if plant != null and is_instance_valid(plant) and plant.is_ready():
				any_ready = true
				break
		if any_ready:
			_mark(seen, "harvest_%d" % tray.get_instance_id(),
				"HARVEST", tray, null)
```

Replace with:

```gdscript
func _scan_harvest(seen: Dictionary) -> void:
	for tray: Node in get_tree().get_nodes_in_group("farming_tray"):
		if not is_instance_valid(tray) or not ("plant_refs" in tray):
			continue
		for plant in tray.plant_refs:
			if plant != null and is_instance_valid(plant) and plant.is_ready():
				## One job per READY PLANT now, not one per tray — a 2x1
				## tray with both cells ready posts two independent jobs.
				## target is the plant itself.
				_mark(seen, "harvest_%d" % plant.get_instance_id(),
					"HARVEST", plant, null)
```

### `scripts/npc/NPCBrain.gd` — `_complete()`

**Anchor:**

```gdscript
			"HARVEST":
				for plant in target.plant_refs:
					if plant != null and is_instance_valid(plant) and plant.is_ready():
						plant.harvest()   ## spawns real produce, clears cell
				NotificationManager.notify(UIKit.Domain.NEUTRAL,
					NotificationManager.Severity.INFO,
					"%s harvested the crops" % npc.npc_name)
```

Replace with:

```gdscript
			"HARVEST":
				## target IS the plant now (Part 31 — one job per plant,
				## not per tray).
				if target != null and is_instance_valid(target) and target.has_method("is_ready") and target.is_ready():
					target.harvest()   ## spawns real produce, clears cell
				NotificationManager.notify(UIKit.Domain.NEUTRAL,
					NotificationManager.Severity.INFO,
					"%s harvested the crops" % npc.npc_name)
				npc.log_action("Job (Harvest)")
```

(The `npc.log_action(...)` line here is also Part B/C below — included
now since this anchor is being touched anyway.)

Everything else — claiming, travel, work-timer, `still_valid()` — needs
no changes; they already treat `target` generically as "the Node3D this
job is about."

---

## Part B — Action Log: data model

Per-NPC (not a shared global feed like `NotificationManager`) — each
NPC's own E-panel shows only their own log.

### `scripts/npc/NPC.gd`

**Anchor:** anywhere near the top of the Relationships section (or any
consistent spot).

Insert:

```gdscript
# ─── Action Log (Aug 2026) ──────────────────────────────────────────────────
## Player-facing, curated log of MEANINGFUL things this NPC has done —
## deliberately NOT a record of routine activity switching (Wander→Eat→
## Wander etc.). Mirrors NotificationManager/NotificationHistoryUI's
## pattern (capped array + change signal + live-rebuilding scroll panel)
## but scoped to one NPC instead of a global feed.
signal action_logged

const ACTION_LOG_MAX_LEN: int = 100
const CONTAGION_LOG_THRESHOLD: float = 2.0   ## cumulative %, since the last log entry

var _action_log: Array[Dictionary] = []
var _contagion_log_accum: float = 0.0
var _last_irritability_label: String = ""
var _last_player_relationship_label: String = "Neutral"

## Single append point for every entry. Both timestamp flavors are
## captured now, not derived later: `fired_at_msec` for the live "Xs ago"
## display, `game_time` (a snapshot of the HUD clock string) for the
## hover tooltip.
func log_action(text: String) -> void:
	_action_log.append({
		"text": text,
		"fired_at_msec": Time.get_ticks_msec(),
		"game_time": _current_game_time_string(),
	})
	if _action_log.size() > ACTION_LOG_MAX_LEN:
		_action_log.pop_front()
	action_logged.emit()

## Newest-first, matching NotificationManager.get_history()'s convention.
func get_action_log() -> Array[Dictionary]:
	var out: Array[Dictionary] = _action_log.duplicate()
	out.reverse()
	return out

func _current_game_time_string() -> String:
	var stats: Node = get_tree().get_first_node_in_group("player_stats")
	if stats != null and stats.has_method("get_time_display"):
		return stats.get_time_display()
	return "?"

## Contagion's own per-tick delta (_mood_contagion_delta, already tracked
## separately inside _tick_mood()) accumulates here; only logged once the
## cumulative drift since the last log crosses ±2%, so ambient contagion
## doesn't spam an entry every 5 seconds.
func _check_contagion_log() -> void:
	_contagion_log_accum += _mood_contagion_delta
	if absf(_contagion_log_accum) >= CONTAGION_LOG_THRESHOLD:
		var verb: String = "rose" if _contagion_log_accum > 0.0 else "fell"
		log_action("Mood %s %+.0f%% (Mood Contagion)" % [verb, _contagion_log_accum])
		_contagion_log_accum = 0.0

## Band-crossing detection — logs only on the actual crossing, not every
## tick the band is held. Irritability (Grumpy/Frustrated/Mad/Rage, and
## calming back down) and relationship-with-player
## (Hostile/Cold/Neutral/Friendly/Close) both already have clean labeled
## bands to compare against; mood doesn't (no small fixed set of bands),
## so it's deliberately not included here.
func _check_label_crossings() -> void:
	var irr_label: String = get_irritability_label()
	if irr_label != _last_irritability_label:
		if irr_label != "":
			log_action("Became \"%s\" (irritability)" % irr_label)
		elif _last_irritability_label != "":
			log_action("Calmed down (irritability)")
		_last_irritability_label = irr_label

	var rel_label: String = get_relationship_label("player")
	if rel_label != _last_player_relationship_label:
		log_action("Relationship with you became \"%s\"" % rel_label)
		_last_player_relationship_label = rel_label
```

**Anchor:** inside `_tick_mood_and_irritability(delta)`, right after
`_tick_mood(h)`/`_tick_irritability(h)` run (exact surrounding lines
depend on which prior plans landed — add these two calls somewhere after
both of those and after `_tick_relationships(h)` if present):

```gdscript
	_check_contagion_log()
	_check_label_crossings()
```

### `scripts/npc/NPC.gd` — `_adjust_relationship()` now reports what it did

**Anchor:** the current function:

```gdscript
func _adjust_relationship(target_id: String, delta: float) -> void:
	if target_id == "" or target_id == npc_id:
		return
	var current: float = get_relationship(target_id)
	relationships[target_id] = clampf(
		current + delta * _sociability_trait_mult(), RELATIONSHIP_MIN, RELATIONSHIP_MAX)
```

Replace with:

```gdscript
## Now returns the ACTUAL applied delta (post-Sociability-multiplier,
## post-clamp) — callers that want to show the real number in the action
## log (not the pre-multiplier input) need this; everything that already
## ignores the return value keeps working unchanged.
func _adjust_relationship(target_id: String, delta: float) -> float:
	if target_id == "" or target_id == npc_id:
		return 0.0
	var current: float = get_relationship(target_id)
	var new_value: float = clampf(
		current + delta * _sociability_trait_mult(), RELATIONSHIP_MIN, RELATIONSHIP_MAX)
	relationships[target_id] = new_value
	return new_value - current
```

---

## Part C — Log call sites

### `scripts/npc/NPC.gd` — Give (`on_item_given()`)

**Anchor:** inside `on_item_given(item)`, the block handling a NEW
(non-repeat) gift:

```gdscript
	var effective_bonus: float = GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)
	_adjust_relationship("player", effective_bonus)
	gift_saturation = minf(GIFT_SATURATION_MAX, gift_saturation + GIFT_SATURATION_PER_GIFT)
```

Replace with:

```gdscript
	var effective_bonus: float = GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)
	var applied: float = _adjust_relationship("player", effective_bonus)
	gift_saturation = minf(GIFT_SATURATION_MAX, gift_saturation + GIFT_SATURATION_PER_GIFT)
	log_action("Player gave you %s (%+.1f relationship)" % [item.get_display_name(), applied])
```

For the repeat-gift ("already boosted, no bonus") branch, add a log line
there too:

```gdscript
	if already_boosted:
		if NPCDebug.enabled:
			NPCDebug.log_relationship_event(self, "player", 0.0, "re-gift, already boosted by this item — fed only, no bonus")
		log_action("Player gave you %s (fed only, no relationship change)" % item.get_display_name())
		return
```

### `scripts/npc/NPC.gd` — Takeaway (`on_item_taken_by_player()`)

**Anchor:** the need-triggered branch:

```gdscript
	if not was_need_triggered:
		return
	_adjust_relationship("player", -TAKEAWAY_RELATIONSHIP_PENALTY)
```

Replace with:

```gdscript
	if not was_need_triggered:
		return   ## job material etc. — no relationship consequence, and deliberately not logged either (not meaningful enough)
	var applied: float = _adjust_relationship("player", -TAKEAWAY_RELATIONSHIP_PENALTY)
	log_action("Player took %s from you (%+.1f relationship)" % [item.get_display_name(), applied])
```

(`item` must still be in scope at this point — it's the local variable
captured before `held_item` was nulled earlier in this same function; if
your version already moved past that point, capture the display name
before clearing `held_item` instead.)

### `scripts/npc/NPC.gd` — Relax interruption (`request_job_while_relaxing()`)

**Anchor:**

```gdscript
func request_job_while_relaxing() -> bool:
	_relax_job_request_count += 1
	if _relax_job_request_count <= 1:
		return false
	_adjust_relationship("player", -3.0)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", -3.0, "pulled from relaxing to do a job")
	return true
```

Replace with:

```gdscript
func request_job_while_relaxing() -> bool:
	_relax_job_request_count += 1
	if _relax_job_request_count <= 1:
		return false
	var applied: float = _adjust_relationship("player", -3.0)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", -3.0, "pulled from relaxing to do a job")
	log_action("Player interrupted your relaxation (%+.1f relationship)" % applied)
	return true
```

### `scripts/npc/NPCBrain.gd` — Relax session completed

**Anchor:** `RelaxActivity.exit()`:

```gdscript
	func exit(npc: NPC) -> void:
		if _inner != null:
			_inner.exit(npc)
			_inner = null
```

Replace with:

```gdscript
	func exit(npc: NPC) -> void:
		if _session_elapsed > 0.01:   ## skip logging a session that never actually started
			npc.log_action("Relaxed for %d min" % int(round(_session_elapsed * 60.0)))
		if _inner != null:
			_inner.exit(npc)
			_inner = null
```

### `scripts/npc/NPCBrain.gd` — Pass out / wake

**Anchor:** `PassedOutActivity.enter()`, right after the mood-drop lines
added previously:

```gdscript
		var mood_drop: float = randf_range(1.0, 10.0 * npc.neuroticism_trait_mult())
		npc.mood = clampf(npc.mood - mood_drop, 0.0, 100.0)
		if NPCDebug.enabled:
			NPCDebug.log_mood_event(npc, -mood_drop, "passed out")
```

Add immediately after:

```gdscript
		npc.log_action("Passed out (0 energy)")
```

**Anchor:** `PassedOutActivity.exit()` — add a log call (create this
function if it doesn't exist yet):

```gdscript
	func exit(npc: NPC) -> void:
		npc.log_action("Woke up")
```

### `scripts/npc/NPCBrain.gd` — Snatch success

**Anchor:** `SnatchActivity.tick()`'s success branch:

```gdscript
				if NPCItemUser.snatch_from_player(npc, _player):
					NPCDebug.log_snatch(npc, "success", "grabbed item from player's hands, handing off to consume")
					_handoff = NPCBrain.GivenEatActivity.new() if _is_edible else NPCBrain.GivenDrinkActivity.new()
					_outcome_label = "Snatched!"
					_player = null
					_tracked_item = null
```

Replace with:

```gdscript
				if NPCItemUser.snatch_from_player(npc, _player):
					NPCDebug.log_snatch(npc, "success", "grabbed item from player's hands, handing off to consume")
					npc.log_action("Snatched an item from your hands")
					_handoff = NPCBrain.GivenEatActivity.new() if _is_edible else NPCBrain.GivenDrinkActivity.new()
					_outcome_label = "Snatched!"
					_player = null
					_tracked_item = null
```

(Deliberately not logging aborted/failed snatch attempts or the dropped-
item-chase variant — not meaningful enough on their own to surface,
consistent with "no useless loops.")

---

## Part D — UI: the log dropdown

### `scripts/ui/npc/NPCTalkMenuUI.gd`

**Anchor:** the `PANEL_H` constant:

```gdscript
const PANEL_H: float = 900.0   ## Part 23 — bumped again for the Ask About...
```

Add nearby:

```gdscript
## Action Log (Aug 2026) — extra height the panel grows by when the log
## dropdown is expanded; shrinks back when collapsed. Log area itself
## stays a fixed, modest size (LOG_AREA_H) — the scroll happens inside
## it, the panel doesn't grow to fit unlimited entries.
const LOG_AREA_H: float = 220.0
const LOG_TOGGLE_BUTTON_H: float = 32.0
const LOG_SECTION_H: float = LOG_AREA_H + LOG_TOGGLE_BUTTON_H + 8.0
```

**Anchor:** var declarations block — add:

```gdscript
var _log_expanded: bool = false
var _log_toggle_button: Button = null
var _log_scroll: ScrollContainer = null
var _log_rows_box: VBoxContainer = null
var _log_entries: Array[Dictionary] = []
var _log_time_labels: Array[Label] = []
```

**Anchor:** end of `_build()`, right after the existing:

```gdscript
	_vbox.add_child(UIKit.make_button("Close", close))
```

Insert:

```gdscript

	## Action Log (Aug 2026) — collapsed by default on every fresh open,
	## deliberately not remembered across panel reopens.
	_log_toggle_button = UIKit.make_button("Show Activity Log ▾", _on_log_toggle_pressed)
	_vbox.add_child(_log_toggle_button)

	var log_bg: PanelContainer = PanelContainer.new()
	var log_style: StyleBoxFlat = StyleBoxFlat.new()
	log_style.bg_color     = Color(0.05, 0.05, 0.06, 0.9)
	log_style.border_color = Color(0.30, 0.30, 0.33, 0.85)
	log_style.set_border_width_all(1)
	log_style.set_corner_radius_all(3)
	log_style.content_margin_left   = 6.0
	log_style.content_margin_right  = 6.0
	log_style.content_margin_top    = 6.0
	log_style.content_margin_bottom = 6.0
	log_bg.add_theme_stylebox_override("panel", log_style)
	log_bg.custom_minimum_size = Vector2(0.0, LOG_AREA_H)
	log_bg.visible = false
	_vbox.add_child(log_bg)

	_log_scroll = ScrollContainer.new()
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	log_bg.add_child(_log_scroll)

	_log_rows_box = VBoxContainer.new()
	_log_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_rows_box.add_theme_constant_override("separation", 2)
	_log_scroll.add_child(_log_rows_box)

	if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_action_log"):
		if not _npc.action_logged.is_connected(_rebuild_log_rows):
			_npc.action_logged.connect(_rebuild_log_rows)
	_rebuild_log_rows()
```

**Anchor:** `_process(delta)` (create one if this UI doesn't already have
one — mirrors `NotificationHistoryUI._process()`'s pattern exactly):

```gdscript
func _process(_delta: float) -> void:
	if not visible or not _log_expanded:
		return
	for i: int in range(_log_time_labels.size()):
		if i >= _log_entries.size():
			continue
		_log_time_labels[i].text = _format_log_age(_log_entries[i]["fired_at_msec"] as int)
```

**Anchor:** end of file — new functions:

```gdscript
func _on_log_toggle_pressed() -> void:
	_log_expanded = not _log_expanded
	_log_toggle_button.text = "Hide Activity Log ▴" if _log_expanded else "Show Activity Log ▾"
	## The log_bg panel is the sibling right after the toggle button —
	## found by index rather than a stored reference to keep this
	## function self-contained.
	var log_idx: int = _log_toggle_button.get_index() + 1
	if log_idx < _vbox.get_child_count():
		_vbox.get_child(log_idx).visible = _log_expanded
	_apply_panel_height(PANEL_H + (LOG_SECTION_H if _log_expanded else 0.0))

## Resizes and re-centers the panel — mirrors UIKit.build_centered_panel()'s
## own centering math, since that helper has no public "resize" method.
func _apply_panel_height(height: float) -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(PANEL_W, height)
	_panel.offset_top    = -height * 0.5
	_panel.offset_bottom =  height * 0.5

func _rebuild_log_rows() -> void:
	if _log_rows_box == null:
		return
	for child: Node in _log_rows_box.get_children():
		child.queue_free()
	_log_time_labels.clear()
	_log_entries = _npc.get_action_log() if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_action_log") else []

	if _log_entries.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Nothing notable yet"
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_font_override("font", UIKit.font())
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
		_log_rows_box.add_child(empty_lbl)
		return

	for entry: Dictionary in _log_entries:
		_log_rows_box.add_child(_make_log_row(entry))

func _make_log_row(entry: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = "At %s" % str(entry.get("game_time", "?"))

	var text_lbl: Label = Label.new()
	text_lbl.text = str(entry["text"])
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.add_theme_font_size_override("font_size", 12)
	text_lbl.add_theme_font_override("font", UIKit.font())
	text_lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.90, 0.95))
	row.add_child(text_lbl)

	var time_lbl: Label = Label.new()
	time_lbl.text = _format_log_age(entry["fired_at_msec"] as int)
	time_lbl.custom_minimum_size = Vector2(52.0, 0.0)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_lbl.add_theme_font_size_override("font_size", 11)
	time_lbl.add_theme_font_override("font", UIKit.font())
	time_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72, 0.8))
	row.add_child(time_lbl)
	_log_time_labels.append(time_lbl)

	return row

func _format_log_age(fired_at_msec: int) -> String:
	var elapsed_sec: int = int((Time.get_ticks_msec() - fired_at_msec) / 1000.0)
	if elapsed_sec < 60:
		return "%ds ago" % elapsed_sec
	var elapsed_min: int = int(elapsed_sec / 60.0)
	if elapsed_min < 60:
		return "%dm ago" % elapsed_min
	var elapsed_hr: int = int(elapsed_min / 60.0)
	return "%dh ago" % elapsed_hr
```

**Anchor:** `_teardown()` — add signal disconnect so reopening a
different NPC's panel doesn't leave a stale connection:

```gdscript
func _teardown() -> void:
```

Add near the top of the function body:

```gdscript
	if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_action_log"):
		if _npc.action_logged.is_connected(_rebuild_log_rows):
			_npc.action_logged.disconnect(_rebuild_log_rows)
	_log_expanded = false
```

---

## Documentation

`docs/systems/npc/README.md` — new section, "Action Log": describe
`NPC.log_action()`/`get_action_log()` as the single append point, list
every current log-triggering event (Give, Takeaway, Snatch success,
Relax completion, Job/Harvest completion, pass-out/wake, contagion
threshold, irritability/relationship band crossings), note "Talked to
[NPC]" is an aspirational future entry (no NPC-to-NPC dialogue exists
yet) the log format already supports without changes, and the UI's
grow/shrink panel behavior. Update the per-plant Harvest note in the
Skills & Jobs section.

**Testing Checklist:**

```
37. Harvest a 2x1 (or larger) tray with multiple ready plants — confirm
    it now posts as multiple independent jobs (check F7 job debug dump
    if available) and can be split across two NPCs working simultaneously.
38. Open an NPC's E-panel, press "Show Activity Log" — confirm the panel
    visibly grows taller and the log area appears with correct rows;
    press again — confirm it shrinks back to the original size.
39. Trigger a Give, a Takeaway, a successful Snatch, a completed Relax
    session, and a Harvest job on one NPC — confirm each produces exactly
    one clear, correctly-worded log entry, newest at the top.
40. Leave two NPCs near each other with meaningfully different moods for
    several minutes — confirm a "Mood rose/fell X% (Mood Contagion)"
    entry appears only occasionally (once cumulative drift crosses ±2%),
    not every few seconds.
41. Push a relationship down past a band boundary (F7) — confirm a
    "Relationship with you became "X"" entry appears exactly once at the
    crossing, not repeated every tick while it stays in that band.
42. Scroll through a log with 20+ entries — confirm the scrollbar
    appears and behaves normally, and hovering a row's timestamp shows
    the in-game clock time in a tooltip.
```
