class_name Conversation
extends Node
## Runs one conversation:
##   "phone" - a customer calls Tony's and orders (Claude fills in the order)
##   "door"  - you knock on a customer's door to deliver
##   "tony"  - chatting with your boss
## Flow: hold T -> record -> speech-to-text -> Claude (or offline brain)
##       -> line shows (+ voice plays) -> game rules apply.

signal ended

var brain: ClaudeBrain
var stt: SpeechToText
var tts: TextToSpeech
var mic: MicRecorder
var offline := OfflineBrain.new()

var ui: DialogueUi
var player: PlayerEgg
var car: PizzaCar
var kitchen: Kitchen
var gags: Gags

var mode := ""
var house: House             ## customer (phone + door)
var speaker: EggBody         ## who's talking on screen (null on the phone)
var character: Dictionary = {}
var active := false
var busy := false
var _ending := false
var _warned_ai := false
var _line_id := 0
var _tony_history: Array = []


func _ready() -> void:
	brain = ClaudeBrain.new()
	stt = SpeechToText.new()
	tts = TextToSpeech.new()
	mic = MicRecorder.new()
	for n in [brain, stt, tts, mic]:
		add_child(n)


# --- starting --------------------------------------------------------------------------------

func start_phone(caller: House) -> void:
	_begin("phone", caller, null, caller.character)
	player.body.phone_mode = true
	ui.open("PHONE: " + caller.display_name(), "Calling from #%d" % caller.number, Settings.has_speech_to_text(), true)
	Sfx.play("blip")
	# Let them talk first: the player "answered" with the standard greeting.
	_ai_turn("(Picked up the phone) Tony's Pizza, what can I get ya?", true)


func start_door(h: House) -> void:
	if h.is_sulking():
		Sfx.play("knock")
		Game.say_toast("Nobody answers. They're still mad at you.", Color("#ff9f1c"))
		return
	h.come_out()
	_begin("door", h, h.resident, h.character)
	Sfx.play("knock")
	player.look_at_point(h.resident.global_position + Vector3(0, 1.15, 0))
	ui.open(h.display_name(), h.character.get("title", ""), Settings.has_speech_to_text(), false)
	await get_tree().create_timer(0.45).timeout
	if active and mode == "door":
		var greet: String = h.character.get("greet", ["Hello?"]).pick_random()
		npc_say(greet, "confused")


func start_tony() -> void:
	_begin("tony", null, kitchen.tony, Characters.TONY)
	player.look_at_point(kitchen.tony.global_position + Vector3(0, 1.15, 0))
	ui.open(Characters.TONY.name, Characters.TONY.title, Settings.has_speech_to_text(), false)
	npc_say(Characters.TONY.greet.pick_random(), "excited")


func _begin(m: String, h: House, who: EggBody, c: Dictionary) -> void:
	mode = m
	house = h
	speaker = who
	character = c
	active = true
	busy = false
	_ending = false
	if h:
		h.turns = 0
	Game.in_dialogue = true
	player.controls_enabled = false
	if speaker:
		_face_each_other()


func _face_each_other() -> void:
	var back := player.global_position - speaker.global_position
	speaker.rotation.y = atan2(back.x, back.z) - (speaker.get_parent() as Node3D).global_rotation.y


func leave() -> void:
	if active and not _ending:
		if mode == "phone":
			Sfx.play("hangup")
		end()


func end() -> void:
	if not active:
		return
	if mic.is_recording():
		mic.stop()
	active = false
	busy = false
	Game.in_dialogue = false
	player.controls_enabled = true
	player.body.talking = false
	player.body.phone_mode = false
	player.clear_look()
	if speaker:
		speaker.talking = false
	if mode == "door" and house and not _has_open_ticket(house):
		var h := house
		get_tree().create_timer(1.0).timeout.connect(_send_inside.bind(h))
	ui.close()
	ended.emit()


func _send_inside(h: House) -> void:
	if not Game.in_dialogue:
		h.go_inside()


func _has_open_ticket(h: House) -> bool:
	for t in Game.open_tickets():
		if t.house == h:
			return true
	return false


# --- player input ---------------------------------------------------------------------------

func push_to_talk_pressed() -> void:
	if not active or busy or _ending:
		return
	if not Settings.has_speech_to_text():
		ui.set_status("Voice chat needs an API key (Settings). Type instead!")
		return
	Sfx.play("mic_on")
	mic.start()
	ui.set_listening(true)
	player.body.talking = true


func push_to_talk_released() -> void:
	if not mic.is_recording():
		return
	Sfx.play("mic_off")
	ui.set_listening(false)
	player.body.talking = false
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
	ui.show_player_line(text)
	_ai_turn(text, false)


