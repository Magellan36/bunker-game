# Cooking System — Recipe Naming: "Best Fit" Implementation

Builds on `COOKING_RECIPE_DESIGN.md` with your 4 confirmed decisions:

1. **Best-fit matching**, not exact-set — a recipe can win even if the pot
   has extra ingredients it doesn't call for. `{Chili Pepper, Onion,
   Pumpkin}` → "Spicy Chili Sauté" (which only needs `{Chili Pepper,
   Onion}`), because nothing else defined fits better yet.
2. **"Cooked Dish" stays the fallback** for anything that doesn't score well
   against any recipe.
3. **New Preserve/Compote category** for fruit-only combos, alternating the
   two words per recipe.
4. Name-only for now — the Filling/Diversity math is completely untouched.

## The matching algorithm

Every recipe in a static table gets scored against whatever's actually in
the pot (as a set of distinct ingredient types — duplicates don't matter).
Highest score wins:

```
score = (2 × ingredients shared between pot and recipe)
      − (1 × ingredients in the pot the recipe doesn't call for — "extras")
      − (1 × ingredients the recipe calls for that the pot doesn't have — "misses")
```

Worked example — `{Chili Pepper, Onion, Pumpkin}` in the pot:
- vs. **Spicy Chili Sauté** `{Chili Pepper, Onion}`: 2 shared, 1 extra (Pumpkin), 0 miss → `2×2 − 1 − 0 = 3`
- vs. **Pumpkin Porridge** `{Pumpkin}`: 1 shared, 2 extra, 0 miss → `2×1 − 2 − 0 = 0`
- vs. **Vegetable Gumbo** `{Onion, Bell Pepper, Tomato}`: 1 shared, 2 extra, 2 miss → `2×1 − 2 − 2 = −2`

Spicy Chili Sauté wins with score 3 — matches your example exactly. Ties
break on (in order): higher shared-ingredient count, then alphabetically by
dish name — fully deterministic, no randomness. If the winning score
doesn't clear a minimum threshold (nothing reasonably explains the pot's
contents), it falls back to `"Cooked Dish"`.

## The recipe table (27 recipes, every ingredient set verified unique)

Same 23 from the design doc, one collision-fix (Casserole's 2-ingredient
Potato+Corn set collided with Porridge's — expanded the Casserole one to 3
ingredients), plus 4 new Preserve/Compote recipes:

- **Porridge (3):** Potato · Pumpkin · Corn & Potato
- **Soup (4):** Tomato Basil · Garden Vegetable · Roasted Garlic · Canned Ration
- **Stew (3):** Root Vegetable · Hearty Garden · Canned Ration
- **Casserole (3):** Potato/Corn/Pepper · Garden · Canned Ration
- **Sauté (4):** Garlic Basil · Pepper & Onion · Spicy Chili · Tomato Basil Garlic
- **Chowder (2):** Corn · Garden
- **Gumbo (2):** Vegetable · Spicy Garden
- **Paella (1):** Garden
- **Baseline (1):** Canned Ration (Food Can alone)
- **Preserve/Compote (4):** Blueberry Compote · Strawberry Preserve · Mixed Berry Preserve · Pumpkin Berry Compote
- **Pemmican (0):** intentionally empty — still needs a real meat item

---

## `scripts/world/items/CookingPot.gd`

### 1. New state var

Find:

```gdscript
var _cook_progress: float = 0.0
var _is_cooked:     bool  = false
var _dish_value:    float = 0.0
var _dish_bonus_pct: float = 0.0
```

Replace with:

```gdscript
var _cook_progress: float = 0.0
var _is_cooked:     bool  = false
var _dish_value:    float = 0.0
var _dish_bonus_pct: float = 0.0
var _dish_name:     String = "Cooked Dish"
```

### 2. Recipe table + resolver (new — add this as its own section, e.g. right after the `RigidBody3D`/state-var block and before `func _ready()`)

```gdscript
# ─── Recipe system (Aug 2026) ──────────────────────────────────────────────
## "Best fit" matching: EVERY recipe is scored against whatever's actually
## in the pot, and the highest-scoring recipe wins — even if the pot has
## extra ingredients the recipe doesn't call for. Confirmed spec:
## {Chili Pepper, Onion, Pumpkin} should still resolve to "Spicy Chili
## Sauté" (which only needs {Chili Pepper, Onion}) rather than matching
## nothing just because Pumpkin is also present.
##
## score = (2 × shared) − (1 × extras in pot not in recipe) − (1 × misses
## the recipe needs but the pot doesn't have). Highest score wins; ties
## break on more shared ingredients, then alphabetically by name
## (deterministic, no randomness). Falls back to "Cooked Dish" if nothing
## clears RECIPE_MIN_SCORE — long-term goal is for every combination to
## resolve to SOMETHING that at least loosely fits, but that's future
## recipe-list expansion, not a change to this matching logic.
const RECIPE_MIN_SCORE: float = 1.0

## Static recipe table. Each entry: { "name": String, "ingredients": Array[String] }.
## ingredients are ingredient_key values (see _get_item_ingredient_key()).
## Every ingredient set below is verified unique — no two recipes share the
## exact same set (verified by hand; if you add a new recipe, re-check this).
const RECIPES: Array[Dictionary] = [
	# ── Porridge ──
	{"name": "Potato Porridge",                "ingredients": ["produce_potato"]},
	{"name": "Pumpkin Porridge",                "ingredients": ["produce_pumpkin"]},
	{"name": "Corn & Potato Porridge",          "ingredients": ["produce_corn", "produce_potato"]},
	# ── Soup ──
	{"name": "Tomato Basil Soup",               "ingredients": ["produce_tomato", "produce_basil"]},
	{"name": "Garden Vegetable Soup",           "ingredients": ["produce_carrot", "produce_onion", "produce_potato"]},
	{"name": "Roasted Garlic Soup",             "ingredients": ["produce_garlic", "produce_onion", "produce_potato"]},
	{"name": "Canned Ration Soup",              "ingredients": ["food_can", "produce_onion"]},
	# ── Stew ──
	{"name": "Root Vegetable Stew",             "ingredients": ["produce_potato", "produce_carrot", "produce_garlic"]},
	{"name": "Hearty Garden Stew",               "ingredients": ["produce_potato", "produce_bell_pepper", "produce_onion"]},
	{"name": "Canned Ration Stew",               "ingredients": ["food_can", "produce_potato", "produce_onion"]},
	# ── Casserole ──
	{"name": "Potato, Corn & Pepper Casserole", "ingredients": ["produce_potato", "produce_corn", "produce_bell_pepper"]},
	{"name": "Garden Casserole",                "ingredients": ["produce_potato", "produce_carrot", "produce_corn"]},
	{"name": "Canned Ration Casserole",         "ingredients": ["food_can", "produce_potato", "produce_corn"]},
	# ── Sauté ──
	{"name": "Garlic Basil Sauté",              "ingredients": ["produce_garlic", "produce_basil"]},
	{"name": "Pepper & Onion Sauté",            "ingredients": ["produce_bell_pepper", "produce_onion"]},
	{"name": "Spicy Chili Sauté",                "ingredients": ["produce_chili_pepper", "produce_onion"]},
	{"name": "Tomato Basil Garlic Sauté",       "ingredients": ["produce_tomato", "produce_basil", "produce_garlic"]},
	# ── Chowder ──
	{"name": "Corn Chowder",                    "ingredients": ["produce_corn", "produce_potato", "produce_onion"]},
	{"name": "Garden Chowder",                  "ingredients": ["produce_corn", "produce_bell_pepper", "produce_carrot"]},
	# ── Gumbo ──
	{"name": "Vegetable Gumbo",                 "ingredients": ["produce_onion", "produce_bell_pepper", "produce_tomato"]},
	{"name": "Spicy Garden Gumbo",               "ingredients": ["produce_bell_pepper", "produce_chili_pepper", "produce_onion"]},
	# ── Paella ──
	{"name": "Garden Paella",                   "ingredients": ["produce_bell_pepper", "produce_tomato", "produce_garlic"]},
	# ── Baseline (early game) ──
	{"name": "Canned Ration",                   "ingredients": ["food_can"]},
	# ── Preserve / Compote (fruit-only) ──
	{"name": "Blueberry Compote",               "ingredients": ["produce_blueberry"]},
	{"name": "Strawberry Preserve",             "ingredients": ["produce_strawberry"]},
	{"name": "Mixed Berry Preserve",            "ingredients": ["produce_blueberry", "produce_strawberry"]},
	{"name": "Pumpkin Berry Compote",           "ingredients": ["produce_pumpkin", "produce_blueberry"]},
	# Pemmican intentionally has NO recipes yet — needs a meat/protein item
	# that doesn't exist in the game. Do not approximate it with berries
	# alone; leave it fully locked until a real meat item is added.
]

## Resolves the best-fit dish name for a set of DISTINCT ingredient keys
## (duplicates in `keys` don't matter — pass unique keys). Falls back to
## "Cooked Dish" if nothing scores well enough.
static func resolve_dish_name(keys: Array) -> String:
	var pot_set: Dictionary = {}
	for k in keys:
		pot_set[k] = true

	var best_name: String = "Cooked Dish"
	var best_score: float = -INF
	var best_matches: int = -1

	for recipe: Dictionary in RECIPES:
		var recipe_keys: Array = recipe["ingredients"]
		var matches: int = 0
		var misses: int  = 0
		for rk in recipe_keys:
			if pot_set.has(rk):
				matches += 1
			else:
				misses += 1
		var extras: int = 0
		for pk in pot_set.keys():
			if not recipe_keys.has(pk):
				extras += 1

		var score: float = float(matches) * 2.0 - float(extras) - float(misses)

		var better: bool = false
		if score > best_score:
			better = true
		elif score == best_score and matches > best_matches:
			better = true
		elif score == best_score and matches == best_matches and String(recipe["name"]) < best_name:
			better = true

		if better:
			best_score   = score
			best_matches = matches
			best_name    = String(recipe["name"])

	if best_score < RECIPE_MIN_SCORE:
		return "Cooked Dish"
	return best_name

```

### 3. `get_interact_prompt()` — show the resolved name both while cooking and when done

Find:

```gdscript
func get_interact_prompt() -> String:
	if _is_cooked:
		return "DONE  —  [E] Take Dish  (%.1f Filling)" % _dish_value
	var totals: Dictionary = compute_dish_totals()
	if totals["item_count"] <= 0:
		return ""
	var bonus_txt: String = "" if totals["bonus_pct"] <= 0.0 else "  (+%d%% Diversity)" % int(round(totals["bonus_pct"] * 100.0))
	var base_txt: String = "Filling: %.1f%s" % [totals["total"], bonus_txt]
	if _host_stove != null and _host_stove.has_method("is_cooking") and _host_stove.is_cooking():
		return "%s  —  COOKING  (%.0f/%.0fs)" % [base_txt, _cook_progress, cook_time_required()]
	return base_txt
```

Replace with:

```gdscript
func get_interact_prompt() -> String:
	if _is_cooked:
		if _host_stove != null:
			return ""
		return "DONE  —  [E] Take Dish  (%s, %.1f Filling)" % [_dish_name, _dish_value]
	var totals: Dictionary = compute_dish_totals()
	if totals["item_count"] <= 0:
		return ""
	## Live best-fit preview of what this WOULD cook into right now, even
	## before the timer finishes — same resolver _finish_cooking() uses.
	var unique_keys: Array = []
	for entry in slots:
		if entry != null and not unique_keys.has(entry["ingredient_key"]):
			unique_keys.append(entry["ingredient_key"])
	var preview_name: String = resolve_dish_name(unique_keys)
	var bonus_txt: String = "" if totals["bonus_pct"] <= 0.0 else "  (+%d%% Diversity)" % int(round(totals["bonus_pct"] * 100.0))
	var base_txt: String = "%s  —  Filling: %.1f%s" % [preview_name, totals["total"], bonus_txt]
	if _host_stove != null and _host_stove.has_method("is_cooking") and _host_stove.is_cooking():
		return "%s  —  COOKING  (%.0f/%.0fs)" % [base_txt, _cook_progress, cook_time_required()]
	return base_txt
```

**Note:** this re-adds the `if _host_stove != null: return ""` guard for the
DONE state (suppresses the pot's own panel while on a stove, since the
Stove's panel already delegates to it — this was already fixed in an
earlier amendment; included here so the whole function is a clean,
complete replacement rather than a partial one that might silently drop
that earlier fix).

### 4. `_finish_cooking()` — resolve and store the dish name

Find:

```gdscript
func _finish_cooking() -> void:
	var totals: Dictionary = compute_dish_totals()
	_dish_value     = totals["total"]
	_dish_bonus_pct = totals["bonus_pct"]
	for i: int in CAPACITY:
```

Replace with:

```gdscript
func _finish_cooking() -> void:
	var totals: Dictionary = compute_dish_totals()
	_dish_value     = totals["total"]
	_dish_bonus_pct = totals["bonus_pct"]

	var unique_keys: Array = []
	for entry in slots:
		if entry != null and not unique_keys.has(entry["ingredient_key"]):
			unique_keys.append(entry["ingredient_key"])
	_dish_name = resolve_dish_name(unique_keys)

	for i: int in CAPACITY:
```

(Leave the rest of `_finish_cooking()`'s body — the slot-clearing loop,
`_cook_progress = 0.0`, `_is_cooked = true`, and the `notify_pot_contents_changed()`
call — completely untouched. Only the top of the function changes.)

### 5. `serve_dish()` — hand the name to whoever creates the DishItem

Find:

```gdscript
func serve_dish() -> Dictionary:
	if not _is_cooked:
		return {}
	var result: Dictionary = {"value": _dish_value, "bonus_pct": _dish_bonus_pct}
	_is_cooked      = false
	_dish_value     = 0.0
	_dish_bonus_pct = 0.0
	return result
```

Replace with:

```gdscript
func serve_dish() -> Dictionary:
	if not _is_cooked:
		return {}
	var result: Dictionary = {"value": _dish_value, "bonus_pct": _dish_bonus_pct, "name": _dish_name}
	_is_cooked      = false
	_dish_value     = 0.0
	_dish_bonus_pct = 0.0
	_dish_name      = "Cooked Dish"
	return result
```

### 6. Save/load — persist the resolved name too

Find:

```gdscript
	return {
		"slots":          slots_out,
		"cook_progress":  _cook_progress,
		"is_cooked":      _is_cooked,
		"dish_value":     _dish_value,
		"dish_bonus_pct": _dish_bonus_pct,
	}
```

Replace with:

```gdscript
	return {
		"slots":          slots_out,
		"cook_progress":  _cook_progress,
		"is_cooked":      _is_cooked,
		"dish_value":     _dish_value,
		"dish_bonus_pct": _dish_bonus_pct,
		"dish_name":      _dish_name,
	}
```

Find:

```gdscript
	_cook_progress  = float(extra.get("cook_progress", 0.0))
	_is_cooked      = bool(extra.get("is_cooked", false))
	_dish_value     = float(extra.get("dish_value", 0.0))
	_dish_bonus_pct = float(extra.get("dish_bonus_pct", 0.0))
```

Replace with:

```gdscript
	_cook_progress  = float(extra.get("cook_progress", 0.0))
	_is_cooked      = bool(extra.get("is_cooked", false))
	_dish_value     = float(extra.get("dish_value", 0.0))
	_dish_bonus_pct = float(extra.get("dish_bonus_pct", 0.0))
	_dish_name      = String(extra.get("dish_name", "Cooked Dish"))
```

---

## `scripts/world/items/DishItem.gd`

Find:

```gdscript
var fill_value: float = 0.0
var bonus_pct:  float = 0.0
```

Replace with:

```gdscript
var fill_value: float = 0.0
var bonus_pct:  float = 0.0
var dish_name:  String = "Cooked Dish"
```

Find:

```gdscript
func get_display_name() -> String:
	return "Cooked Dish"

func get_prompt_text() -> String:
	return "[F] Pick up  Cooked Dish"

func get_use_prompt() -> String:
	return "[E] Eat  Cooked Dish  (%.1f)" % fill_value
```

Replace with:

```gdscript
func get_display_name() -> String:
	return dish_name

func get_prompt_text() -> String:
	return "[F] Pick up  %s" % dish_name

func get_use_prompt() -> String:
	return "[E] Eat  %s  (%.1f)" % [dish_name, fill_value]
```

Leave `on_use()` and `consume_as_food()` completely untouched — they
already work purely off `fill_value`/`bonus_pct` and don't reference the
name at all (this also means the NPC-facing consumption path from NPC Pass
2 Part 3 is unaffected by this change).

---

## `scripts/player/InteractionSystem.gd`

Find:

```gdscript
	dish.global_position = (pot as Node3D).global_position
	dish.fill_value = result["value"]
	dish.bonus_pct  = result["bonus_pct"]
```

Replace with:

```gdscript
	dish.global_position = (pot as Node3D).global_position
	dish.fill_value = result["value"]
	dish.bonus_pct  = result["bonus_pct"]
	dish.dish_name  = String(result.get("name", "Cooked Dish"))
```

---

## Verify

1. Cook `{Tomato, Basil}` alone → confirm the live preview (while cooking)
   and the final "DONE" text both say **Tomato Basil Soup**.
2. Cook `{Chili Pepper, Onion, Pumpkin}` → confirm it resolves to **Spicy
   Chili Sauté**, matching the worked example above, not "Cooked Dish" and
   not some worse partial match.
3. Cook `{Strawberry}` alone → confirm **Strawberry Preserve**. Cook
   `{Blueberry, Strawberry}` → confirm **Mixed Berry Preserve** (not the
   single-fruit names).
4. Cook something with no good match at all (e.g. `{Basil, Corn, Strawberry}`
   — deliberately unrelated ingredients) → confirm it falls back to the
   generic **Cooked Dish**, not a nonsensical low-quality match.
5. Take the dish (`[E]`) in each case and confirm the resolved name carries
   through to the held `DishItem`'s pickup/eat prompts, not just the pot's
   own hover text.
6. Save mid-cook with a resolvable ingredient combo in the pot, reload, let
   it finish — confirm the correct dish name still comes out the other end
   (tests the save/load `dish_name` round-trip).
