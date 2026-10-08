class_name DayCycle
extends Node3D
## Sun, sky, fog and lights from morning (10 AM) to night (10 PM).
## Golden hour, a pink sunset, then streetlights and windows switch on.

## [day fraction, sky top, horizon, sun color, sun energy, sun pitch, ambient color, ambient energy]
const KEYS := [
	[0.00, "#2f8ff0", "#bfe6ff", "#fff6e0", 0.72, -58.0, "#c4cdf0", 0.21],
	[0.45, "#2c86ea", "#c6e8fc", "#fff1d4", 0.7, -42.0, "#c8c8ec", 0.21],
	[0.66, "#5f86d0", "#ffcf9a", "#ffc488", 0.62, -16.0, "#dcbcbc", 0.21],
	[0.74, "#5258a3", "#ff9a80", "#ff9068", 0.42, -4.0, "#b897b8", 0.2],
	[0.82, "#232758", "#62558a", "#9fa8e8", 0.17, -30.0, "#6464a0", 0.2],
	[1.00, "#111533", "#2a2d5a", "#a3b1f0", 0.15, -55.0, "#474d8a", 0.19],
]

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var town: Town
var night := 0.0

var _window_day: Material
var _window_night: Material
var _lamp_day: Material
var _lamp_night: Material
var _was_night := false

## Weather: how much it dims the sun, thickens fog, greys the sky.
const WEATHER := {
	"clear": {"sun": 1.0, "fog": 1.0, "gray": 0.0, "amb": 1.0, "toast": ""},
	"overcast": {"sun": 0.5, "fog": 1.8, "gray": 0.8, "amb": 1.15, "toast": "Overcast today. The sky is a big grey blanket."},
	"rain": {"sun": 0.28, "fog": 3.0, "gray": 0.92, "amb": 1.1, "toast": "Rainy day! Roads are slippery, so brake early."},
	"fog": {"sun": 0.6, "fog": 7.0, "gray": 0.7, "amb": 1.2, "toast": "Thick fog this morning. Follow the GPS!"},
}
var weather := "clear"
var _w_mix := {"sun": 1.0, "fog": 1.0, "gray": 0.0, "amb": 1.0}
var _rain: CPUParticles3D
var _rain_holder: Node3D
var _rain_audio: AudioStreamPlayer
var _rain_pb: AudioStreamGeneratorPlayback
var _flash := 0.0
var _next_thunder := 12.0


func _ready() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 25.0
	sky_mat.ground_bottom_color = Color("#6fae5b")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_density = 0.0019
	env.fog_sky_affect = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.2
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2      # bright anime colors
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.3             # first person is close to the floor: avoid shadow acne stripes
	sun.shadow_normal_bias = 3.0
	add_child(sun)
	_window_day = Toon.mat(Color("#8fb8c9"), 0.0)
	_window_night = Toon.glow(Color("#ffd98a"), 1.1)
	_lamp_day = Toon.mat(Color("#d9d2c0"), 0.0)
	_lamp_night = Toon.glow(Color("#ffe8a3"), 2.5)
	_build_rain()
	Game.day_started.connect(_on_new_day)
	apply(0.0)


func _on_new_day(day: int) -> void:
	var roll := randf()
	var w := "clear"
	if day > 1:
		w = "clear" if roll < 0.5 else ("overcast" if roll < 0.68 else ("rain" if roll < 0.9 else "fog"))
	set_weather(w, true)


func set_weather(w: String, announce := false) -> void:
	weather = w
	Game.weather = w
	if announce and String(WEATHER[w].toast) != "":
		Game.say_toast(WEATHER[w].toast, Color("#9ec9ff"))


func _build_rain() -> void:
	_rain_holder = Node3D.new()
	add_child(_rain_holder)
	_rain = CPUParticles3D.new()
	_rain.amount = 2600
	_rain.lifetime = 1.0
	_rain.preprocess = 1.0
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(26, 0.5, 26)
	_rain.direction = Vector3(0.12, -1, 0.05)
	_rain.spread = 3.0
	_rain.initial_velocity_min = 26.0
	_rain.initial_velocity_max = 32.0
	_rain.gravity = Vector3(0, -6, 0)
	var qm := BoxMesh.new()
	qm.size = Vector3(0.02, 0.8, 0.02)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.8, 0.9, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.material = mat
	_rain.mesh = qm
	_rain.emitting = false
	_rain_holder.add_child(_rain)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.2
	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.stream = gen
	_rain_audio.volume_db = -26.0
	add_child(_rain_audio)
	_rain_audio.play()
	_rain_pb = _rain_audio.get_stream_playback() as AudioStreamGeneratorPlayback


