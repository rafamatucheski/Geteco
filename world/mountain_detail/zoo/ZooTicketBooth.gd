extends RefCounted
## Exterior service counter: shared materials, metre-scale grain, unchanged floor clearance.
const GEO = preload("res://world/mountain_detail/zoo/ZooGeometry.gd")
const SURFACE = preload("res://world/mountain_detail/zoo/booth_surface.gdshader")
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}

static func _material(kind: int, color: String) -> ShaderMaterial:
	var key := str(kind) + color
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = SURFACE
		material.set_shader_parameter("surface_kind", kind)
		material.set_shader_parameter("base_color", Color(color))
		_materials[key] = material
	return _materials[key]

static func _piece(parent: Node3D, id: String, at: Vector3, size: Vector3, kind: int, color: String, solid := true) -> void:
	var key := str(size)
	if not _meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	var visual := MeshInstance3D.new()
	visual.name = id + "Surface"
	visual.position = at
	visual.mesh = _meshes[key]
	visual.material_override = _material(kind, color)
	parent.add_child(visual)
	if solid: GEO.solid(parent, id, at, size)

static func build(parent: Node3D) -> void:
	var booth := Node3D.new()
	booth.name = "TicketBooth"
	parent.add_child(booth)
	# Retain the cabinet and back-post floor footprint. The cashier stands
	# behind the cabinet at (-3.2, .06, 21.1), on the real ground, never on the counter.
	_piece(booth, "TicketBoothCabinet", Vector3(-3.2,.48,22.5), Vector3(2.1,.96,1.8), 0, "365b50")
	for x in [-4.2,-2.2]:
		_piece(booth, "TicketBoothPost", Vector3(x,1.625,21.3), Vector3(.16,3.25,.16), 1, "98734d")
	# A higher, shallower canopy leaves the clerk's head visible from the gameplay
	# camera instead of placing the whole service window behind an opaque roof.
	_piece(booth, "TicketBoothRoof", Vector3(-3.2,3.35,21.35), Vector3(2.7,.22,2.1), 2, "334a46")
	# Thin finish layers sit against the existing solids; the overhanging worktop
	# has its own matching collider and keeps the approach to the front unobstructed.
	_piece(booth, "TicketBoothCounter", Vector3(-3.2,1.005,22.5), Vector3(2.22,.09,1.9), 3, "c4bba4")
	_piece(booth, "TicketBoothPlinth", Vector3(-3.2,.09,23.405), Vector3(2.1,.18,.014), 1, "62523e", false)
	for x in [-4.22,-2.18]:
		_piece(booth, "TicketBoothCorner", Vector3(x,.5,23.41), Vector3(.065,.9,.025), 1, "a58a60", false)
	_piece(booth, "TicketBoothFascia", Vector3(-3.2,3.22,22.38), Vector3(2.7,.14,.07), 1, "a58a60")
