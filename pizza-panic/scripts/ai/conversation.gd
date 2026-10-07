class_name Conversation
extends Node
## Runs a talk with one NPC:
##   hold T -> record mic -> speech-to-text -> Claude (or offline brain)
##   -> NPC line shows + voice plays -> game rules apply (pay, steal, slam...)

signal ended

var brain: ClaudeBrain
var stt: SpeechToText
var tts: TextToSpeech
var mic: MicRecorder
var offline := OfflineBrain.new()

var ui: DialogueUi
var car: PizzaCar
var camera: ChaseCamera
var town: Town

var house: House
var npc: Npc
var active := false
var busy := false
var _ending := false
var _warned_ai := false
var _line_id := 0


func _ready() -> void:
	brain = ClaudeBrain.new()
	stt = SpeechToText.new()
	tts = TextToSpeech.new()
	mic = MicRecorder.new()
	for n in [brain, stt, tts, mic]:
		add_child(n)


func start(h: House) -> void:
	if active:
		return
	house = h
	npc = h.resident
	active = true
	busy = false
	_ending = false
	npc.turns = 0
	Game.in_dialogue = true
	car.controls_enabled = false
	camera.focus_npc = npc
	npc.look_target = car
	ui.open(npc.display_name(), npc.character.get("title", ""), Settings.has_speech_to_text())
	Sfx.play("knock")

	if npc.hidden_inside:
		ui.show_npc_line("(nobody)", "*They're still inside sulking. Try again later.*")
		_end_after(2.0)
		return

	if house.is_shop:
		_tony_greeting()
	else:
		await get_tree().create_timer(0.5).timeout
		if active:
			npc_say(npc.character.get("greet", ["Hello?"]).pick_random(), "confused")


func _tony_greeting() -> void:
	if not Game.has_order():
		var choices := town.houses.filter(func(x): return x != house)
		var target: House = choices.pick_random()
		var dist := target.stop_point.distance_to(house.stop_point)
		var o := Game.new_order(target, dist)
		Sfx.play("pickup")
		npc_say("Order up! %s for house number %d! You got %d seconds! GO GO GO!" % [o.pizza, target.number, int(o.time_limit)], "excited")
	else:
		npc_say("House number %d! Why are you still HERE?!" % Game.order.house.number, "angry")


func leave() -> void:
	if active and not _ending:
		end()


func end() -> void:
	if not active:
		return
	if mic.is_recording():
		mic.stop()
	active = false
	busy = false
	Game.in_dialogue = false
	car.controls_enabled = true
	camera.focus_npc = null
	if npc:
		npc.look_target = null
		npc.set_talking(false)
	ui.close()
	ended.emit()


# --- player input ----------------------------------------------------------------

func push_to_talk_pressed() -> void:
	if not active or busy or _ending:
		return
	if not Settings.has_speech_to_text():
		ui.set_status("Voice chat needs an API key (Settings). Type instead!")
		return
	Sfx.play("mic_on")
	mic.start()
	ui.set_listening(true)


func push_to_talk_released() -> void:
	if not mic.is_recording():
		return
	Sfx.play("mic_off")
	ui.set_listening(false)
	var wav := mic.stop()
	if wav.is_empty():
		ui.set_status("Hold T while you talk!")
		return
	busy = true
	ui.set_status("Listening really hard...")
	var text := await stt.transcribe(wav)
	busy = false
	if not active:
		return
	if text == "":
		ui.set_status("Didn't catch that. " + ("(" + stt.last_error.left(80) + ")" if stt.last_error != "" else "Try again?"))
		stt.last_error = ""
		return
	player_says(text)


