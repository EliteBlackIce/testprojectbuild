class_name Batch
extends RefCounted
## Collects lots of little colored boxes / cylinders / balls and draws each kind as
## ONE MultiMesh (per-instance colors). Trim, rails, balusters, shingles, window frames:
## hundreds of details per house for a handful of draw calls.
##
## Usage: var b := Batch.new(); b.box(pos, size, color); ...; b.flush(parent)

const KINDS := ["box", "cyl", "cone", "taper", "ball"]

var _items: Dictionary = {"box": [], "cyl": [], "cone": [], "taper": [], "ball": []}
var _glass_lit: Array[Transform3D] = []
var _glass_dim: Array[Transform3D] = []
var ground := Callable()      ## optional (x, z) -> y offset: while set, every item rides the ground (yards on hills)
static var _mat: ShaderMaterial
static var _meshes: Dictionary = {}


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = Toon.TOON_SHADER
		_mat.set_shader_parameter("use_vertex_color", true)
		_mat.set_shader_parameter("rim_strength", 0.2)
	return _mat


static func mesh_for(kind: String) -> Mesh:
	if not _meshes.has(kind):
		match kind:
			"box":
				_meshes[kind] = Shapes.box(Vector3.ONE)
			"cyl":
				_meshes[kind] = Shapes.cylinder(0.5, 0.5, 1.0, 10)
			"cone":
				_meshes[kind] = Shapes.cylinder(0.0, 0.5, 1.0, 10)
			"taper":
				_meshes[kind] = Shapes.cylinder(0.32, 0.5, 1.0, 10)
			"ball":
				_meshes[kind] = Shapes.ball(0.5, 10, 6)
	return _meshes[kind]


func _add(kind: String, xf: Transform3D, color: Color) -> void:
	if ground.is_valid():
		xf.origin.y += float(ground.call(xf.origin.x, xf.origin.z))
	_items[kind].append([xf, color.srgb_to_linear()])


## Box centered on pos.
func box(pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	_add("box", Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos), color)


## Cylinder centered on pos (axis = Y before rot).
func cyl(pos: Vector3, radius: float, height: float, color: Color, rot := Vector3.ZERO) -> void:
	_add("cyl", Transform3D(Basis.from_euler(rot) * Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), pos), color)


## Cone with its point up.
func cone(pos: Vector3, radius: float, height: float, color: Color, rot := Vector3.ZERO) -> void:
	_add("cone", Transform3D(Basis.from_euler(rot) * Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), pos), color)


## Column that narrows toward the top (bottom radius given).
func taper(pos: Vector3, radius: float, height: float, color: Color) -> void:
	_add("taper", Transform3D(Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), pos), color)


func ball(pos: Vector3, radius: float, color: Color, squash := Vector3.ONE) -> void:
	_add("ball", Transform3D(Basis.from_scale(Vector3.ONE * radius * 2.0 * squash), pos), color)


## A window pane: lit ones switch to a warm glow at night.
func glass(pos: Vector3, size: Vector3, lit: bool, rot := Vector3.ZERO) -> void:
	var xf := Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos)
	if ground.is_valid():
		xf.origin.y += float(ground.call(xf.origin.x, xf.origin.z))
	if lit:
		_glass_lit.append(xf)
	else:
		_glass_dim.append(xf)


func count() -> int:
	var n := _glass_lit.size() + _glass_dim.size()
	for k in KINDS:
		n += _items[k].size()
	return n


## Builds the MultiMeshInstance3D nodes under `parent` (call once, at the end).
func flush(parent: Node3D, visible_end := 0.0) -> void:
	for kind in KINDS:
		var list: Array = _items[kind]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh_for(kind)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = material()
		if visible_end > 0.0:
			mmi.visibility_range_end = visible_end
		parent.add_child(mmi)
	for lit in [true, false]:
		var xs: Array[Transform3D] = _glass_lit if lit else _glass_dim
		if xs.is_empty():
			continue
		var gm := Toon.multimesh(parent, mesh_for("box"), Toon.mat(Color("#8fb8c9"), 0.0), xs)
		if lit:
			gm.add_to_group("night_window")
		if visible_end > 0.0:
			gm.visibility_range_end = visible_end
	_items = {"box": [], "cyl": [], "cone": [], "taper": [], "ball": []}
	_glass_lit.clear()
	_glass_dim.clear()
