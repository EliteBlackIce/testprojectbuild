extends Node
## The business: money, days, the clock, order tickets, reputation, upgrades
## and saving. Scenes listen to the signals here.

signal money_changed(total: int, delta: int)
signal tickets_changed
signal toast(text: String, color: Color)
signal day_started(day: int)
signal day_ended(summary: Dictionary)
signal upgrades_changed
signal staff_changed

const SAVE_PATH := "user://save.json"
const OPEN_MINUTE := 10 * 60      ## 10:00
const LAST_CALL_MINUTE := 20 * 60 + 30
const CLOSE_MINUTE := 22 * 60     ## 22:00
## Real seconds per in-game minute.
const SECONDS_PER_MINUTE := 1.0
## How long a customer is promised their pizza (game minutes).
const PROMISE_MINUTES := 75.0

var money := 40
var bonks := 0                 ## eggs bonked today (just for bragging)
var day := 1
var reputation := 2.5             ## 0..5 stars
var upgrades: Dictionary = {}     ## id -> level
var staff: Dictionary = {}        ## hired StaffData id -> {"training": n}
var lifetime := {"delivered": 0, "earned": 0, "best_tip": 0, "days": 0}

var clock := float(OPEN_MINUTE)   ## minutes since midnight
var day_running := false
var in_dialogue := false
var today: Dictionary = {}
var tickets: Array[Dictionary] = []
var _next_ticket_id := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	load_game()


func _process(delta: float) -> void:
	if not day_running or in_dialogue:
		return
	clock += delta / SECONDS_PER_MINUTE
	if clock >= CLOSE_MINUTE:
		end_day()


# --- days ------------------------------------------------------------------------

func start_day() -> void:
	clock = float(OPEN_MINUTE)
	bonks = 0
	day_running = true
	in_dialogue = false
	tickets.clear()
	today = {"earned": 0, "tips": 0, "costs": 0, "delivered": 0, "failed": 0, "missed_calls": 0,
		"rep_start": reputation, "perfect": 0, "wages": 0, "staff_made": 0}
	tickets_changed.emit()
	day_started.emit(day)


func end_day() -> void:
	if not day_running:
		return
	day_running = false
	for t in tickets:
		if t.status not in ["delivered", "failed"]:
			t.status = "failed"
			today.failed += 1
			reputation = maxf(0.0, reputation - 0.2)
	# Pay the staff
	var wages := wages_total()
	if wages > 0:
		money = maxi(0, money - wages)
		today.wages = wages
		money_changed.emit(money, -wages)
	var summary := today.duplicate()
	summary["day"] = day
	summary["rep_end"] = reputation
	summary["money"] = money
	summary["rank"] = rank_for_day(summary)
	lifetime.days += 1
	day += 1
	save_game()
	tickets_changed.emit()
	day_ended.emit(summary)


func is_last_call() -> bool:
	return clock >= LAST_CALL_MINUTE


func clock_text() -> String:
	var m := int(clock)
	var h := (m / 60) % 24
	var ampm := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m % 60, ampm]


## 0 = morning, 1 = midnight-ish. Used for lighting.
func day_fraction() -> float:
	return clampf((clock - OPEN_MINUTE) / float(CLOSE_MINUTE - OPEN_MINUTE), 0.0, 1.0)


# --- tickets ------------------------------------------------------------------------

func add_ticket(house: Node, customer_name: String, order: Dictionary) -> Dictionary:
	var t := {
		"id": _next_ticket_id,
		"house": house,
		"customer": customer_name,
		"order": order,
		"price": Menu.price_of(order),
		"status": "new",          # new -> making -> baking -> ready -> in_car -> delivered / failed
		"created": clock,
		"due": clock + PROMISE_MINUTES,
	}
	_next_ticket_id += 1
	tickets.append(t)
	tickets_changed.emit()
	return t


func ticket(id: int) -> Dictionary:
	for t in tickets:
		if t.id == id:
			return t
	return {}


func open_tickets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in tickets:
		if t.status not in ["delivered", "failed"]:
			out.append(t)
	return out


func set_ticket_status(id: int, status: String) -> void:
	var t := ticket(id)
	if not t.is_empty():
		t.status = status
		tickets_changed.emit()


func minutes_left(t: Dictionary) -> float:
	return float(t.due) - clock


## Pizza handed over and accepted. `pizza` is a PizzaItem's data dictionary.
## Returns the breakdown so the UI can show it.
func complete_delivery(id: int, pizza: Dictionary, npc_tip: int) -> Dictionary:
	var t := ticket(id)
	if t.is_empty():
		return {}
	var q := Pizza.quality(pizza, t.order)
	var late := minutes_left(t) < 0.0
	var price: int = t.price
	if late:
		price = int(price * 0.5)
	var tip_mult: float = 0.4 + q.total * 1.2 + (reputation - 2.5) * 0.08
	var tip := clampi(int(round(npc_tip * tip_mult + (3.0 if q.total > 0.85 and not late else 0.0))), 0, 40)
	var earned := price + tip
	t.status = "delivered"
	money += earned
	today.earned += earned
	today.tips += tip
	today.delivered += 1
	lifetime.delivered += 1
	lifetime.earned += earned
	lifetime.best_tip = maxi(lifetime.best_tip, tip)
	var rep_delta := -0.25 if late else (0.25 if q.total > 0.85 else (0.1 if q.total > 0.6 else -0.1))
	if q.total > 0.85 and not late:
		today.perfect += 1
	reputation = clampf(reputation + rep_delta, 0.0, 5.0)
	money_changed.emit(money, earned)
	tickets_changed.emit()
	return {"price": price, "tip": tip, "earned": earned, "late": late, "quality": q, "rep": rep_delta}


