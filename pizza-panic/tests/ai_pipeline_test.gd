extends Node
## Tests the AI pipeline (Claude phone orders + doorstep, speech-to-text,
## voices, text-only mode) against tests/mock_ai_server.py, without real keys:
##   python3 tests/mock_ai_server.py 8787 some.mp3 /tmp/requests.log &
##   godot --headless --path . res://tests/ai_pipeline_test.tscn

var main: Node
var failures: PackedStringArray = []


func _ready() -> void:
	Settings.ai_mode = "proxy"   # in memory only; points at the mock server
	Settings.proxy_url = "http://127.0.0.1:8787"
	Settings.proxy_token = "test-token"
	Settings.tts_provider = "auto"
	Settings.reply_mode = "voice"
	Game.reset_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start_game(true)
	check(Settings.has_brain() and Settings.has_speech_to_text(), "AI brain + voice input enabled")

	# 1. Speech to text
	var clip := Sfx.babble("here is your tuba gary", 200.0)
	clip.save_to_wav("user://test_clip.wav")
	var wav := FileAccess.get_file_as_bytes("user://test_clip.wav")
	var heard: String = await main.convo.stt.transcribe(wav)
	check(heard == "Here's your tuba, Gary!", "transcription works ('%s')" % heard)

	# 2. Voices: OpenAI MP3, and text-only mode makes no audio
	var gary: Dictionary = Characters.ROSTER[0]
	var voice: Dictionary = await main.convo.tts.synthesize("*waves* Hello there!", gary)
	check(voice.stream is AudioStreamMP3, "AI voice decoded as MP3")
	Settings.reply_mode = "text"
	voice = await main.convo.tts.synthesize("Hello there!", gary)
	check(voice.stream == null, "text-only replies make no audio")
	Settings.reply_mode = "voice"

	# 3. Phone order placed by Claude
	var house: House = main.town.houses[4]
	main.phone.ring(house)
	main._answer_phone()
	for i in 40:
		if not Game.open_tickets().is_empty():
			break
		await _seconds(0.1)
	check(Game.open_tickets().size() == 1, "Claude placed an order over the phone")
	var t: Dictionary = Game.open_tickets()[0] if not Game.open_tickets().is_empty() else {}
	check(not t.is_empty() and t.order.toppings == ["pepperoni", "onion"] and t.order.size == "medium", "ticket matches Claude's order")
	await _seconds(5.0)
	check(not main.convo.active, "call wrapped up")

	# 4. Make it (fast-forward), deliver it, Claude accepts + tips
	var p := Pizza.new()
	add_child(p)
	p.setup(t.id)
	p.auto_assemble(t.order, 1.0)
	p.set_bake(1.0)
	p.data.baked = true
	p.data.heat = 100.0
	p.auto_cut(1.0)
	p.put_in_box(true)
	main.player.hold(p)
	main.player.global_position = house.knock_spot.global_position + Vector3(0, -0.85, 0)
	await get_tree().physics_frame
	main._on_knock(house, main.player)
	await _seconds(0.7)
	main.convo.player_says(heard)
	for i in 50:
		if Game.today.delivered > 0:
			break
		await _seconds(0.1)
	check(Game.today.delivered == 1, "Claude accepted the pizza at the door")
	check(Game.today.tips >= 9, "Claude's tip was paid (tips $%d)" % Game.today.tips)

	# 5. Tony chats through Claude too
	await _seconds(4.0)
	main.convo.start_tony()
	main.convo.player_says("hey tony")
	await _seconds(1.0)
	check(main.convo._tony_history.size() == 2, "Tony conversation used Claude")
	main.convo.leave()

	if failures.is_empty():
		print("AI PIPELINE TEST PASSED")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		get_tree().quit(1)


func check(cond: bool, msg: String) -> void:
	print(("ok   - " if cond else "FAIL - ") + msg)
	if not cond:
		failures.append(msg)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
