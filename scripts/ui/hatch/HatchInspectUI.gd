extends "res://scripts/ui/common/BunkerDeviceInspector.gd"
## View/controller only. SurfaceHatch owns expeditions, forecasts and
## reports; this panel reads them and calls SurfaceHatch.launch().
## Ordinary device inspector: right rail, world visible, walk-away close.

const T := preload("res://scripts/world/hatch/ExpeditionTables.gd")
const R := preload("res://scripts/world/hatch/ExpeditionResolver.gd")
const REPORTS_SHOWN: int = 3

var _hatch: Node = null
var _topside: PanelContainer
var _sites: PanelContainer
var _active_box: VBoxContainer
var _who: OptionButton
var _where: OptionButton
var _approach: OptionButton
var _forecast: Label
var _approach_hint: Label
var _block_hint: Label
var _reports_box: VBoxContainer
var _send_btn: Button
var _active_sig: String = ""
var _options_sig: String = ""
var _reports_sig: String = ""

func _build_content() -> void:
	refresh_interval = 0.5
	_topside = W.status(_statuses, "Topside")
	_sites = W.status(_statuses, "Sites")
	W.heading(_details, "ActiveHeading", "TOPSIDE NOW")
	_active_box = W.column(_details, "Active", 4)
	W.heading(_details, "PlanHeading", "PLAN A RUN")
	W.label(_details, "WhoCaption", "Who goes", 14, "secondary")
	_who = W.option(_details, "Who")
	W.label(_details, "WhereCaption", "Where", 14, "secondary")
	_where = W.option(_details, "Where")
	W.label(_details, "ApproachCaption", "Approach", 14, "secondary")
	_approach = W.option(_details, "Approach")
	_approach_hint = W.label(_details, "ApproachHint", "", 14, "secondary")
	_forecast = W.label(_details, "Forecast", "", 16)
	_block_hint = W.label(_details, "BlockHint", "", 14, "warning")
	W.heading(_details, "ReportsHeading", "REPORTS")
	_reports_box = W.column(_details, "Reports", 8)
	_send_btn = W.button(_footer, "Send", "SEND TOPSIDE", _on_send_pressed, "", true)
	for option: OptionButton in [_who, _where, _approach]:
		option.item_selected.connect(_on_option_changed)

func open(hatch: Node) -> void:
	if not is_instance_valid(hatch):
		return
	_hatch = hatch
	_options_sig = ""
	_active_sig = ""
	_reports_sig = ""
	_open_device("Surface hatch", "SURFACE", "", hatch as Node3D)

func _refresh_data() -> void:
	if not is_instance_valid(_hatch) or _hatch.is_queued_for_deletion():
		close()
		return
	var active: Array = _hatch.get("active")
	W.set_status(_topside, "%d topside" % active.size() if not active.is_empty() else "Hatch sealed",
		"warning" if not active.is_empty() else "success")
	W.set_status(_sites, "%d sites known" % _hatch.call("get_available_destinations").size(), "secondary")
	_rebuild_options_if_changed()
	_refresh_active(active)
	_refresh_forecast()
	_refresh_reports()

# ─── Options ──────────────────────────────────────────────────────────────────
func _rebuild_options_if_changed() -> void:
	var candidates: Array[Dictionary] = _hatch.call("get_candidates")
	var dests: Array[String] = _hatch.call("get_available_destinations")
	var parts: PackedStringArray = []
	for c: Dictionary in candidates:
		parts.append("%s:%s" % [c["npc"].get("npc_id"), c["reason"]])
	parts.append("|" + ",".join(dests))
	var sig: String = ";".join(parts)
	if sig == _options_sig:
		return
	_options_sig = sig

	var keep_who: String = _selected_meta(_who)
	var keep_where: String = _selected_meta(_where)
	var keep_approach: String = _selected_meta(_approach)
	_who.clear()
	for c: Dictionary in candidates:
		var text: String = String(c["name"])
		if String(c["reason"]) != "":
			text += " — " + String(c["reason"])
		_who.add_item(text)
		var idx: int = _who.item_count - 1
		_who.set_item_metadata(idx, String(c["npc"].get("npc_id")))
		_who.set_item_disabled(idx, String(c["reason"]) != "")
	_where.clear()
	for id: String in dests:
		_where.add_item(String(T.DESTINATIONS[id]["name"]))
		_where.set_item_metadata(_where.item_count - 1, id)
	if _approach.item_count == 0:
		for id: String in T.APPROACH_ORDER:
			_approach.add_item(String(T.APPROACHES[id]["name"]))
			_approach.set_item_metadata(_approach.item_count - 1, id)
	_select_meta(_who, keep_who, true)
	_select_meta(_where, keep_where, false)
	_select_meta(_approach, keep_approach if keep_approach != "" else "balanced", false)

func _selected_meta(option: OptionButton) -> String:
	if option.item_count == 0 or option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))