func _ai_turn(text: String, silent_player: bool) -> void:
	busy = true
	ui.set_status("%s is thinking..." % character.get("name", "?"))
	if house:
		house.turns += 1
	var reply: Dictionary = {}
	var hist: Array = _tony_history if mode == "tony" else house.history
	if Settings.has_brain():
		reply = await brain.think(character, hist, text, _scene())
		if not active:
			return
		if not reply.get("ok", false):
			if not _warned_ai:
				_warned_ai = true
				Game.say_toast("AI brain unavailable, using backup brain", Color("#ff9f1c"))
			reply = {}
	if reply.is_empty():
		reply = offline.think(character, text, _offline_ctx())
	busy = false
	if house:
		house.mood = clampi(house.mood + int(reply.get("mood_change", 0)), -10, 10)
	npc_say(str(reply.get("say", "...")), str(reply.get("emotion", "confused")))
	ui.set_status("")
	_apply(str(reply.get("action", "none")), int(reply.get("tip", 0)), reply.get("order", {}))


# --- game rules --------------------------------------------------------------------------------

func _held_pizza() -> Pizza:
	var p := player.held as Pizza
	return p if p and p.is_boxed() else null


func _held_is_theirs() -> bool:
	var p := _held_pizza()
	if p == null or house == null:
		return false
	var t := Game.ticket(p.data.ticket)
	return not t.is_empty() and t.house == house


func _apply(action: String, tip: int, order) -> void:
	match mode:
		"phone":
			if action == "place_order" and not _ending:
				var o := ClaudeBrain._clean_order(order)
				if o.is_empty():
					o = Menu.random_order(offline.rng, character.get("favorites", []))
				var t := Game.add_ticket(house, house.display_name(), o)
				Sfx.play("register")
				Game.say_toast("NEW ORDER #%d: %s for %s" % [t.id, Menu.describe(o), house.display_name()], UiTheme.YELLOW)
				ui.set_status("Order written down! (Esc to hang up, or keep chatting)")
				_end_after(4.5)
			elif action == "hang_up":
				_ending = true
				Sfx.play("hangup")
				Game.say_toast("They hung up on you.", Color("#ff9f1c"))
				_end_after(1.5)
		"door":
			if action == "accept_pizza" and _held_is_theirs():
				_ending = true
				var cid := str(character.get("id", ""))
				if cid == "chad" and gags:
					ui.set_status("Chad wants to arm wrestle for the tip...")
					var won: bool = await gags.arm_wrestle()
					if not active:
						return
					if won:
						tip += 8
						speaker.play("shrug")
						Game.say_toast("CHAD: ...RESPECT, BRO. (+tip)", UiTheme.TEAL)
					else:
						tip = 0
						speaker.play("flex")
						player.tumble(player.global_position - speaker.global_position, 0.8)
						Game.say_toast("CHAD WINS. You got flung. No tip, bro.", UiTheme.PINK)
				var p := _held_pizza()
				var tid: int = p.data.ticket
				var result := Game.complete_delivery(tid, p.data, tip)
				player.take_held()
				# They hold the pizza overhead, triumphantly.
				speaker.carrying = true
				p.reparent(speaker.hand_socket, false)
				p.position = Vector3(0, 0.05, 0)
				speaker.express("excited", 3.0)
				speaker.hop()
				Sfx.play("cash")
				_show_receipt(result)
				get_tree().create_timer(3.4).timeout.connect(_finish_handoff.bind(house, p))
				house.set_target(false)
				_end_after(3.5)
			elif action == "steal_pizza" and _held_pizza() and not _held_is_theirs():
				_ending = true
				var p := player.take_held() as Pizza
				speaker.carrying = true
				p.reparent(speaker.hand_socket, false)
				p.position = Vector3(0, 0.05, 0)
				speaker.hop()
				Sfx.play("fail")
				Game.fail_ticket(p.data.ticket, "THEY STOLE PIZZA #%d! Make a new one." % p.data.ticket)
				get_tree().create_timer(2.8).timeout.connect(_finish_handoff.bind(house, p))
				_end_after(3.0)
			elif action == "slam_door":
				_ending = true
				Sfx.play("fail")
				var h := house
				_end_after(1.4)
				get_tree().create_timer(1.5).timeout.connect(func(): h.storm_inside())


## The customer goes inside with their pizza.
func _finish_handoff(h: House, p: Pizza) -> void:
	h.resident.carrying = false
	if is_instance_valid(p):
		if str(h.character.get("id", "")) == "dave" and gags:
			gags.frogify(p)
			Game.say_toast("DAVE: Abracadabra! ...oops. Your box is a frog now.", UiTheme.PINK)
		p.queue_free()


