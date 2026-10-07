class_name Upgrades
extends RefCounted
## Everything you can buy. `levels` = how many times it can be bought;
## `costs` lists the price of each level.

const LIST := {
	# --- CAR -----------------------------------------------------------------
	"engine": {"cat": "Car", "name": "Engine", "levels": 4, "costs": [80, 180, 350, 600],
		"desc": "Go faster. Level 4 is honestly irresponsible."},
	"tires": {"cat": "Car", "name": "Grippy Tires", "levels": 3, "costs": [70, 160, 300],
		"desc": "Better steering and less sliding around corners."},
	"suspension": {"cat": "Car", "name": "Bouncy Suspension", "levels": 3, "costs": [90, 200, 380],
		"desc": "Crashes smush the pizzas less. Also bouncier."},
	"hot_bag": {"cat": "Car", "name": "Hot Bag", "levels": 3, "costs": [60, 150, 300],
		"desc": "Pizzas stay hot longer on the road. Hot pizza = bigger tips."},
	"cargo": {"cat": "Car", "name": "Roof Rack", "levels": 3, "costs": [120, 260, 500],
		"desc": "Carry more pizzas per trip (2 > 3 > 4 > 6)."},
	"boost": {"cat": "Car", "name": "Pizza Rocket", "levels": 1, "costs": [450],
		"desc": "Hold SHIFT to boost. Smells like oregano."},
	"horn": {"cat": "Car", "name": "Silly Horn", "levels": 3, "costs": [25, 40, 60],
		"desc": "Upgrade the honk: clown > air horn > goat."},
	"paint": {"cat": "Car", "name": "Paint Job", "levels": 4, "costs": [30, 30, 30, 30],
		"desc": "New color for the car. Purely for the drip."},
	# --- KITCHEN ---------------------------------------------------------------
	"oven": {"cat": "Kitchen", "name": "Turbo Oven", "levels": 3, "costs": [100, 220, 420],
		"desc": "Pizzas bake faster."},
	"second_oven": {"cat": "Kitchen", "name": "Second Oven", "levels": 1, "costs": [300],
		"desc": "Bake two pizzas at once."},
	"dough_press": {"cat": "Kitchen", "name": "Dough Press", "levels": 2, "costs": [90, 200],
		"desc": "Makes the dough-stretching sweet spot bigger."},
	"sauce_gun": {"cat": "Kitchen", "name": "Sauce Gun", "levels": 2, "costs": [80, 180],
		"desc": "Sauce and cheese spread faster and more evenly."},
	"headset": {"cat": "Kitchen", "name": "Cordless Headset", "levels": 1, "costs": [150],
		"desc": "Answer phone calls from anywhere, even while driving (press Q)."},
	"neon_sign": {"cat": "Kitchen", "name": "Neon Sign", "levels": 2, "costs": [140, 320],
		"desc": "More people notice Tony's. More phone calls."},
	"weird_toppings": {"cat": "Kitchen", "name": "Weird Toppings", "levels": 1, "costs": [120],
		"desc": "Unlocks gummy bears and hot dog bits. Customers will order them."},
	"heat_lamp": {"cat": "Kitchen", "name": "Heat Lamp Shelf", "levels": 1, "costs": [110],
		"desc": "Boxed pizzas waiting in the kitchen don't cool down."},
	# --- YOU -------------------------------------------------------------------
	"sneakers": {"cat": "You", "name": "Fast Sneakers", "levels": 2, "costs": [60, 150],
		"desc": "Run around the kitchen faster."},
	"hat": {"cat": "You", "name": "New Hat", "levels": 5, "costs": [40, 60, 80, 120, 250],
		"desc": "Beanie > propeller cap > cowboy hat > top hat > CROWN."},
}

const HATS := ["cap", "beanie", "propeller", "cowboy", "tophat", "crown"]
const PAINTS := ["#c0392b", "#2e86de", "#27ae60", "#8e44ad", "#f39c12"]
const CARGO := [2, 3, 4, 6]


static func cost(id: String, level: int) -> int:
	var costs: Array = LIST[id].costs
	return costs[level] if level < costs.size() else -1


static func maxed(id: String, level: int) -> bool:
	return level >= int(LIST[id].levels)
