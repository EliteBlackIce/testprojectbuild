class_name MinigameUi
extends CanvasLayer
## Quick kitchen minigames, all played with E or SPACE.
##   stretch - hold to stretch the dough, let go on the size the ticket wants
##   fill    - hold to squeeze sauce, let go inside the green zone
##   mash    - mash to grate cheese into the green zone before time runs out
##   chop    - press when the knife is in the zone, 4 times (cutting)
## await play(kind, params) -> {"quality": 0..1, ...}

signal finished(result: Dictionary)

var active := false
var _kind := ""
var _params: Dictionary = {}
var _value := 0.0
var _holding := false
var _started := false
var _timer := 0.0
var _hits: Array[float] = []
var _dir := 1.0

var _panel: PanelContainer
var _title: Label
var _hint: Label
var _bar: Control
var _result: Label


func _ready() -> void:
	layer = 7
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -420
	_panel.offset_right = 420
	_panel.offset_top = -270
	_panel.offset_bottom = -60
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_title = UiTheme.label("", 34, UiTheme.RED)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(780, 56)
	_bar.draw.connect(_draw_bar)
	v.add_child(_bar)
	_hint = UiTheme.label("", 22)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hint)
	_result = UiTheme.label("", 26, UiTheme.TEAL)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_result)
	visible = false


func play(kind: String, params := {}) -> Dictionary:
	_kind = kind
	_params = params
	_value = 0.0
	_holding = false
	_started = false
	_timer = 0.0
	_hits.clear()
	_dir = 1.0
	_result.text = ""
	active = true
	visible = true
	match kind:
		"stretch":
			_title.text = "STRETCH THE DOUGH: %s" % str(params.get("size", "medium")).to_upper()
			_hint.text = "Hold E to stretch. Let go on the %s marker!" % params.get("size", "medium")
		"fill":
			_title.text = "SQUEEZE THE %s SAUCE" % str(params.get("label", "")).to_upper()
			_hint.text = "Hold E to squeeze. Let go in the green zone. Don't flood it!"
		"mash":
			_title.text = "GRATE THE CHEESE!"
			_hint.text = "MASH E! Stop in the green zone (it drains if you're slow)."
			_timer = 4.0
		"chop":
			_title.text = "CUT IT INTO SLICES"
			_hint.text = "Press E when the knife is in the green zone. (4 cuts)"
	var result: Dictionary = await finished
	return result


func _zone() -> Vector2:
	var bonus := float(_params.get("bonus", 0.0))
	match _kind:
		"stretch":
			var target: float = {"small": 0.4, "medium": 0.65, "large": 0.9}[_params.get("size", "medium")]
			var w := 0.05 + bonus * 0.025
			return Vector2(target - w, target + w)
		"fill":
			return Vector2(0.68 - bonus * 0.05, 0.88 + bonus * 0.03)
		"mash":
			return Vector2(0.62 - bonus * 0.05, 0.88)
		"chop":
			return Vector2(0.42 - bonus * 0.03, 0.58 + bonus * 0.03)
	return Vector2(0.4, 0.6)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var press := event.is_action_pressed("interact") or event.is_action_pressed("hop")
	var release := event.is_action_released("interact") or event.is_action_released("hop")
	if press and event.is_echo():
		return
	if press or release:
		get_viewport().set_input_as_handled()
	match _kind:
		"stretch", "fill":
			if press:
				_holding = true
				_started = true
			elif release and _started:
				_holding = false
				_finish()
		"mash":
			if press:
				_value = minf(1.15, _value + 0.075 * (1.0 + float(_params.get("bonus", 0.0)) * 0.25))
				Sfx.play("click", randf_range(0.8, 1.3), -8.0)
		"chop":
			if press:
				var z := _zone()
				var center := (z.x + z.y) * 0.5
				var acc := clampf(1.0 - absf(_value - center) / 0.5 * 1.6, 0.0, 1.0)
				_hits.append(acc)
				Sfx.play("bonk", 1.8 + acc * 0.4, -6.0)
				if _hits.size() >= 4:
					_finish()


## Lets tests (and the auto-play option) finish a minigame with a given score.
func auto_finish(quality: float) -> void:
	if not active:
		return
	var z := _zone()
	_value = lerpf(0.0, (z.x + z.y) * 0.5, clampf(quality, 0.0, 1.0))
	_hits = [quality, quality, quality, quality]
	_finish()


