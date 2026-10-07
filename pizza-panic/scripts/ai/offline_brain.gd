class_name OfflineBrain
extends RefCounted
## Keyword-matching dialogue for when there's no AI available. Way dumber
## than Claude, but the game is fully playable without internet or keys.
## Returns the same shape as ClaudeBrain.think().

const GENERIC := [
	["\\b(hi|hello|hey|yo|sup|howdy)\\b", ["Hello?", "...Hi.", "Why are you yelling hello at me?"], 0, "none"],
	["sorry|apolog", ["Apology accepted. Maybe.", "Okay fine. I forgive you."], 1, "none"],
	["pineapple", ["Pineapple on pizza is a war crime.", "Finally, someone who gets it."], 0, "none"],
	["stupid|idiot|dumb|shut up|ugly|loser|hate you", ["Wow. Rude.", "I'm telling Tony about this."], -2, "none"],
	["love you|beautiful|handsome|awesome|nice|cool|great|amazing", ["Aw, shucks.", "You're alright, pizza person."], 1, "none"],
	["joke", ["Why did the pizza get a job? It was tired of being cheesy. ...Give me my pizza."], 1, "none"],
	["\\bname\\b", ["My name is {name}. Obviously."], 0, "none"],
]
const DELIVER_WORDS := "pizza|here you go|here's your|delivery|deliver|your order|enjoy|food|order"

var _compiled: Dictionary = {}


func think(character: Dictionary, player_text: String, ctx: Dictionary) -> Dictionary:
	var text := player_text.to_lower()
	var mood: int = ctx.get("mood", 0)
	var for_me: bool = ctx.get("pizza_for_me", false)
	var carrying: bool = ctx.get("carrying", false)
	var is_boss: bool = ctx.get("is_boss", false)

	var hit: Array = []
	for rule in character.get("rules", []) + GENERIC:
		if _rx(rule[0]).search(text):
			hit = rule
			break

	var reply := {
		"ok": true,
		"say": "",
		"emotion": "confused",
		"mood_change": 0,
		"action": "none",
		"tip": 0,
	}
	if hit.is_empty():
		reply.say = character.get("idle", ["..."]).pick_random()
	else:
		reply.say = (hit[1] as Array).pick_random().replace("{name}", character.get("name", "me"))
		reply.mood_change = hit[2]
		reply.action = hit[3]
	reply.emotion = "happy" if reply.mood_change > 0 else ("angry" if reply.mood_change < 0 else "confused")

	if is_boss:
		reply.action = "none"
		return reply

	var wants_to_deliver := _rx(DELIVER_WORDS).search(text) != null
	if reply.action == "accept_pizza" or wants_to_deliver:
		if not carrying:
			reply.say = "You don't have a pizza. Are you just... a guy? Standing here?"
			reply.action = "refuse_pizza"
			reply.emotion = "confused"
		elif not for_me:
			if randf() < 0.5:
				reply.say = "I didn't order that. ...I'm keeping it though. Bye!"
				reply.action = "steal_pizza"
				reply.emotion = "smug"
			else:
				reply.say = "Wrong house, genius."
				reply.action = "refuse_pizza"
		elif reply.action != "accept_pizza":
			# Delivering without playing along: only works once they like you,
			# or after you've tried a few times (offline mode is forgiving).
			if mood + reply.mood_change >= 2 or ctx.get("turns", 0) >= 3:
				reply.action = "accept_pizza"
				reply.say += " ...Fine. Gimme."
	if reply.action == "accept_pizza":
		reply.emotion = "excited"
		reply.tip = clampi(3 + (mood + reply.mood_change) * 2, 0, 15)
	if mood + reply.mood_change <= -6:
		reply.say = "That's it. *SLAMS DOOR*"
		reply.action = "slam_door"
		reply.emotion = "angry"
	return reply


func _rx(pattern: String) -> RegEx:
	if not _compiled.has(pattern):
		_compiled[pattern] = RegEx.create_from_string(pattern)
	return _compiled[pattern]