func player_says(text: String) -> void:
	text = text.strip_edges()
	if not active or busy or _ending or text == "":
		return
	busy = true
	ui.show_player_line(text)
	ui.set_status("%s is thinking..." % npc.display_name())
	npc.turns += 1

	var for_me: bool = Game.has_order() and Game.order.house == house
	var reply: Dictionary = {}
	if Settings.has_brain():
		reply = await brain.think(npc.character, npc.history, text, _context(for_me))
		if not active:
			return
		if not reply.get("ok", false):
			if not _warned_ai:
				_warned_ai = true
				Game.say_toast("AI brain unavailable, using backup brain", Color("#ff9f1c"))
				push_warning(reply.get("error", ""))
			reply = {}
	if reply.is_empty():
		reply = offline.think(npc.character, text, {
			"mood": npc.mood, "pizza_for_me": for_me, "carrying": Game.has_order(),
			"turns": npc.turns, "is_boss": house.is_shop,
		})

	npc.mood = clampi(npc.mood + int(reply.get("mood_change", 0)), -10, 10)
	var action: String = reply.get("action", "none")
	# The game, not the AI, has the final say on what's possible.
	if house.is_shop:
		action = "none"
	elif action == "accept_pizza" and not for_me:
		action = "refuse_pizza"
	elif action == "steal_pizza" and (for_me or not Game.has_order()):
		action = "none"

	npc_say(str(reply.get("say", "...")), str(reply.get("emotion", "confused")))
	ui.set_status("")
	busy = false
	_apply_action(action, int(reply.get("tip", 0)))


func _apply_action(action: String, tip: int) -> void:
	match action:
		"accept_pizza":
			_ending = true
			var earned := Game.complete_delivery(tip)
			Sfx.play("cash")
			npc.celebrate()
			house.set_target(false)
			Game.say_toast("DELIVERED! +$%d" % earned, Color("#06d6a0"))
			_end_after(3.5)
		"steal_pizza":
			_ending = true
			npc.celebrate()
			Sfx.play("fail")
			Game.fail_delivery("THEY STOLE THE PIZZA. Back to Tony's!")
			_end_after(3.0)
		"slam_door":
			_ending = true
			Sfx.play("fail")
			npc.storm_inside()
			_end_after(1.6)


func _end_after(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
	if active:
		end()


func _context(for_me: bool) -> String:
	if house.is_shop:
		if Game.has_order():
			return "You're at your pizza shop. The player is holding the order for house #%d (%s) and should be out delivering it RIGHT NOW. Money earned this shift: $%d." % [Game.order.house.number, Game.order.pizza, Game.money]
		return "You're at your pizza shop. The player has no pizza right now. Money earned this shift: $%d." % Game.money
	var parts: PackedStringArray = []
	parts.append("You live at house #%d." % house.number)
	if not Game.has_order():
		parts.append("The player is NOT carrying any pizza (they just knocked on your door for no reason).")
	elif for_me:
		var left := Game.order_seconds_left()
		parts.append("The player is carrying YOUR pizza: %s." % Game.order.pizza)
		parts.append("Pizza condition: %d%% (100 = perfect, under 40 = basically destroyed from car crashes)." % int(Game.pizza_hp))
		if left >= 0.0:
			parts.append("It's on time (%d seconds to spare)." % int(left))
		else:
			parts.append("It's LATE by %d seconds." % int(-left))
	else:
		parts.append("The player is carrying a pizza for a DIFFERENT house (#%d), not you." % Game.order.house.number)
	parts.append("Your opinion of the player: %d (-10 hate, 0 neutral, 10 love)." % npc.mood)
	parts.append("Exchanges this visit: %d." % npc.turns)
	return " ".join(parts)


# --- NPC speech -------------------------------------------------------------------

func npc_say(text: String, emotion := "") -> void:
	_line_id += 1
	var my_line := _line_id
	ui.show_npc_line(npc.display_name(), text)
	if emotion != "":
		npc.show_emotion(emotion)
	npc.set_talking(true)
	var result := await tts.synthesize(text, npc.character)
	if my_line != _line_id or npc == null:
		return
	if result.stream:
		npc.say(result.stream)
	# Stop the talking animation once the voice is done.
	while is_instance_valid(npc) and npc.is_speaking() and my_line == _line_id:
		await get_tree().process_frame
	if my_line == _line_id and is_instance_valid(npc):
		npc.set_talking(false)