func _select_meta(option: OptionButton, meta: String, skip_disabled: bool) -> void:
	if option.item_count == 0:
		return
	for i: int in option.item_count:
		if String(option.get_item_metadata(i)) == meta and not (skip_disabled and option.is_item_disabled(i)):
			option.select(i)
			return
	for i: int in option.item_count:
		if not (skip_disabled and option.is_item_disabled(i)):
			option.select(i)
			return
	option.select(-1)

func _selected_npc() -> Node:
	var id: String = _selected_meta(_who)
	if id == "" or _who.is_item_disabled(_who.selected):
		return null
	for c: Dictionary in _hatch.call("get_candidates"):
		if String(c["npc"].get("npc_id")) == id:
			return c["npc"]
	return null

func _on_option_changed(_index: int) -> void:
	_refresh_forecast()

# ─── Sections ─────────────────────────────────────────────────────────────────
func _refresh_active(active: Array) -> void:
	var now: float = NPCClock.now()
	var parts: PackedStringArray = []
	for rec: Dictionary in active:
		parts.append("%s:%d" % [rec["id"], int(float(rec["due_h"]) - now)])
	var sig: String = ",".join(parts)
	if sig == _active_sig:
		return
	_active_sig = sig
	for child: Node in _active_box.get_children():
		child.queue_free()
	if active.is_empty():
		W.label(_active_box, "None", "Nobody is outside.", 15, "secondary")
		return
	for rec: Dictionary in active:
		var dest_name: String = String(T.DESTINATIONS[rec["dest"]]["name"])
		var left: float = float(rec["due_h"]) - now
		var when: String = "due back in about %dh" % maxi(1, int(ceil(left))) if left > 0.0 \
			else "OVERDUE by %dh" % maxi(1, int(floor(-left)))
		W.label(_active_box, "Row", "%s — %s (%s), %s" % [rec["npc_name"], dest_name,
			T.APPROACHES[rec["approach"]]["name"].to_lower(), when], 15,
			"warning" if left <= 0.0 else "text")

func _refresh_forecast() -> void:
	var dest: String = _selected_meta(_where)
	var approach: String = _selected_meta(_approach)
	var npc: Node = _selected_npc()
	_approach_hint.text = String(T.APPROACHES.get(approach, {}).get("blurb", ""))
	var block: String = String(_hatch.call("launch_block_reason"))
	if npc == null:
		block = "No one is fit to go topside." if block == "" else block
	_block_hint.text = block
	_block_hint.visible = block != ""
	_send_btn.disabled = block != "" or dest == ""
	if dest == "":
		_forecast.text = ""
		return
	var f: Dictionary = _hatch.call("forecast", npc, dest, approach)
	var text: String = "%s\n~%dh round trip · Injury risk: %s (%d%%) · Haul: %s" % [
		T.DESTINATIONS[dest]["blurb"], int(round(float(f["hours"]))), f["risk"],
		int(round(float(f["injury_chance"]) * 100.0)), f["haul"]]
	if float(f["loss_chance"]) >= 0.005:
		text += "\nChance they don't come back: %d%%" % maxi(1, int(round(float(f["loss_chance"]) * 100.0)))
	if float(f["depletion"]) > 0.05:
		text += "\nPicked over: %d%%" % int(round(float(f["depletion"]) * 100.0))
	if npc != null and float(f["loyalty"]) < T.SKIM_BELOW:
		text += "\n%s doesn't trust you. They may not share everything." % npc.get("npc_name")
	_forecast.text = text

func _refresh_reports() -> void:
	var reports: Array = _hatch.get("reports")
	var sig: String = "%d:%s" % [reports.size(), String(reports[0]["title"]) if not reports.is_empty() else ""]
	if sig == _reports_sig:
		return
	_reports_sig = sig
	for child: Node in _reports_box.get_children():
		child.queue_free()
	if reports.is_empty():
		W.label(_reports_box, "None", "No runs yet.", 15, "secondary")
		return
	for i: int in mini(REPORTS_SHOWN, reports.size()):
		var rep: Dictionary = reports[i]
		var tone: String = String(rep.get("tone", "info"))
		W.label(_reports_box, "Title", "%s · %s" % [rep["title"], NPCClock.format_age(float(rep["stamp"]))], 15,
			"critical" if tone == "critical" else ("warning" if tone == "warning" else "text"))
		var lines: Array = rep.get("lines", [])
		W.label(_reports_box, "Body", "\n".join(PackedStringArray(lines)), 14, "secondary")

# ─── Actions ──────────────────────────────────────────────────────────────────
func _on_send_pressed() -> void:
	if not _is_open or not is_instance_valid(_hatch):
		return
	var npc: Node = _selected_npc()
	if npc == null:
		return
	if bool(_hatch.call("launch", npc, _selected_meta(_where), _selected_meta(_approach))):
		_options_sig = ""
		_refresh_data()
