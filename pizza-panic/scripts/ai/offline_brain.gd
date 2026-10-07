class_name OfflineBrain
extends RefCounted
## Keyword dialogue for when there's no AI. Much dumber than Claude, but the
## whole game is playable offline. Returns the same shape as ClaudeBrain.think().

const GENERIC := [
	["\\b(hi|hello|hey|yo|sup|howdy)\\b", ["Hello?", "...Hi.", "Why are you yelling hello at me?"], 0, "none"],
	["sorry|apolog", ["Apology accepted. Maybe.", "Okay fine. I forgive you."], 1, "none"],
	["pineapple", ["Pineapple on pizza is a war crime.", "Finally, someone who gets it."], 0, "none"],
	["stupid|idiot|dumb|shut up|ugly|loser|hate you", ["Wow. Rude.", "I'm telling Tony about this."], -2, "none"],
	["love you|beautiful|handsome|awesome|nice|cool|great|amazing", ["Aw, shucks.", "You're alright, pizza person."], 1, "none"],
	["joke", ["Why did the pizza get a job? It was tired of being cheesy."], 1, "none"],
	["\\bname\\b", ["My name is {name}. Obviously."], 0, "none"],
]
const DELIVER_WORDS := "pizza|here you go|here's your|delivery|deliver|your order|enjoy|food|order"

var _compiled: Dictionary = {}
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


## ctx keys: mode ("phone", "door", "tony"), mood, turns, has_my_pizza,
## has_other_pizza, pizza_in_car
func think(character: Dictionary, player_text: String, ctx: Dictionary) -> Dictionary:
	var text := player_text.to_lower()
	var mode: String = ctx.get("mode", "door")
	var mood: int = ctx.get("mood", 0)
	var reply := {"ok": true, "say": "", "emotion": "confused", "mood_change": 0, "action": "none", "tip": 0, "order": {}}

	if mode == "phone":
		# Offline callers just say their order straight away.
		var order := Menu.random_order(rng, character.get("favorites", []))
		reply.order = order
		reply.action = "place_order"
		reply.emotion = "happy"
		reply.say = "I'll have a %s. Thanks, bye!" % Menu.describe(order).to_lower()
		return reply

	var hit: Array = []
	for rule in character.get("rules", []) + GENERIC:
		if _rx(rule[0]).search(text):
			hit = rule
			break
	if hit.is_empty():
		reply.say = character.get("idle", ["..."]).pick_random()
	else:
		reply.say = (hit[1] as Array).pick_random().replace("{name}", character.get("name", "me"))
		reply.mood_change = hit[2]
		reply.action = hit[3]
	reply.emotion = "happy" if reply.mood_change > 0 else ("angry" if reply.mood_change < 0 else "confused")

	if mode == "tony":
		reply.action = "none"
		return reply

	var wants_to_deliver := _rx(DELIVER_WORDS).search(text) != null
	if reply.action == "accept_pizza" or wants_to_deliver:
		if ctx.get("has_my_pizza", false):
			if reply.action != "accept_pizza":
				# Not playing along: only works once they like you or you keep trying.
				if mood + reply.mood_change >= 2 or int(ctx.get("turns", 0)) >= 3:
					reply.action = "accept_pizza"
					reply.say += " ...Fine. Gimme."
				else:
					reply.action = "refuse_pizza"
		elif ctx.get("has_other_pizza", false):
			if rng.randf() < 0.5:
				reply.say = "I didn't order that. ...I'm keeping it though. Bye!"
				reply.action = "steal_pizza"
				reply.emotion = "smug"
			else:
				reply.say = "That's not mine, genius. Wrong house."
				reply.action = "refuse_pizza"
		elif ctx.get("pizza_in_car", false):
			reply.say = "Uh, my pizza is in your CAR. Go get it!"
			reply.action = "refuse_pizza"
		else:
			reply.say = "You don't have a pizza. Are you just... a guy? Standing here?"
			reply.action = "refuse_pizza"
	if reply.action == "accept_pizza":
		reply.emotion = "excited"
		reply.tip = clampi(4 + (mood + reply.mood_change) * 2, 0, 15)
	if mood + reply.mood_change <= -6:
		reply.say = "That's it. *SLAMS DOOR*"
		reply.action = "slam_door"
		reply.emotion = "angry"
	return reply


func _rx(pattern: String) -> RegEx:
	if not _compiled.has(pattern):
		_compiled[pattern] = RegEx.create_from_string(pattern)
	return _compiled[pattern]
