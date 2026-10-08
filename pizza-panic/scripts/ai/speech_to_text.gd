class_name SpeechToText
extends Node
## Turns a WAV recording of the player into text.
## Uses OpenAI's transcription API, or ElevenLabs Scribe if that's the only key.

const OPENAI_MODEL := "gpt-4o-mini-transcribe"
const ELEVENLABS_MODEL := "scribe_v1"
## Helps the transcriber spell our silly words right.
const PROMPT_HINT := "Pizza delivery conversation. Words: pizza, pepperoni, Tony, tuba, Kevin, Grandma, bro, wizard, abracadabra, Sparkle-chan, rival, sensei, grasshopper, synergy, NPC, woof, good boy, boo, goo goo gaga."

var last_error := ""


## Returns the transcript, or "" on failure.
func transcribe(wav: PackedByteArray) -> String:
	if wav.is_empty():
		return ""
	var boundary := "----PizzaPanic%d" % randi()
	var url: String
	var headers := PackedStringArray()
	var body: PackedByteArray
	if Settings.stt_provider() == "local":
		# OpenAI-style endpoint served by tools/voice_server (faster-whisper).
		url = Settings.local_voice_url.trim_suffix("/") + "/v1/audio/transcriptions"
		body = _multipart(boundary, {"model": "whisper", "language": "en", "prompt": PROMPT_HINT}, "file", wav)
	elif Settings.stt_provider() == "openai":
		url = Settings.openai_url("/v1/audio/transcriptions")
		headers.append(Settings.openai_auth_header())
		body = _multipart(boundary, {"model": OPENAI_MODEL, "language": "en", "prompt": PROMPT_HINT}, "file", wav)
	else:
		url = Settings.elevenlabs_url("/v1/speech-to-text")
		headers.append(Settings.elevenlabs_auth_header())
		body = _multipart(boundary, {"model_id": ELEVENLABS_MODEL, "language_code": "en"}, "file", wav)
	headers.append("Content-Type: multipart/form-data; boundary=" + boundary)

	var http := HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	var err := http.request_raw(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return _fail("Couldn't start transcription (error %d)" % err)
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return _fail("Network problem (result %d)" % res[0])
	var raw: PackedByteArray = res[3]
	var data = JSON.parse_string(raw.get_string_from_utf8())
	if res[1] != 200 or typeof(data) != TYPE_DICTIONARY:
		return _fail("Transcription HTTP %d: %s" % [res[1], raw.get_string_from_utf8().left(300)])
	return str(data.get("text", "")).strip_edges()


func _multipart(boundary: String, fields: Dictionary, file_field: String, file_bytes: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	for key in fields:
		out.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, key, fields[key]]).to_utf8_buffer())
	out.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % [boundary, file_field]).to_utf8_buffer())
	out.append_array(file_bytes)
	out.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	return out


func _fail(msg: String) -> String:
	last_error = msg
	push_warning("[SpeechToText] " + msg)
	return ""
