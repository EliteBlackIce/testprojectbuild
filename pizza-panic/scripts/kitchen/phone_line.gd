class_name PhoneLine
extends Node
## Tony's phone. Customers call in at random (more often with better
## reputation and the Neon Sign). Answer within RING_TIME or they hang up.

signal ringing_changed(caller: House)

const RING_TIME := 22.0
const BASE_OPEN_TICKETS := 3

var town: Town
var caller: House = null
var ring_left := 0.0
var _next_call := 14.0
var _ring_sound := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func reset() -> void:
	caller = null
	ring_left = 0.0
	_next_call = 14.0
	ringing_changed.emit(null)


## Never more waiting orders than you can sensibly handle: 3 to start, +1 per two hired eggs.
func max_open() -> int:
	return mini(BASE_OPEN_TICKETS + Game.staff.size() / 2 + Game.level("cargo") / 2, 6)


func is_ringing() -> bool:
	return caller != null


func _process(delta: float) -> void:
	if not Game.day_running or Game.in_dialogue:
		return
	if caller:
		ring_left -= delta
		_ring_sound -= delta
		if _ring_sound <= 0.0:
			_ring_sound = 1.6
			Sfx.play("ring", 1.0, -4.0)
		if ring_left <= 0.0:
			caller = null
			Game.missed_call()
			Sfx.play("hangup")
			ringing_changed.emit(null)
		return
	if Game.is_last_call() or Game.open_tickets().size() >= max_open():
		return
	_next_call -= delta
	if _next_call <= 0.0:
		# Game minutes between calls -> real seconds.
		var minutes := 60.0 / Game.call_rate()
		_next_call = rng.randf_range(0.6, 1.4) * minutes * Game.SECONDS_PER_MINUTE
		ring()


## Starts a call from a random customer who isn't already waiting.
func ring(from: House = null) -> void:
	if caller:
		return
	if from == null:
		var busy := {}
		for t in Game.open_tickets():
			busy[t.house] = true
		var options: Array[House] = []
		for h in town.houses:
			if not busy.has(h) and not h.is_sulking():
				options.append(h)
		if options.is_empty():
			return
		from = options[rng.randi() % options.size()]
	caller = from
	ring_left = RING_TIME
	_ring_sound = 0.0
	ringing_changed.emit(caller)


## Picks up. Returns the caller (and clears the ring).
func answer() -> House:
	var h := caller
	caller = null
	ringing_changed.emit(null)
	return h
