extends Node
## Tests the whole AI pipeline (Claude brain, speech-to-text, voices) against
## tests/mock_ai_server.py, so it runs without real API keys:
##   python3 tests/mock_ai_server.py 8787 some.mp3 /tmp/requests.log &
##   godot --headless --path . res://tests/ai_pipeline_test.tscn

var main: Node
var failures: PackedStringArray = []


func _ready() -> void:
	Settings.ai_mode = "proxy"   # in memory only; never saved by this test
	Settings.proxy_url = "http://127.0.0.1:8787"
	Settings.proxy_token = "test-token"
	Settings.tts_provider = "auto"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start_shift()
	check(Settings.has_brain() and Settings.has_speech_to_text(), "proxy mode enables brain + voice input")
	check(Settings.voice_engine() == "openai", "proxy mode uses OpenAI voices (got %s)" % Settings.voice_engine())

	var gary: Dictionary = Characters.ROSTER[0]

	# 1. Claude brain
	var history: Array = []
	var r: Dictionary = await main.convo.brain.think(gary, history, "hello", "test context")
	check(r.get("ok", false) and str(r.get("say", "")) != "", "Claude reply parsed: %s" % str(r.get("say", r.get("error", ""))))
	check(history.size() == 2, "history grew by one exchange")
	check(history.size() == 2 and history[1].content.size() == 1 and history[1].content[0].type == "text", "only text (no thinking blocks) kept in history")
	r = await main.convo.brain.think(gary, history, "still hello", "test context")
	check(r.get("ok", false) and history.size() == 4, "second turn works with history")

	# 2. Speech to text
	var clip := Sfx.babble("here is your tuba gary", 200.0)
	clip.save_to_wav("user://test_clip.wav")
	var wav := FileAccess.get_file_as_bytes("user://test_clip.wav")
	var heard: String = await main.convo.stt.transcribe(wav)
	check(heard == "Here's your tuba, Gary!", "transcription: '%s' %s" % [heard, main.convo.stt.last_error])

	# 3. Voice
	var voice: Dictionary = await main.convo.tts.synthesize("*waves* Hello there!", gary)
	check(voice.stream is AudioStreamMP3, "OpenAI voice decoded as MP3 (%s)" % main.convo.tts.last_error)

	# 4. Full delivery: Tony gives an order, we steer it to a Gary house,
	# then "say" the transcribed line and Claude accepts the pizza.
	var gary_house: House = null
	for h in main.town.houses:
		if h.resident.character.id == "gary":
			gary_house = h
			break
	if gary_house == null:
		gary_house = main.town.houses[0]
		gary_house.resident.character = gary
	main.convo.start(main.town.shop)
	await _seconds(0.3)
	main.convo.end()
	check(Game.has_order(), "got an order")
	Game.order.house = gary_house
	Game.order_changed.emit(Game.order)
	main.convo.start(gary_house)
	await _seconds(0.7)
	main.convo.player_says(heard)
	for i in 50:
		if Game.deliveries > 0:
			break
		await _seconds(0.1)
	check(Game.deliveries == 1, "Claude accepted the pizza through the real conversation flow")
	check(Game.money >= 12 + 9, "paid base + Claude's tip ($%d)" % Game.money)

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