func fail_ticket(id: int, reason: String) -> void:
	var t := ticket(id)
	if t.is_empty() or t.status in ["delivered", "failed"]:
		return
	t.status = "failed"
	today.failed += 1
	reputation = maxf(0.0, reputation - 0.3)
	tickets_changed.emit()
	toast.emit(reason, Color("#ff5d73"))


func missed_call() -> void:
	today.missed_calls += 1
	reputation = maxf(0.0, reputation - 0.1)
	toast.emit("Missed call! (-reputation)", Color("#ff9f1c"))


# --- money + upgrades ----------------------------------------------------------------

func spend(amount: int, what := "") -> bool:
	if amount > money:
		return false
	money -= amount
	if what == "ingredients":
		today.costs += amount
	money_changed.emit(money, -amount)
	return true


func level(id: String) -> int:
	return int(upgrades.get(id, 0))


func has_upgrade(id: String) -> bool:
	return level(id) > 0


func buy_upgrade(id: String) -> bool:
	var lv := level(id)
	if Upgrades.maxed(id, lv):
		return false
	if not spend(Upgrades.cost(id, lv)):
		return false
	upgrades[id] = lv + 1
	upgrades_changed.emit()
	save_game()
	return true


# --- staff ---------------------------------------------------------------------------

func is_hired(id: String) -> bool:
	return staff.has(id)


func hire(id: String) -> bool:
	if is_hired(id) or not StaffData.CANDIDATES.has(id):
		return false
	if not spend(int(StaffData.CANDIDATES[id].hire)):
		return false
	staff[id] = {"training": 0}
	staff_changed.emit()
	save_game()
	return true


func fire(id: String) -> void:
	if staff.erase(id):
		staff_changed.emit()
		save_game()


func train(id: String) -> bool:
	if not is_hired(id):
		return false
	var lv := int(staff[id].training)
	if lv >= StaffData.TRAIN_MAX or not spend(StaffData.TRAIN_COST * (lv + 1)):
		return false
	staff[id].training = lv + 1
	staff_changed.emit()
	save_game()
	return true


func staff_skill(id: String) -> float:
	return StaffData.skill_of(id, int(staff.get(id, {}).get("training", 0)))


func wages_total() -> int:
	var total := 0
	for id: String in staff:
		total += int(StaffData.CANDIDATES[id].wage)
	return total


func cargo_capacity() -> int:
	return Upgrades.CARGO[level("cargo")]


func current_hat() -> String:
	return Upgrades.HATS[level("hat")]


## Calls per in-game hour; more with reputation and the neon sign.
func call_rate() -> float:
	return 0.75 + reputation * 0.15 + level("neon_sign") * 0.25 + minf(day - 1, 6) * 0.05


func rank_for_day(s: Dictionary) -> String:
	var score: int = s.delivered * 2 + s.perfect * 2 - s.failed * 2 - s.missed_calls
	if score >= 26:
		return "PIZZA GOD (Tony is crying)"
	if score >= 18:
		return "Cheese Wizard"
	if score >= 11:
		return "Certified Slice Slinger"
	if score >= 5:
		return "Mediocre Pizza Person"
	if score > 0:
		return "Pizza Peasant"
	return "Professional Pizza Loser"


func say_toast(text: String, color := Color("#ffd166")) -> void:
	toast.emit(text, color)


# --- saving --------------------------------------------------------------------------

func save_game() -> void:
	var data := {"money": money, "day": day, "reputation": reputation, "upgrades": upgrades, "lifetime": lifetime, "staff": staff}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	money = int(data.get("money", money))
	day = int(data.get("day", day))
	reputation = float(data.get("reputation", reputation))
	var ups: Dictionary = data.get("upgrades", {})
	upgrades = {}
	for k in ups:
		upgrades[k] = int(ups[k])
	staff = {}
	var st: Dictionary = data.get("staff", {})
	for k: String in st:
		if StaffData.CANDIDATES.has(k):
			staff[k] = {"training": int(st[k].get("training", 0))}
	var life: Dictionary = data.get("lifetime", {})
	for k in life:
		lifetime[k] = life[k]


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) and day > 1


func reset_save() -> void:
	money = 40
	day = 1
	reputation = 2.5
	upgrades = {}
	staff = {}
	lifetime = {"delivered": 0, "earned": 0, "best_tip": 0, "days": 0}
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	money_changed.emit(money, 0)
	upgrades_changed.emit()
	staff_changed.emit()
