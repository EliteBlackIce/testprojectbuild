class_name Terrain
extends RefCounted
## The land around Eggville: flat under the town, then rolling hills that climb
## into forested ridges, a lake, and (far away) the mountains. One height function
## drives the mesh, the trees, the rocks and the lake, so everything sits on the ground.

const CELL := 10.0
const EXTENT := 520.0           ## half size of the terrain square from the town's center

static var _noise: FastNoiseLite
static var _ridge: FastNoiseLite
static var center := Vector3.ZERO
static var half := Vector2(150, 120)
static var lake_center := Vector2.ZERO
const LAKE_R := 62.0
const LAKE_Y := -2.2


static func setup(c: Vector3, h: Vector2, seed_value: int) -> void:
	center = c
	half = h
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0046
	_noise.fractal_octaves = 3
	_ridge = FastNoiseLite.new()
	_ridge.seed = seed_value + 99
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.frequency = 0.012
	lake_center = Vector2(c.x - h.x - 150.0, c.z + 70.0)


## Distance outside the town's rectangle (0 anywhere inside it).
static func outside(x: float, z: float) -> float:
	var dx := maxf(absf(x - center.x) - half.x, 0.0)
	var dz := maxf(absf(z - center.z) - half.y, 0.0)
	return sqrt(dx * dx + dz * dz)


static func height(x: float, z: float) -> float:
	var d := outside(x, z)
	if d <= 0.0:
		return 0.0
	var rise := smoothstep(16.0, 150.0, d)
	var fade := 1.0 - smoothstep(260.0, 400.0, d)
	var n := _noise.get_noise_2d(x, z)                     # -1..1
	var r := absf(_ridge.get_noise_2d(x, z))
	var h := rise * (14.0 + n * 30.0 + (1.0 - r) * 14.0) + smoothstep(120.0, 300.0, d) * 22.0
	h *= fade
	# The lake: carve a bowl with a gentle shore.
	var ld := Vector2(x, z).distance_to(lake_center)
	var bowl := 1.0 - smoothstep(LAKE_R * 0.55, LAKE_R * 1.35, ld)
	h = lerpf(h, LAKE_Y - 3.0, bowl)
	return h


static func color_at(h: float, x: float, z: float) -> Color:
	var v := _ridge.get_noise_2d(x * 3.0, z * 3.0) * 0.5      # small patchiness
	if h < LAKE_Y + 0.6:
		return Color("#e6d5a0")                                   # sandy lake floor
	if h < 0.9:
		return Color("#8fcf6a").lerp(Color("#e6d5a0"), 0.35)      # shore
	if h < 22.0:
		return Color("#7bbf68").lerp(Color("#5fa84f"), clampf(h / 22.0 + v, 0.0, 1.0))
	if h < 42.0:
		return Color("#4f9a52").lerp(Color("#3f8447"), clampf((h - 22.0) / 20.0 + v, 0.0, 1.0))
	if h < 56.0:
		return Color("#8b9aa8").lerp(Color("#a7b3be"), clampf((h - 42.0) / 14.0, 0.0, 1.0))
	return Color("#f4f7fb")


static func build(parent: Node3D) -> void:
	var n := int(EXTENT * 2.0 / CELL)
	var origin := Vector2(center.x - EXTENT, center.z - EXTENT)
	var heights: Array = []
	for i in n + 1:
		var row := PackedFloat32Array()
		row.resize(n + 1)
		for j in n + 1:
			row[j] = height(origin.x + i * CELL, origin.y + j * CELL)
		heights.append(row)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for i in n:
		for j in n:
			var x0 := origin.x + i * CELL
			var z0 := origin.y + j * CELL
			var a := Vector3(x0, heights[i][j], z0)
			var b := Vector3(x0 + CELL, heights[i + 1][j], z0)
			var c := Vector3(x0 + CELL, heights[i + 1][j + 1], z0 + CELL)
			var d := Vector3(x0, heights[i][j + 1], z0 + CELL)
			# Flat region: skip (the ground slab covers it) to save triangles.
			if a.y == 0.0 and b.y == 0.0 and c.y == 0.0 and d.y == 0.0:
				continue
			# Alternate the split so the facets don't all lean one way.
			var tris := [[a, d, c], [a, c, b]] if (i + j) % 2 == 0 else [[a, d, b], [b, d, c]]
			for t in tris:
				var p0: Vector3 = t[0]
				var p1: Vector3 = t[1]
				var p2: Vector3 = t[2]
				var fn := (p1 - p0).cross(p2 - p0)
				if fn.y > 0.0:      # front faces are clockwise from above
					var tmp := p1
					p1 = p2
					p2 = tmp
					fn = -fn
				var nrm := (-fn).normalized()
				var mid := (p0 + p1 + p2) / 3.0
				var col := color_at(mid.y, mid.x, mid.z).srgb_to_linear()
				for p in [p0, p1, p2]:
					verts.append(p)
					norms.append(nrm)
					cols.append(col)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := (Toon.mat(Color.WHITE, 0.0) as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("albedo", Color.WHITE)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "Terrain"
	parent.add_child(mi)
	# Lake water
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = LAKE_R * 1.5
	disc.bottom_radius = LAKE_R * 1.5
	disc.height = 0.1
	disc.radial_segments = 40
	water.mesh = disc
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("#3fb6e8")
	wm.roughness = 0.8
	wm.metallic = 0.0
	wm.emission_enabled = true
	wm.emission = Color("#2a8cc4")
	wm.emission_energy_multiplier = 0.12
	water.material_override = wm
	water.position = Vector3(lake_center.x, LAKE_Y, lake_center.y)
	parent.add_child(water)
