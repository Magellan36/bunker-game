extends RefCounted
class_name NPCThoughts
## NPCThoughts.gd (Sep 2026) — short-lived mood modifiers ("thoughts") that
## come from things that actually HAPPENED to an NPC: the meal they ate, how
## they slept, a good chat, a gift, getting their food snatched, a filthy
## bunker, being in pain...
##
## Before this, mood only ever tracked the average of hunger/thirst/energy
## (plus contagion and noise), so nothing the player built or did — beds,
## cooking, cleaning, gifts — had any visible effect on how residents felt.
## Thoughts sum into NPC._tick_mood()'s target, are listed on the resident
## panel ("Feeling"), and colour dialogue, so the player can read WHY
## someone is unhappy and do something about it.
##
## Personality: Optimists feel good things a little more; Neurotic NPCs
## feel bad things a little more (see NPC.thought_weight()).

## id -> definition. "%s" in a label is replaced by the thought's subject
## (another resident's name, usually). `hours` = how long it lasts at full
## strength; it then fades out over FADE_HOURS. `stack` = how many copies
## with DIFFERENT subjects may coexist (same subject refreshes instead).
const DEFS: Dictionary = {
	"ate_hot_meal":      {"label": "Ate a hot meal",                   "mood": 6.0,  "hours": 8.0,  "stack": 1},
	"ate_fresh":         {"label": "Ate something fresh",              "mood": 2.5,  "hours": 6.0,  "stack": 1},
	"ate_cold_can":      {"label": "Ate cold food from a can",         "mood": -1.5, "hours": 6.0,  "stack": 1},
	"slept_in_bed":      {"label": "Slept in a proper bed",            "mood": 4.0,  "hours": 14.0, "stack": 1},
	"slept_in_chair":    {"label": "Dozed off in a chair",             "mood": -2.0, "hours": 10.0, "stack": 1},
	"slept_on_floor":    {"label": "Slept on the floor",               "mood": -5.0, "hours": 14.0, "stack": 1},
	"collapsed":         {"label": "Collapsed from exhaustion",        "mood": -8.0, "hours": 14.0, "stack": 1},
	"good_chat":         {"label": "Had a nice chat with %s",          "mood": 3.0,  "hours": 6.0,  "stack": 3},
	"bad_chat":          {"label": "Got into it with %s",              "mood": -3.0, "hours": 6.0,  "stack": 3},
	"received_gift":     {"label": "%s brought me something",          "mood": 5.0,  "hours": 10.0, "stack": 2},
	"helped_friend":     {"label": "Looked out for %s",                "mood": 2.0,  "hours": 6.0,  "stack": 2},
	"got_snatched":      {"label": "%s snatched my food",              "mood": -6.0, "hours": 12.0, "stack": 2},
	"food_taken":        {"label": "My food was taken away",           "mood": -5.0, "hours": 10.0, "stack": 1},
	"relaxed":           {"label": "Took a proper break",              "mood": 2.0,  "hours": 4.0,  "stack": 1},
	"break_interrupted": {"label": "My break got cut short",           "mood": -3.0, "hours": 4.0,  "stack": 1},
	"productive":        {"label": "Got something useful done",        "mood": 1.5,  "hours": 4.0,  "stack": 1},
	"went_topside":      {"label": "Saw the sky again",                "mood": 4.0,  "hours": 16.0, "stack": 1},
	"rough_trip_topside": {"label": "Got hurt topside",                "mood": -6.0, "hours": 24.0, "stack": 1},
	## Conditions — held while a situation lasts (set_condition()), then fade.
	"cluttered":         {"label": "The bunker is a mess",             "mood": -3.0, "hours": 0.0,  "stack": 1},
	"in_pain":           {"label": "I'm hurt",                         "mood": -4.0, "hours": 0.0,  "stack": 1},
	"lonely":            {"label": "Haven't really talked to anyone",  "mood": -3.0, "hours": 0.0,  "stack": 1},
	"crowded_beds":      {"label": "No bed to call my own",            "mood": -2.0, "hours": 0.0,  "stack": 1},
	"encouraged":        {"label": "Someone had my back",              "mood": 3.0,  "hours": 5.0,  "stack": 1},
	"laughed":           {"label": "Had a good laugh",                 "mood": 2.5,  "hours": 3.0,  "stack": 1},
	"insulted":          {"label": "Got insulted",                     "mood": -5.0, "hours": 12.0, "stack": 1},
	"threatened":        {"label": "Got threatened",                   "mood": -8.0, "hours": 18.0, "stack": 1},
	"burned_out":        {"label": "Burned out",                       "mood": -4.0, "hours": 10.0, "stack": 1},
	"vented_rage":       {"label": "Got it out of my system",          "mood": 2.0,  "hours": 8.0,  "stack": 1},
	"cried_it_out":      {"label": "Cried it out",                     "mood": 3.0,  "hours": 8.0,  "stack": 1},
	## Violence and its aftermath (NPCCombat / CrashOutActivity, Sep 2026).
	"was_attacked":      {"label": "%s attacked me",                   "mood": -7.0, "hours": 24.0, "stack": 2},
	"saw_fight":         {"label": "Saw %s get attacked",              "mood": -3.0, "hours": 8.0,  "stack": 2},
	"grieving":          {"label": "%s is gone",                       "mood": -12.0, "hours": 72.0, "stack": 3},
	"saved_me":          {"label": "%s saved my life",                 "mood": 8.0,  "hours": 36.0, "stack": 1},
	"broke_up_fight":    {"label": "Broke up a fight",                 "mood": 2.0,  "hours": 6.0,  "stack": 1},
	"backed_down":       {"label": "Backed down from %s",              "mood": -3.0, "hours": 8.0,  "stack": 1},
	"talked_down":       {"label": "%s talked me down",                "mood": 3.0,  "hours": 8.0,  "stack": 1},
	## Danger in the bunker (conditions, re-checked every mood tick).
	"body_in_bunker":    {"label": "There's a body in here",           "mood": -7.0, "hours": 0.0,  "stack": 1},
	"weapon_fight":      {"label": "There was a fight with weapons in here", "mood": -6.0, "hours": 0.0, "stack": 1},
	"unsafe_with":       {"label": "Living with someone who attacked me", "mood": -4.0, "hours": 0.0, "stack": 1},
	## Care between residents (TreatActivity).
	"patched_up":        {"label": "%s patched me up",                 "mood": 4.0,  "hours": 12.0, "stack": 2},
	"under_pressure":    {"label": "Being pushed hard",                "mood": -3.0, "hours": 0.0,  "stack": 1},
	"cowed":             {"label": "Put in my place",                  "mood": -2.0, "hours": 0.0,  "stack": 1},
	"hungry":            {"label": "Hungry",                           "mood": -4.0, "hours": 0.0,  "stack": 1},
	"starving":          {"label": "Starving",                         "mood": -12.0, "hours": 0.0, "stack": 1},
	"thirsty":           {"label": "Thirsty",                          "mood": -4.0, "hours": 0.0,  "stack": 1},
	"parched":           {"label": "Parched",                          "mood": -12.0, "hours": 0.0, "stack": 1},
	"exhausted":         {"label": "Exhausted",                        "mood": -7.0, "hours": 0.0,  "stack": 1},
}
const FADE_HOURS: float = 2.0
const MAX_THOUGHTS: int = 12

