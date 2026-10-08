class_name Chaos
extends RefCounted
## Little helpers for the slapstick layer: bonking eggs, floating "BONK!" text.

const WORDS := ["BONK!", "OOF!", "WHAM!", "BOINK!", "YEOWCH", "DONK!", "SPLORT", "BAP!"]


static func popup(at: Vector3, text: String, color := Color("#ffd166"), size := 140) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font = Toon.goofy_font()
	l.font_size = size
	l.pixel_size = 0.0035
	l.modulate = color
	l.outline_size = 22
	l.outline_modulate = Color("#2b1c18")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 5
	tree.current_scene.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", at.y + 1.1, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)


## Smack an egg: it tumbles, yells, and flies off in `dir` (world space).
static func bonk(egg: EggBody, dir: Vector3, strength := 1.0, word := "") -> void:
	if egg == null or not is_instance_valid(egg):
		return
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	Sfx.play("bonk", randf_range(0.8, 1.35), -2.0)
	popup(egg.global_position + Vector3(0, 2.0, 0), word if word != "" else WORDS.pick_random())
	if egg.has_meta("on_bonk"):
		(egg.get_meta("on_bonk") as Callable).call(dir, strength)
	else:
		egg.tumble(dir, strength)
		egg.express("scared", 2.0)
	Game.bonks += 1
	if Game.bonks in [5, 15, 30, 60]:
		Game.say_toast({5: "5 bonks. You're a natural.", 15: "15 BONKS. Tony is concerned.", 30: "30 bonks!! Legend of the kitchen.", 60: "60 BONKS. HR has been notified."}[Game.bonks], UiTheme.PINK)
