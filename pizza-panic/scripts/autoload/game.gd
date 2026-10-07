extends Node
## Global game state for one shift: money, the current order, the pizza's
## physical well-being, and a few signals the UI listens to.

signal money_changed(total: int, delta: int)
signal order_changed(order: Dictionary)
signal pizza_damaged(hp: float)
signal toast(text: String, color: Color)
signal shift_ended(summary: Dictionary)

const SHIFT_SECONDS := 420.0

const WEIRD_PIZZAS := [
	"a large pepperoni",
	"a pizza with gummy bears on it",
	"a pizza that is just cheese and regret",
	"a pineapple-anchovy supreme",
	"a cold pizza (they specifically asked for cold)",
	"a pizza shaped like a cat",
	"a calzone that has been told it is a pizza",
	"a double hot-dog-crust meat explosion",
	"a pizza with a smaller pizza on top",
	"a pizza with exactly one olive",
	"the 'Spicy Grandma' (do not ask)",
	"a gluten-free, cheese-free, pizza-free pizza",
	"a pizza with a birthday candle in it for some reason",
]

var money := 0
var deliveries := 0
var failed := 0
var tips_total := 0
var best_tip := 0
var pizza_hp := 100.0
## Empty when the player isn't carrying anything. Keys:
##   house (Node), pizza (String), deadline (float, seconds of shift_time),
##   time_limit (float)
var order: Dictionary = {}
var shift_time := 0.0
var running := false
var in_dialogue := false


func start_shift() -> void:
	money = 0
	deliveries = 0
	failed = 0
	tips_total = 0
	best_tip = 0
	pizza_hp = 100.0
	order = {}
	shift_time = 0.0
	running = true
	in_dialogue = false
	money_changed.emit(money, 0)
	order_changed.emit(order)


func _process(delta: float) -> void:
	if not running or get_tree().paused:
		return
	# The clock doesn't run while you're mid-conversation. We're not monsters.
	if not in_dialogue:
		shift_time += delta
	if shift_time >= SHIFT_SECONDS:
		end_shift()


func time_left_in_shift() -> float:
	return maxf(0.0, SHIFT_SECONDS - shift_time)


func has_order() -> bool:
	return not order.is_empty()


func order_seconds_left() -> float:
	if order.is_empty():
		return 0.0
	return order.deadline - shift_time


func new_order(house: Node, distance: float) -> Dictionary:
	var limit: float = clampf(distance / 9.0 + 18.0, 25.0, 75.0)
	order = {
		"house": house,
		"pizza": WEIRD_PIZZAS.pick_random(),
		"deadline": shift_time + limit,
		"time_limit": limit,
	}
	pizza_hp = 100.0
	order_changed.emit(order)
	return order


func damage_pizza(amount: float) -> void:
	if order.is_empty():
		return
	pizza_hp = maxf(0.0, pizza_hp - amount)
	pizza_damaged.emit(pizza_hp)


## Called when an NPC accepts the pizza. Returns the money earned.
func complete_delivery(tip_from_npc: int) -> int:
	var late := order_seconds_left() < 0.0
	var base := 0 if late else 12
	var condition_bonus := int(roundf((pizza_hp - 50.0) / 10.0))
	var speed_bonus := int(maxf(0.0, order_seconds_left()) / 6.0)
	var tip := clampi(tip_from_npc + condition_bonus + speed_bonus, 0, 40)
	var earned := base + tip
	money += earned
	deliveries += 1
	tips_total += tip
	best_tip = maxi(best_tip, tip)
	order = {}
	money_changed.emit(money, earned)
	order_changed.emit(order)
	return earned


func fail_delivery(reason: String) -> void:
	failed += 1
	order = {}
	order_changed.emit(order)
	toast.emit(reason, Color("#ff5d73"))


func end_shift() -> void:
	if not running:
		return
	running = false
	shift_ended.emit({
		"money": money,
		"deliveries": deliveries,
		"failed": failed,
		"best_tip": best_tip,
		"rank": rank_for(money),
	})


static func rank_for(cash: int) -> String:
	if cash >= 260:
		return "PIZZA GOD (Tony is crying)"
	if cash >= 180:
		return "Cheese Wizard"
	if cash >= 110:
		return "Certified Slice Slinger"
	if cash >= 50:
		return "Mediocre Pizza Person"
	if cash > 0:
		return "Pizza Peasant"
	return "Professional Pizza Loser"


func say_toast(text: String, color := Color("#ffd166")) -> void:
	toast.emit(text, color)
