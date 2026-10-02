extends "res://scripts/ui/common/BunkerDeviceInspector.gd"
## HatchLeaveUI.gd (Oct 2026)
## The Surface Hatch before the apocalypse (BunkerPhase PRE_APOCALYPSE).
## Instead of planning expeditions, the hatch offers one thing: Leave. Above
## it, a short readiness check — who is coming in, roughly how long the food,
## water and fuel will last for them, and the cash that will be worthless —
## so the player decides with the facts in front of them. Leave asks once
## more in the shared ConfirmDialogUI, then SealTransition plays the seal.
##
## View/controller only: BunkerPhase owns the rules (supply_snapshot, seal).
## Ordinary device inspector: right rail, world visible, walk-away close.

const SEAL_TRANSITION: GDScript = preload("res://scripts/ui/hatch/SealTransition.gd")
const CONFIRM_SCRIPT: String = "res://scripts/ui/common/ConfirmDialogUI.gd"

## Copy. Functional, flagged for Brannon to rewrite (docs/systems/phase).
const BODY_TEXT: String = "When you leave, the hatch seals behind you and Day 1 begins. The shop closes for good, nothing new can be built, and the bunker lives on what you prepared."
const CONFIRM_TITLE: String = "Are you certain you're ready?"
const CONFIRM_TEXT: String = "No major changes can be made after this. The shop closes for good and nothing new can be built."
const LOW_DAYS: float = 3.0

var _hatch: Node = null
var _phase_status: PanelContainer
var _people: VBoxContainer
var _food: VBoxContainer
var _water: VBoxContainer
var _fuel: VBoxContainer
var _cash: VBoxContainer
var _cash_hint: Label
var _leave_btn: Button
var _confirm: CanvasLayer = null


func _build_content() -> void:
	refresh_interval = 0.5
	_phase_status = W.status(_statuses, "Phase")
	W.heading(_details, "LeaveHeading", "WHEN YOU LEAVE")
	W.label(_details, "Body", BODY_TEXT, 15, "secondary")
	W.heading(_details, "ReadyHeading", "WHAT YOU'RE TAKING IN")
	_people = W.stat(_details, "People", "Survivors")
	_food = W.stat(_details, "Food", "Food")
	_water = W.stat(_details, "Water", "Water")
	_fuel = W.stat(_details, "Fuel", "Fuel")
	_cash = W.stat(_details, "Cash", "Unspent cash")
	_cash_hint = W.label(_details, "CashHint", "Unspent cash is lost when you leave.", 14, "warning")
	_leave_btn = W.button(_footer, "Leave", "Leave", _on_leave_pressed, "", true)
	## The one big action on this surface.
	_leave_btn.custom_minimum_size.y = 52.0
	_leave_btn.set_meta("ui_min_height", 52)
	_leave_btn.set_meta("ui_font_size", 19)
	_leave_btn.add_theme_font_size_override("font_size", 19)


func open(hatch: Node) -> void:
	if not is_instance_valid(hatch):
		return
	_hatch = hatch
	_open_device("Surface hatch", "SURFACE", "", hatch as Node3D)
	## Land on the action: Leave is the reason this panel exists.
	_leave_btn.call_deferred("grab_focus")


func _refresh_data() -> void:
	if not is_instance_valid(_hatch) or _hatch.is_queued_for_deletion():
		close()
		return
	var phase: BunkerPhase = BunkerPhase.of(get_tree())
	if phase == null or not phase.is_preparing():
		close()
		return
	W.set_status(_phase_status, "Before the apocalypse", "success")
	var names: Array[String] = phase.resident_names()
	W.set_stat(_people, "Just you" if names.is_empty() else _join_names(names))
	var supply: Dictionary = phase.supply_snapshot()
	_set_supply(_food, float(supply["cans"]), "can", float(supply["food_days"]))
	_set_supply(_water, float(supply["bottles"]), "bottle", float(supply["water_days"]))
	var fuel: float = float(supply["fuel_cans"])
	W.set_stat(_fuel, "%s fuel can%s" % [_amount(fuel), "" if is_equal_approx(fuel, 1.0) else "s"],
		"text" if fuel > 0.05 else "warning")
	var cash: int = int(phase.world.call("get_cash")) if phase.world != null and phase.world.has_method("get_cash") else 0
	W.set_stat(_cash, UIFormat.money(cash), "text")
	_cash_hint.visible = cash > 0


## "12 cans · about 3 days"; warning when short, critical when none.
func _set_supply(row: VBoxContainer, amount: float, unit: String, days: float) -> void:
	if amount < 0.05:
		W.set_stat(row, "None", "critical")
		return
	var plural: String = "" if is_equal_approx(amount, 1.0) else "s"
	var span: String = "under a day" if days < 1.0 else "about %d day%s" % [int(floor(days)), "" if int(floor(days)) == 1 else "s"]
	W.set_stat(row, "%s %s%s · %s" % [_amount(amount), unit, plural, span],
		"warning" if days < LOW_DAYS else "text")


static func _amount(value: float) -> String:
	var rounded: float = snappedf(value, 0.1)
	if is_equal_approx(rounded, roundf(rounded)):
		return str(int(roundf(rounded)))
	return "%.1f" % rounded


static func _join_names(names: Array[String]) -> String:
	if names.size() == 1:
		return names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1]


# ─── Leave ────────────────────────────────────────────────────────────────────
func _on_leave_pressed() -> void:
	if not _is_open:
		return
	if _confirm == null or not is_instance_valid(_confirm):
		_confirm = CanvasLayer.new()
		_confirm.set_script(load(CONFIRM_SCRIPT))
		_confirm.name = "LeaveConfirm"
		get_tree().root.add_child(_confirm)   ## outlives this panel's own close
		_confirm.confirmed.connect(_on_leave_confirmed)
		_confirm.cancelled.connect(_on_leave_cancelled)
	_confirm.call("open", CONFIRM_TITLE, CONFIRM_TEXT, "Leave", "Not yet", "danger", "warning")


func _on_leave_cancelled() -> void:
	if _is_open:
		_leave_btn.grab_focus()


func _on_leave_confirmed() -> void:
	var phase: BunkerPhase = BunkerPhase.of(get_tree())
	close()
	if phase == null or not phase.is_preparing():
		return
	SEAL_TRANSITION.call("play", get_tree(), phase)
