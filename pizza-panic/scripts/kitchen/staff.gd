class_name Staff
extends Node
## Spawns the eggs you've hired (see StaffData) into the kitchen each day,
## and adds/removes them when you hire or fire from Tony's PC.

var kitchen: Kitchen
var phone: PhoneLine
var workers: Dictionary = {}   ## id -> Worker


func _ready() -> void:
	Game.staff_changed.connect(sync)


## Make the people in the kitchen match who's on the payroll.
func sync() -> void:
	for id: String in workers.keys():
		if not Game.is_hired(id):
			(workers[id] as Worker).quit()
			workers.erase(id)
	var slot := 0
	for id: String in Game.staff:
		if StaffData.CANDIDATES[id].role == "cook":
			slot += 1
		if workers.has(id):
			continue
		var w := Worker.new()
		kitchen.pizzeria.add_child(w)
		# They clock in right at their post.
		var post: int = 14 if StaffData.CANDIDATES[id].role == "phone" else Worker.BOARD_NODES[(slot - 1) % Worker.BOARDS.size()]
		w.position = Worker.NODES[post]
		w.setup(id, kitchen, phone, (slot - 1) % Worker.BOARDS.size())
		workers[id] = w
	kitchen.pizzeria.set_staff_board(roster_lines())


## Everyone clocks out (end of day / back to title).
func clear() -> void:
	for id: String in workers:
		(workers[id] as Worker).quit()
	workers.clear()


func roster_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for id: String in Game.staff:
		var c: Dictionary = StaffData.CANDIDATES[id]
		out.append("%s (%s) $%d/day" % [c.name, "cook" if c.role == "cook" else "phones", c.wage])
	return out
