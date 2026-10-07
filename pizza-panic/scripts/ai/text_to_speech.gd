class_name TextToSpeech
extends Node
## Gives NPCs a voice.
##   openai     - gpt-4o-mini-tts, which takes acting directions ("talk like a
##                dramatic ghost"), so every character sounds different.
##   elevenlabs - the most natural voices; each character has a voice id.
##   system     - the computer's built-in robot voice (free, offline).
##   babble     - Animal Crossing style gibberish (free, offline, very goofy).

const OPENAI_MODEL := "gpt-4o-mini-tts"
const ELEVENLABS_MODEL := "eleven_flash_v2_5"
const GLOBAL_STYLE := " This is a goofy cartoon comedy game, so ham it up like an over-the-top anime dub."

var last_error := ""
var _action_regex := RegEx.create_from_string("\\*[^*]*\\*")


## Returns {"stream": AudioStream or null, "system": bool}.
## When "system" is true the OS is already speaking the line.
func synthesize(text: String, character: Dictionary) -> Dictionary:
	var spoken := _action_regex.sub(text, "", true).strip_edges()
	var voice: Dictionary = character.get("voice", {})
	if spoken == "":
		return {"stream": null, "system": false}
	match Settings.voice_engine():
		"openai":
			var s := await _openai(spoken, voice)
			if s:
				return {"stream": s, "system": false}
		"elevenlabs":
			var s := await _elevenlabs(spoken, voice)
			if s:
				return {"stream": s, "system": false}
		"system":
			if _system(spoken, voice):
				return {"stream": null, "system": true}
	# Anything failed (or offline): gibberish it is.
	return {"stream": Sfx.babble(spoken, voice.get("babble", 220.0), voice.get("speed", 1.0)), "system": false}


func _openai(text: String, voice: Dictionary) -> AudioStream:
	var body := {
		"model": OPENAI_MODEL,
		"voice": voice.get("openai", "alloy"),
		"input": text,
		"instructions": str(voice.get("style", "")) + GLOBAL_STYLE,
		"response_format": "mp3",
	}
	var headers := PackedStringArray(["Content-Type: application/json", Settings.openai_auth_header()])
	var bytes := await _post(Settings.openai_url("/v1/audio/speech"), headers, JSON.stringify(body))
	return _mp3(bytes)


func _elevenlabs(text: String, voice: Dictionary) -> AudioStream:
	var body := {
		"text": text,
		"model_id": ELEVENLABS_MODEL,
		"voice_settings": {"stability": 0.3, "similarity_boost": 0.75, "style": 0.6},
	}
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: audio/mpeg", Settings.elevenlabs_auth_header()])
	var path := "/v1/text-to-speech/%s?output_format=mp3_44100_128" % voice.get("eleven", "pNInz6obpgDQGcFmaJgB")
	var bytes := await _post(Settings.elevenlabs_url(path), headers, JSON.stringify(body))
	return _mp3(bytes)


func _system(text: String, voice: Dictionary) -> bool:
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		return false
	var pitch := clampf(remap(voice.get("babble", 220.0), 110.0, 420.0, 0.6, 1.8), 0.0, 2.0)
	var rate := clampf(voice.get("speed", 1.0), 0.5, 2.0)
	var pick: String = voices[hash(text.left(1) + str(voice.get("openai", ""))) % voices.size()]
	DisplayServer.tts_speak(text, pick, int(Settings.voice_volume * 100.0), pitch, rate, 0, true)
	return true


func _post(url: String, headers: PackedStringArray, body: String) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	if http.request(url, headers, HTTPClient.METHOD_POST, body) != OK:
		http.queue_free()
		last_error = "Couldn't start voice request"
		return PackedByteArray()
	var res: Array = await http.request_completed
	http.queue_free()
	var raw: PackedByteArray = res[3]
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		last_error = "Voice HTTP %d: %s" % [res[1], raw.get_string_from_utf8().left(300)]
		push_warning("[TextToSpeech] " + last_error)
		return PackedByteArray()
	return raw


func _mp3(bytes: PackedByteArray) -> AudioStream:
	if bytes.size() < 64:
		return null
	return AudioStreamMP3.load_from_buffer(bytes)
