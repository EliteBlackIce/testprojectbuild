class_name Toon
extends RefCounted
## Materials + quick builders for faceted cel-shaded parts.
## Every builder returns the MeshInstance3D so you can tweak rotation/scale.

const TOON_SHADER := preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")

const INK := Color("#2b1c18")

static var _cache: Dictionary = {}


## Cel-shaded material with an ink outline (outline 0 = none).
static func mat(color: Color, outline := 0.02, glow := 0.0) -> ShaderMaterial:
	var key := "%s|%s|%s" % [color.to_html(), outline, glow]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("emission_strength", glow)
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE_SHADER
		o.set_shader_parameter("outline_width", outline)
		o.set_shader_parameter("outline_color", INK)
		m.next_pass = o
	_cache[key] = m
	return m


## Glowy unshaded material (lamp bulbs, neon, screens).
static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "glow|%s|%s" % [color.to_html(), energy]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		_cache[key] = m
	return _cache[key]


static func mesh(parent: Node3D, m: Mesh, pos: Vector3, color: Color, outline := 0.02) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat(color, outline)
	parent.add_child(mi)
	return mi


## Box centered on `pos`.
static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, outline := 0.02) -> MeshInstance3D:
	return mesh(parent, Shapes.box(size), pos, color, outline)


## Chamfered block whose BOTTOM sits at `pos`.
static func block(parent: Node3D, size: Vector3, pos: Vector3, color: Color, bevel := 0.12, outline := 0.02) -> MeshInstance3D:
	return mesh(parent, Shapes.chamfer_box(size, bevel), pos, color, outline)


static func ball(parent: Node3D, radius: float, pos: Vector3, color: Color, outline := 0.015, segments := 10) -> MeshInstance3D:
	return mesh(parent, Shapes.ball(radius, segments, maxi(4, segments / 2)), pos, color, outline)


static func cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, color: Color, outline := 0.015, segments := 8) -> MeshInstance3D:
	return mesh(parent, Shapes.cylinder(top, bottom, height, segments), pos, color, outline)


static func label(parent: Node3D, text: String, pos: Vector3, size := 96, color := Color.WHITE, billboard := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.outline_size = int(size / 4.0)
	l.modulate = color
	l.outline_modulate = INK
	l.pixel_size = 0.01
	l.font = goofy_font()
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.double_sided = billboard
	parent.add_child(l)
	return l


## The game's display font (signs, logo, name tags): Erica One, a chunky cartoon face
## shipped in res://fonts. Falls back to a system font if it hasn't been imported yet.
static func goofy_font() -> Font:
	if not _cache.has("font"):
		var f: Font = null
		if ResourceLoader.exists("res://fonts/EricaOne-Regular.ttf"):
			f = load("res://fonts/EricaOne-Regular.ttf") as Font
		if f == null:
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray(["Chalkboard SE", "Comic Sans MS", "Marker Felt", "Arial Rounded MT Bold"])
			sf.font_weight = 700
			f = sf
		_cache.font = f
	return _cache.font


## Static collision box centered on `pos`.
static func solid_box(parent: Node3D, size: Vector3, pos: Vector3, layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	body.add_child(shape)
	parent.add_child(body)
	return body


## Batch many copies of one mesh into a single draw call.
static func multimesh(parent: Node3D, m: Mesh, material: Material, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	parent.add_child(mmi)
	return mmi