func _update_weather(delta: float) -> void:
	var tgt: Dictionary = WEATHER[weather]
	for k in ["sun", "fog", "gray", "amb"]:
		_w_mix[k] = lerpf(_w_mix[k], tgt[k], 1.0 - exp(-0.8 * delta))
	var cam := get_viewport().get_camera_3d()
	var raining := weather == "rain"
	var inside := false
	if cam:
		_rain_holder.global_position = cam.global_position + Vector3(0, 14, 0)
		if town and town.pizzeria:
			inside = town.pizzeria.is_inside(cam.global_position)
	_rain.emitting = raining and not inside
	if _rain_pb:
		var vol := 1.0 if (raining and not inside) else (0.35 if raining else 0.0)
		for i in _rain_pb.get_frames_available():
			var n := (randf() * 2.0 - 1.0) * 0.5 * vol
			_rain_pb.push_frame(Vector2(n, n))
	# thunder and lightning
	if raining:
		_next_thunder -= delta
		if _next_thunder <= 0.0:
			_next_thunder = randf_range(9.0, 24.0)
			_flash = 1.0
			get_tree().create_timer(randf_range(0.4, 1.4)).timeout.connect(func() -> void: Sfx.play("slam", randf_range(0.35, 0.5), -6.0))
	_flash = maxf(0.0, _flash - delta * 3.5)
	if Game.day_running:
		env.ambient_light_energy = env.ambient_light_energy * float(_w_mix.amb) + _flash * 1.4
	env.fog_density = 0.0019 * float(_w_mix.fog)


func apply(f: float) -> void:
	var a: Array = KEYS[0]
	var b: Array = KEYS[KEYS.size() - 1]
	for k in KEYS.size() - 1:
		if f >= KEYS[k][0] and f <= KEYS[k + 1][0]:
			a = KEYS[k]
			b = KEYS[k + 1]
			break
	var t := 0.0 if b[0] == a[0] else clampf((f - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
	var top := Color(a[1]).lerp(Color(b[1]), t)
	var hor := Color(a[2]).lerp(Color(b[2]), t)
	var gray_amt := float(_w_mix.gray)
	var gc := Color(0.5, 0.54, 0.6).lerp(Color(0.12, 0.13, 0.2), clampf(f * 1.2, 0.0, 1.0) if f > 0.7 else 0.0)
	top = top.lerp(gc.darkened(0.15), gray_amt)
	hor = hor.lerp(gc, gray_amt)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sun.light_color = Color(a[3]).lerp(Color(b[3]), t)
	sun.light_energy = lerpf(a[4], b[4], t) * float(_w_mix.sun)
	sun.rotation_degrees = Vector3(lerpf(a[5], b[5], t), lerpf(-30.0, -150.0, f), 0)
	env.ambient_light_color = Color(a[6]).lerp(Color(b[6]), t)
	env.ambient_light_energy = lerpf(a[7], b[7], t)
	env.fog_light_color = hor
	night = clampf((f - 0.7) / 0.12, 0.0, 1.0)
	_set_lights(night)


func _set_lights(n: float) -> void:
	if town:
		for l in town.lamps:
			l.light_energy = n * 1.6
		if town.pizzeria:
			town.pizzeria.set_night(n)
	var is_night := n > 0.4
	if is_night == _was_night:
		return
	_was_night = is_night
	for w in get_tree().get_nodes_in_group("night_window"):
		(w as GeometryInstance3D).material_override = _window_night if is_night else _window_day
	for g in get_tree().get_nodes_in_group("lamp_glow"):
		(g as GeometryInstance3D).material_override = _lamp_night if is_night else _lamp_day


func _process(delta: float) -> void:
	if Game.day_running:
		apply(Game.day_fraction())
	_update_weather(delta)
