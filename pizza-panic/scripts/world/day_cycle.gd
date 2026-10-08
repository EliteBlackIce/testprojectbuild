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
	apply(0.0)


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
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sun.light_color = Color(a[3]).lerp(Color(b[3]), t)
	sun.light_energy = lerpf(a[4], b[4], t)
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


func _process(_delta: float) -> void:
	if Game.day_running:
		apply(Game.day_fraction())
