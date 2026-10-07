class_name Menu
extends RefCounted
## What Tony's sells. Orders, the kitchen, prices and the AI all use this list.

const SIZES := {
	"small": {"label": "Small", "radius": 0.3, "price": 8},
	"medium": {"label": "Medium", "radius": 0.38, "price": 11},
	"large": {"label": "Large", "radius": 0.46, "price": 14},
}
const SIZE_ORDER := ["small", "medium", "large"]

const SAUCES := {
	"tomato": {"label": "Tomato", "color": "#c8321f"},
	"bbq": {"label": "BBQ", "color": "#6b2e1a"},
	"white": {"label": "White garlic", "color": "#f1e6cf"},
}

## kind = how the pieces look on the pizza.
const TOPPINGS := {
	"pepperoni": {"label": "Pepperoni", "color": "#b8321f", "kind": "disc", "price": 1.5},
	"mushroom": {"label": "Mushrooms", "color": "#b8a089", "kind": "dome", "price": 1.5},
	"olive": {"label": "Olives", "color": "#2d2a2b", "kind": "ring", "price": 1.5},
	"pepper": {"label": "Green peppers", "color": "#4d9a3a", "kind": "strip", "price": 1.5},
	"onion": {"label": "Onions", "color": "#efe7f2", "kind": "ring", "price": 1.0},
	"sausage": {"label": "Sausage", "color": "#7a4a32", "kind": "blob", "price": 2.0},
	"ham": {"label": "Ham", "color": "#e79a9a", "kind": "square", "price": 2.0},
	"pineapple": {"label": "Pineapple", "color": "#f2c94c", "kind": "chunk", "price": 1.5},
	"anchovy": {"label": "Anchovies", "color": "#8a8f98", "kind": "strip", "price": 2.0},
	"jalapeno": {"label": "Jalapeños", "color": "#2f7a2f", "kind": "disc", "price": 1.5},
	"gummy": {"label": "Gummy bears", "color": "#ff5fa2", "kind": "chunk", "price": 3.0, "unlock": "weird_toppings"},
	"hotdog": {"label": "Hot dog bits", "color": "#d9734a", "kind": "blob", "price": 2.5, "unlock": "weird_toppings"},
}
const TOPPING_ORDER := ["pepperoni", "mushroom", "olive", "pepper", "onion", "sausage", "ham", "pineapple", "anchovy", "jalapeno", "gummy", "hotdog"]

## What it costs Tony's to make a pizza (ingredients), as a fraction of price.
const INGREDIENT_COST := 0.3


static func available_toppings() -> Array[String]:
	var out: Array[String] = []
	for t: String in TOPPING_ORDER:
		var unlock: String = TOPPINGS[t].get("unlock", "")
		if unlock == "" or Game.has_upgrade(unlock):
			out.append(t)
	return out


static func price_of(order: Dictionary) -> int:
	var p := float(SIZES[order.get("size", "medium")].price)
	for t in order.get("toppings", []):
		p += float(TOPPINGS.get(t, {}).get("price", 1.0))
	return int(ceil(p))


static func describe(order: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append(SIZES[order.get("size", "medium")].label)
	var sauce: String = order.get("sauce", "tomato")
	if sauce != "tomato":
		parts.append(SAUCES[sauce].label + " sauce")
	var tops: Array = order.get("toppings", [])
	if tops.is_empty():
		parts.append("cheese")
	else:
		var names: PackedStringArray = []
		for t in tops:
			names.append(TOPPINGS[t].label.to_lower())
		parts.append(", ".join(names))
	return " ".join(parts)


## Text for the AI so customers only order things that exist.
static func menu_for_ai() -> String:
	var tops: PackedStringArray = []
	for t in available_toppings():
		tops.append(t)
	return "Sizes: small, medium, large. Sauces: tomato, bbq, white. Toppings: %s." % ", ".join(tops)


static func random_order(rng: RandomNumberGenerator, favorites: Array = []) -> Dictionary:
	var tops: Array[String] = []
	var avail := available_toppings()
	for f in favorites:
		if f in avail and rng.randf() < 0.75:
			tops.append(f)
	var extra := rng.randi_range(0, 2)
	for i in extra:
		var t: String = avail[rng.randi() % avail.size()]
		if t not in tops:
			tops.append(t)
	var sauce := "tomato"
	var roll := rng.randf()
	if roll > 0.85:
		sauce = "bbq"
	elif roll > 0.72:
		sauce = "white"
	return {"size": SIZE_ORDER[rng.randi() % 3], "sauce": sauce, "toppings": tops.slice(0, 3)}