func _process(delta: float) -> void:
	if not active:
		return
	match _kind:
		"stretch":
			if _holding:
				_value = minf(1.2, _value + delta * 0.55)
		"fill":
			if _holding:
				_value = minf(1.25, _value + delta * (0.42 - float(_params.get("bonus", 0.0)) * 0.06))
		"mash":
			_timer -= delta
			_value = maxf(0.0, _value - delta * 0.12)
			if _timer <= 0.0:
				_finish()
		"chop":
			_value += _dir * delta * 1.4
			if _value > 1.0:
				_value = 1.0
				_dir = -1.0
			elif _value < 0.0:
				_value = 0.0
				_dir = 1.0
	_bar.queue_redraw()


func _finish() -> void:
	if not active:
		return
	active = false
	var z := _zone()
	var q := 0.0
	var res := {}
	match _kind:
		"stretch":
			# Which size did they actually make?
			var made := "small"
			if _value >= 0.53:
				made = "medium"
			if _value >= 0.78:
				made = "large"
			res["size"] = made
			var center := (z.x + z.y) * 0.5
			q = clampf(1.0 - maxf(0.0, absf(_value - center) - (z.y - z.x) * 0.5) * 6.0, 0.0, 1.0)
			if made != _params.get("size", "medium"):
				q *= 0.5
		"fill", "mash":
			if _value >= z.x and _value <= z.y:
				q = 1.0
			elif _value < z.x:
				q = clampf(_value / z.x, 0.0, 1.0) * 0.8
			else:
				q = clampf(1.0 - (_value - z.y) * 3.0, 0.0, 1.0) * 0.8
		"chop":
			var total := 0.0
			for h in _hits:
				total += h
			q = total / maxf(1.0, _hits.size())
	res["quality"] = q
	_result.text = _verdict(q)
	Sfx.play("pickup" if q > 0.7 else "blip", 1.0 + q * 0.3)
	await get_tree().create_timer(0.6).timeout
	visible = false
	finished.emit(res)


static func _verdict(q: float) -> String:
	if q >= 0.95:
		return "PERFECT!!"
	if q >= 0.75:
		return "Nice!"
	if q >= 0.5:
		return "Eh, it's fine."
	return "Yikes."


func _draw_bar() -> void:
	var w := _bar.size.x
	var h := _bar.size.y
	_bar.draw_rect(Rect2(0, 8, w, h - 16), Color("#fff8e7"))
	var z := _zone()
	var scale_div := 1.2 if _kind in ["stretch", "fill"] else (1.15 if _kind == "mash" else 1.0)
	_bar.draw_rect(Rect2(z.x / scale_div * w, 8, (z.y - z.x) / scale_div * w, h - 16), Color("#06d6a0"))
	if _kind == "stretch":
		for s in [["S", 0.4], ["M", 0.65], ["L", 0.9]]:
			var x: float = s[1] / 1.2 * w
			_bar.draw_line(Vector2(x, 0), Vector2(x, h), UiTheme.INK, 3)
			_bar.draw_string(Toon.goofy_font(), Vector2(x - 8, h + 22), s[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiTheme.INK)
	var fill_col := Color("#e63946") if _kind == "fill" else Color("#f2c14e")
	if _kind == "chop":
		var kx := _value * w
		_bar.draw_rect(Rect2(kx - 6, 0, 12, h), Color("#adb5bd"))
		_bar.draw_rect(Rect2(kx - 6, 0, 12, h), UiTheme.INK, false, 3)
		for i in _hits.size():
			_bar.draw_circle(Vector2(20 + i * 30, -10), 10, Color("#06d6a0") if _hits[i] > 0.6 else Color("#e63946"))
	else:
		_bar.draw_rect(Rect2(0, 14, minf(_value / scale_div, 1.0) * w, h - 28), fill_col)
	_bar.draw_rect(Rect2(0, 8, w, h - 16), UiTheme.INK, false, 4)
	if _kind == "mash":
		_bar.draw_string(Toon.goofy_font(), Vector2(w - 60, -8), "%.1fs" % maxf(_timer, 0.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiTheme.INK)
