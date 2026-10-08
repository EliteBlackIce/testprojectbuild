extends Node
## Player settings + AI service configuration.
##
## Saved to user://settings.cfg. API keys can also come from environment
## variables (ANTHROPIC_API_KEY, OPENAI_API_KEY, ELEVENLABS_API_KEY), which is
## handy while developing so keys never end up in the project folder.
##
## AI modes:
##   "auto"    - use direct keys if any are set, otherwise offline.
##   "offline" - no internet. Scripted dialogue, typed input, babble voices.
##   "direct"  - the game calls Anthropic / OpenAI / ElevenLabs with your own keys.
##               Fine for development. NEVER ship a build with keys baked in.
##   "proxy"   - the game calls YOUR server (see server/), which holds the keys.
##               This is what the Steam release should use.

signal changed

const PATH := "user://settings.cfg"

var ai_mode := "auto"
var anthropic_key := ""
var openai_key := ""
var elevenlabs_key := ""
var proxy_url := ""
var proxy_token := ""
var claude_model := "claude-opus-5-5"
var claude_effort := "low"
## "auto" picks ElevenLabs if that key exists, else OpenAI, else babble.
## Other values: "elevenlabs", "openai", "system" (OS robot voice), "babble".
var tts_provider := "auto"
var master_volume := 0.8
var voice_volume := 1.0
var music_volume := 0.6
var show_hints := true
var mouse_sensitivity := 1.0
var show_subtitles := true
## How NPCs answer: "voice" (spoken + text) or "text" (text only, no AI voice).
var reply_mode := "voice"


func _ready() -> void:
	load_settings()
	_register_inputs()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		ai_mode = cfg.get_value("ai", "mode", ai_mode)
		anthropic_key = cfg.get_value("ai", "anthropic_key", "")
		openai_key = cfg.get_value("ai", "openai_key", "")
		elevenlabs_key = cfg.get_value("ai", "elevenlabs_key", "")
		proxy_url = cfg.get_value("ai", "proxy_url", "")
		proxy_token = cfg.get_value("ai", "proxy_token", "")
		claude_model = cfg.get_value("ai", "claude_model", claude_model)
		claude_effort = cfg.get_value("ai", "claude_effort", claude_effort)
		tts_provider = cfg.get_value("ai", "tts_provider", tts_provider)
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
		voice_volume = cfg.get_value("audio", "voice_volume", voice_volume)
		music_volume = cfg.get_value("audio", "music_volume", music_volume)
		show_hints = cfg.get_value("game", "show_hints", show_hints)
		mouse_sensitivity = cfg.get_value("game", "mouse_sensitivity", mouse_sensitivity)
		show_subtitles = cfg.get_value("game", "show_subtitles", show_subtitles)
		reply_mode = cfg.get_value("ai", "reply_mode", reply_mode)
	_apply_audio()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ai", "mode", ai_mode)
	cfg.set_value("ai", "anthropic_key", anthropic_key)
	cfg.set_value("ai", "openai_key", openai_key)
	cfg.set_value("ai", "elevenlabs_key", elevenlabs_key)
	cfg.set_value("ai", "proxy_url", proxy_url)
	cfg.set_value("ai", "proxy_token", proxy_token)
	cfg.set_value("ai", "claude_model", claude_model)
	cfg.set_value("ai", "claude_effort", claude_effort)
	cfg.set_value("ai", "tts_provider", tts_provider)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "voice_volume", voice_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("game", "show_hints", show_hints)
	cfg.set_value("game", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("game", "show_subtitles", show_subtitles)
	cfg.set_value("ai", "reply_mode", reply_mode)
	cfg.save(PATH)
	_apply_audio()
	changed.emit()


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))


# --- Keys (settings file first, then environment variables) -----------------

func get_anthropic_key() -> String:
	return anthropic_key if anthropic_key != "" else OS.get_environment("ANTHROPIC_API_KEY")


func get_openai_key() -> String:
	return openai_key if openai_key != "" else OS.get_environment("OPENAI_API_KEY")


func get_elevenlabs_key() -> String:
	return elevenlabs_key if elevenlabs_key != "" else OS.get_environment("ELEVENLABS_API_KEY")


## The mode actually in effect after resolving "auto".
func effective_mode() -> String:
	if ai_mode == "auto":
		if proxy_url != "":
			return "proxy"
		if get_anthropic_key() != "":
			return "direct"
		return "offline"
	return ai_mode


func online() -> bool:
	return effective_mode() != "offline"


## Can NPCs think with Claude?
func has_brain() -> bool:
	match effective_mode():
		"proxy":
			return proxy_url != ""
		"direct":
			return get_anthropic_key() != ""
	return false