func _show_receipt(r: Dictionary) -> void:
	var q: Dictionary = r.get("quality", {})
	var stars := int(round(float(q.get("total", 0.0)) * 5.0))
	Game.say_toast("DELIVERED! +$%d  (pizza %s, tip $%d%s)" % [r.earned, "%d/5 stars" % stars, r.tip, ", LATE" if r.late else ""], UiTheme.TEAL)


func _end_after(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
	if active:
		end()


## What Claude needs to know about this moment.
func _scene() -> String:
	var parts: PackedStringArray = []
	match mode:
		"phone":
			parts.append("PHONE CALL. You called Tony's Pizza to order. You live at house #%d." % house.number)
			parts.append("Menu: " + Menu.menu_for_ai())
			parts.append("Your usual: " + ", ".join(character.get("favorites", [])) + ".")
			if _has_open_ticket(house):
				parts.append("You've ALREADY placed your order this call; don't place another, just chat or say bye.")
		"door":
			parts.append("DOORSTEP. You live at house #%d. The player knocked on your door." % house.number)
			var mine := _held_is_theirs()
			var held := _held_pizza()
			if mine:
				var t := Game.ticket(held.data.ticket)
				var left := Game.minutes_left(t)
				parts.append("The player is holding YOUR pizza: %s (you ordered: %s)." % [Menu.describe({"size": held.data.size, "sauce": held.data.sauce, "toppings": _unique(held.data.toppings)}), Menu.describe(t.order)])
				var q := Pizza.quality(held.data, t.order)
				if float(q["match"]) < 0.75:
					parts.append("It's NOT quite what you ordered.")
				parts.append("The pizza is " + Pizza.describe_condition(held.data) + ".")
				parts.append("It's on time." if left >= 0.0 else "It's LATE by %d minutes." % int(-left))
			elif held:
				parts.append("The player is holding a pizza for a DIFFERENT house (#%d), not yours." % Game.ticket(held.data.ticket).get("house").number)
			elif _has_open_ticket(house):
				parts.append("You're waiting for your pizza, but the player came to the door EMPTY-HANDED (your pizza is probably in their car or not made yet).")
			else:
				parts.append("You didn't order anything right now. The player just knocked for no reason.")
			parts.append("Your opinion of the player: %d (-10 hate, 0 neutral, 10 love). Exchanges this visit: %d." % [house.mood, house.turns])
		"tony":
			parts.append("You're at your pizza shop talking to your employee (the player). It's %s on day %d. They've made $%d today. Reputation: %.1f stars. Open orders: %d." % [Game.clock_text(), Game.day, Game.today.get("earned", 0), Game.reputation, Game.open_tickets().size()])
	return " ".join(parts)


func _offline_ctx() -> Dictionary:
	return {
		"mode": mode,
		"mood": house.mood if house else 0,
		"turns": house.turns if house else 0,
		"has_my_pizza": _held_is_theirs(),
		"has_other_pizza": _held_pizza() != null and not _held_is_theirs(),
		"pizza_in_car": house != null and car.pizza_for_house(house) != null,
	}


static func _unique(arr: Array) -> Array:
	var out: Array = []
	for a in arr:
		if a not in out:
			out.append(a)
	return out


# --- NPC speech ---------------------------------------------------------------------------------

func npc_say(text: String, emotion := "") -> void:
	_line_id += 1
	var my_line := _line_id
	ui.show_npc_line(character.get("name", "?"), text)
	if speaker:
		if emotion != "":
			speaker.express(emotion, 4.0)
		speaker.talking = true
	var result := await tts.synthesize(text, character)
	if my_line != _line_id:
		return
	var voice_player: Node = null
	if result.stream:
		voice_player = _play_voice(result.stream)
	# Keep the mouth flapping while the line plays (or for a bit, text-only).
	var until := Time.get_ticks_msec() + int(clampf(text.length() * 55.0, 900.0, 5000.0))
	while my_line == _line_id:
		var playing := (voice_player != null and is_instance_valid(voice_player) and (voice_player as AudioStreamPlayer).playing) or DisplayServer.tts_is_speaking()
		if not playing and (voice_player != null or Time.get_ticks_msec() > until):
			break
		await get_tree().process_frame
	if my_line == _line_id and speaker:
		speaker.talking = false


func _play_voice(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = linear_to_db(maxf(Settings.voice_volume, 0.0001))
	if mode == "phone":
		p.pitch_scale = 1.0
		p.bus = "Master"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p
