class_name Toon
extends RefCounted
## Helpers for building chunky cel-shaded meshes out of primitives.
## Everything in the game is made from these, so there are no model files.

const TOON_SHADER := preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")
const PUPIL_SHADER := preload("res://shaders/googly_pupil.gdshader")

static var _cache: Dictionary = {}


## A cel-shaded material with an inked outline.
static func mat(color: Color, outline := 0.035, boxy := false, glow := 0.0) -> ShaderMaterial:
	var key := "%s|%s|%s|%s" % [color.to_html(), outline, boxy, glow]
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
		o.set_shader_parameter("expand_from_center", boxy)
		m.next_pass = o
	_cache[key] = m
	return m


static func pupil_mat() -> ShaderMaterial:
	if not _cache.has("pupil"):
		var m := ShaderMaterial.new()
		m.shader = PUPIL_SHADER
		_cache.pupil = m
	return _cache.pupil


static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, outline := 0.04) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, pos, mat(color, outline, true))


static func sphere(parent: Node3D, radius: float, pos: Vector3, color: Color, outline := 0.03, squash := 1.0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0 * squash
	mesh.radial_segments = 24
	mesh.rings = 12
	return _add(parent, mesh, pos, mat(color, outline))


static func capsule(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, outline := 0.03) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 6
	return _add(parent, mesh, pos, mat(color, outline))


static func cylinder(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, color: Color, outline := 0.03) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 20
	return _add(parent, mesh, pos, mat(color, outline, top == 0.0 or bottom == 0.0))


static func prism(parent: Node3D, size: Vector3, pos: Vector3, color: Color, outline := 0.05) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	return _add(parent, mesh, pos, mat(color, outline, true))


static func label(parent: Node3D, text: String, pos: Vector3, size := 96, color := Color.WHITE, billboard := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.outline_size = int(size / 4.0)
	l.modulate = color
	l.outline_modulate = Color("#2b1d33")
	l.pixel_size = 0.01
	l.font = goofy_font()
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.double_sided = true
	parent.add_child(l)
	return l


## A chunky rounded font. Macs ship Chalkboard SE / Marker Felt; Windows has
## Comic Sans. Falls back to Godot's default font elsewhere.
static func goofy_font() -> Font:
	if not _cache.has("font"):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Chalkboard SE", "Comic Sans MS", "Marker Felt", "Comic Neue", "Arial Rounded MT Bold"])
		f.font_weight = 700
		_cache.font = f
	return _cache.font


static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = material
	parent.add_child(mi)
	return mi


## Static collision box (position is the box center).
static func solid_box(parent: Node3D, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	body.add_child(shape)
	parent.add_child(body)
	return body