## Can we turn the player's voice into text?
func has_speech_to_text() -> bool:
	match effective_mode():
		"proxy":
			return proxy_url != ""
		"direct":
			return get_openai_key() != "" or get_elevenlabs_key() != ""
	return false


## Which voice engine NPCs use ("none" = text-only replies).
func voice_engine() -> String:
	if reply_mode == "text":
		return "none"
	var mode := effective_mode()
	if tts_provider in ["system", "babble"]:
		return tts_provider
	if mode == "offline":
		return "babble"
	if mode == "proxy":
		return "openai" if tts_provider == "auto" else tts_provider
	if tts_provider == "elevenlabs" and get_elevenlabs_key() != "":
		return "elevenlabs"
	if tts_provider == "openai" and get_openai_key() != "":
		return "openai"
	if tts_provider == "auto":
		if get_elevenlabs_key() != "":
			return "elevenlabs"
		if get_openai_key() != "":
			return "openai"
	return "babble"


# --- Endpoints (direct vs proxy) --------------------------------------------

func anthropic_url(path: String) -> String:
	if effective_mode() == "proxy":
		return proxy_url.trim_suffix("/") + "/anthropic" + path
	return "https://api.anthropic.com" + path


func openai_url(path: String) -> String:
	if effective_mode() == "proxy":
		return proxy_url.trim_suffix("/") + "/openai" + path
	return "https://api.openai.com" + path


func elevenlabs_url(path: String) -> String:
	if effective_mode() == "proxy":
		return proxy_url.trim_suffix("/") + "/elevenlabs" + path
	return "https://api.elevenlabs.io" + path


func anthropic_headers() -> PackedStringArray:
	var h := PackedStringArray([
		"content-type: application/json",
		"anthropic-version: 2023-06-01",
		"anthropic-beta: server-side-fallback-2026-07-01",
	])
	if effective_mode() == "proxy":
		h.append("x-game-token: " + proxy_token)
	else:
		h.append("x-api-key: " + get_anthropic_key())
	return h


func openai_auth_header() -> String:
	if effective_mode() == "proxy":
		return "x-game-token: " + proxy_token
	return "Authorization: Bearer " + get_openai_key()


func elevenlabs_auth_header() -> String:
	if effective_mode() == "proxy":
		return "x-game-token: " + proxy_token
	return "xi-api-key: " + get_elevenlabs_key()


func stt_provider() -> String:
	if effective_mode() == "proxy":
		return "openai"
	return "openai" if get_openai_key() != "" else "elevenlabs"


# --- Input map ----------------------------------------------------------------
# Registered in code so the bindings are easy to read and change in one place.

const BINDINGS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"hop": [KEY_SPACE],
	"interact": [KEY_E],
	"push_to_talk": [KEY_T],
	"honk": [KEY_H],
	"pause": [KEY_ESCAPE],
	"respawn": [KEY_R],
	"car": [KEY_F],
	"boost": [KEY_SHIFT],
	"answer_phone": [KEY_Q],
	"cam_left": [KEY_BRACKETLEFT],
	"cam_right": [KEY_BRACKETRIGHT],
	"tickets": [KEY_TAB],
	"view": [KEY_V],
	"poke": [],
	"tool_alt": [],
	"look_left": [],
	"look_right": [],
	"look_up": [],
	"look_down": [],
}
const PAD_BUTTONS := {
	"accelerate": [JOY_BUTTON_RIGHT_SHOULDER],
	"brake": [JOY_BUTTON_LEFT_SHOULDER],
	"hop": [JOY_BUTTON_A],
	"interact": [JOY_BUTTON_X],
	"push_to_talk": [JOY_BUTTON_Y],
	"honk": [JOY_BUTTON_B],
	"pause": [JOY_BUTTON_START],
	"respawn": [JOY_BUTTON_BACK],
	"car": [JOY_BUTTON_LEFT_STICK],
	"boost": [JOY_BUTTON_RIGHT_STICK],
	"answer_phone": [JOY_BUTTON_DPAD_UP],
	"cam_left": [JOY_BUTTON_DPAD_LEFT],
	"cam_right": [JOY_BUTTON_DPAD_RIGHT],
	"view": [JOY_BUTTON_DPAD_DOWN],
	"poke": [JOY_BUTTON_RIGHT_SHOULDER],
}


func _register_inputs() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		for button in PAD_BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = button
			InputMap.action_add_event(action, jb)
	# Left stick steering + triggers for gas/brake.
	_add_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis("accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_axis("accelerate", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis("brake", JOY_AXIS_LEFT_Y, 1.0)
	# Right stick looks around (first person).
	_add_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	# Mouse buttons: left pokes / uses a tool, right is the alternate tool action.
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("poke", lmb)
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("tool_alt", rmb)


func _add_axis(action: String, axis: JoyAxis, dir: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = dir
	InputMap.action_add_event(action, ev)
