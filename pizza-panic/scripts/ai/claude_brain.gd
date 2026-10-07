class_name ClaudeBrain
extends Node
## Makes NPCs think with Claude (Anthropic Messages API over plain HTTP,
## since Godot has no Anthropic SDK).
##
## Every reply comes back as structured JSON (say / emotion / mood_change /
## action / tip), so the NPC's words and the game logic stay in sync.

const SCHEMA := {
	"type": "object",
	"properties": {
		"say": {"type": "string", "description": "What you say out loud. One or two short sentences."},
		"emotion": {"type": "string", "enum": ["happy", "angry", "confused", "excited", "sad", "scared", "suspicious", "in_love", "smug"]},
		"mood_change": {"type": "integer", "description": "-3 to 3"},
		"action": {"type": "string", "enum": ["none", "place_order", "hang_up", "accept_pizza", "refuse_pizza", "slam_door", "steal_pizza"]},
		"tip": {"type": "integer", "description": "0 to 15 dollars, only used with accept_pizza"},
		"order": {
			"type": "object",
			"description": "Your pizza order. Used with place_order; otherwise your usual favorite.",
			"properties": {
				"size": {"type": "string", "enum": ["small", "medium", "large"]},
				"sauce": {"type": "string", "enum": ["tomato", "bbq", "white"]},
				"toppings": {"type": "array", "items": {"type": "string", "enum": ["pepperoni", "mushroom", "olive", "pepper", "onion", "sausage", "ham", "pineapple", "anchovy", "jalapeno", "gummy", "hotdog"]}},
			},
			"required": ["size", "sauce", "toppings"],
			"additionalProperties": false,
		},
	},
	"required": ["say", "emotion", "mood_change", "action", "tip", "order"],
	"additionalProperties": false,
}

## Keeps conversations from growing forever. Old turns are dropped in pairs
## from the front (each NPC only needs to vaguely remember you).
const MAX_HISTORY_MESSAGES := 24

var last_error := ""


## Ask the character what they say next.
## `history` is that NPC's message list; it is updated in place on success.
## Returns {ok, say, emotion, mood_change, action, tip}.
func think(character: Dictionary, history: Array, player_text: String, scene: String) -> Dictionary:
	var user_msg := {
		"role": "user",
		"content": "[SCENE] %s\n[PLAYER SAYS] %s" % [scene, player_text],
	}
	var messages := history.duplicate()
	messages.append(user_msg)
	var body := {
		"model": Settings.claude_model,
		"max_tokens": 4000,
		"system": [{
			"type": "text",
			"text": Characters.SHARED_RULES + "\n\n## Your character\n" + character.prompt
				+ "\n\nLatency-sensitive; begin your visible answer immediately.",
		}],
		"output_config": {
			"effort": Settings.claude_effort,
			"format": {"type": "json_schema", "schema": SCHEMA},
		},
		# If Claude's safety filter declines a line, let the API retry on its
		# recommended fallback model instead of the NPC going silent.
		"fallbacks": "default",
		"messages": messages,
	}

	var http := HTTPRequest.new()
	http.timeout = 40.0
	add_child(http)
	var err := http.request(Settings.anthropic_url("/v1/messages"), Settings.anthropic_headers(),
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return _fail("Couldn't start request (error %d)" % err)
	var res: Array = await http.request_completed
	http.queue_free()

	var result: int = res[0]
	var code: int = res[1]
	var raw: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return _fail("Network problem (result %d)" % result)
	var data = JSON.parse_string(raw.get_string_from_utf8())
	if code != 200 or typeof(data) != TYPE_DICTIONARY:
		return _fail("Claude HTTP %d: %s" % [code, raw.get_string_from_utf8().left(300)])

	if data.get("stop_reason") == "refusal":
		# Don't add the refused turn to history; just deflect in character.
		return {"ok": true, "say": "...Uh. I don't wanna talk about that. Pizza?", "emotion": "confused",
			"mood_change": 0, "action": "none", "tip": 0, "order": {}}

	var text := ""
	for block in data.get("content", []):
		if block.get("type") == "text":
			text += block.get("text", "")
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("say"):
		return _fail("Claude sent something that isn't the JSON we asked for: " + text.left(200))

	# Only the NPC's text goes into history, never thinking blocks. Thinking
	# blocks are bound to the exact conversation that produced them, and we
	# trim old turns below, which would invalidate them. Text-only history
	# can be trimmed freely (this also covers turns served by a fallback model).
	history.append(user_msg)
	history.append({"role": "assistant", "content": [{"type": "text", "text": text}]})
	while history.size() > MAX_HISTORY_MESSAGES:
		history.pop_front()
		history.pop_front()

	parsed["ok"] = true
	parsed["mood_change"] = clampi(int(parsed.get("mood_change", 0)), -3, 3)
	parsed["tip"] = clampi(int(parsed.get("tip", 0)), 0, 15)
	parsed["order"] = _clean_order(parsed.get("order", {}))
	return parsed


## Keep orders sane: known toppings only (and only unlocked ones), max 3.
static func _clean_order(o) -> Dictionary:
	if typeof(o) != TYPE_DICTIONARY:
		return {}
	var size := str(o.get("size", "medium"))
	if size not in Menu.SIZES:
		size = "medium"
	var sauce := str(o.get("sauce", "tomato"))
	if sauce not in Menu.SAUCES:
		sauce = "tomato"
	var avail := Menu.available_toppings()
	var tops: Array[String] = []
	for t in o.get("toppings", []):
		if str(t) in avail and str(t) not in tops and tops.size() < 3:
			tops.append(str(t))
	return {"size": size, "sauce": sauce, "toppings": tops}


func _fail(msg: String) -> Dictionary:
	last_error = msg
	push_warning("[ClaudeBrain] " + msg)
	return {"ok": false, "error": msg}