## Each entry: {"id", "subject", "mood", "left", "condition"}
var _list: Array[Dictionary] = []

## Adds (or refreshes) a thought. `weight` scales its mood (personality).
func add(id: String, subject: String = "", weight: float = 1.0) -> void:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		push_warning("NPCThoughts: unknown thought '%s'" % id)
		return
	var same_id: Array[Dictionary] = []
	for t: Dictionary in _list:
		if t["id"] != id:
			continue
		if t["subject"] == subject:
			t["left"] = float(def["hours"]) + FADE_HOURS   ## refresh
			t["mood"] = float(def["mood"]) * weight
			return
		same_id.append(t)
	if same_id.size() >= int(def.get("stack", 1)):
		_list.erase(_oldest(same_id))
	_list.append({"id": id, "subject": subject, "mood": float(def["mood"]) * weight,
		"left": float(def["hours"]) + FADE_HOURS, "condition": false})
	while _list.size() > MAX_THOUGHTS:
		_list.erase(_weakest())

## Turns a condition thought on/off. While on it holds at full strength;
## once off it fades over FADE_HOURS like any other thought.
func set_condition(id: String, active: bool, weight: float = 1.0) -> void:
	for t: Dictionary in _list:
		if t["id"] == id:
			if active:
				t["condition"] = true
				t["left"] = FADE_HOURS
				t["mood"] = float(DEFS[id]["mood"]) * weight
			else:
				t["condition"] = false
			return
	if active:
		_list.append({"id": id, "subject": "", "mood": float(DEFS[id]["mood"]) * weight,
			"left": FADE_HOURS, "condition": true})

func has(id: String) -> bool:
	for t: Dictionary in _list:
		if t["id"] == id:
			return true
	return false

func tick(h: float) -> void:
	for i: int in range(_list.size() - 1, -1, -1):
		var t: Dictionary = _list[i]
		if t["condition"]:
			continue
		t["left"] = float(t["left"]) - h
		if float(t["left"]) <= 0.0:
			_list.remove_at(i)

## Current strength multiplier (1.0 until the fade window, then → 0).
func _strength(t: Dictionary) -> float:
	if t["condition"]:
		return 1.0
	return clampf(float(t["left"]) / FADE_HOURS, 0.0, 1.0)

func total() -> float:
	var sum: float = 0.0
	for t: Dictionary in _list:
		sum += float(t["mood"]) * _strength(t)
	return sum

## Display list, strongest first: [{"text", "mood"}]
func describe() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in _list:
		var mood_now: float = float(t["mood"]) * _strength(t)
		if absf(mood_now) < 0.25:
			continue
		var text: String = String(DEFS[t["id"]]["label"])
		if text.contains("%s"):
			text = text % (t["subject"] if t["subject"] != "" else "someone")
		out.append({"id": t["id"], "text": text, "mood": mood_now, "subject": t["subject"]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(a["mood"]) > absf(b["mood"]))
	return out

## Strongest positive/negative thought (for dialogue), or {}.
func strongest(positive: bool) -> Dictionary:
	var best: Dictionary = {}
	for d: Dictionary in describe():
		if (d["mood"] > 0.0) == positive and (best.is_empty() or absf(d["mood"]) > absf(best["mood"])):
			best = d
	return best

func to_save() -> Array:
	return _list.duplicate(true)

func from_save(data: Array) -> void:
	_list.clear()
	for v: Variant in data:
		if v is Dictionary and DEFS.has(String(v.get("id", ""))):
			_list.append({"id": String(v["id"]), "subject": String(v.get("subject", "")),
				"mood": float(v.get("mood", 0.0)), "left": float(v.get("left", 0.0)),
				"condition": bool(v.get("condition", false))})

func _oldest(arr: Array[Dictionary]) -> Dictionary:
	var o: Dictionary = arr[0]
	for t: Dictionary in arr:
		if float(t["left"]) < float(o["left"]):
			o = t
	return o

func _weakest() -> Dictionary:
	var w: Dictionary = _list[0]
	for t: Dictionary in _list:
		if absf(float(t["mood"]) * _strength(t)) < absf(float(w["mood"]) * _strength(w)):
			w = t
	return w
