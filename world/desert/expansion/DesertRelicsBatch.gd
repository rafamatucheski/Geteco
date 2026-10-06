extends RefCounted
## Small static construction buffer: unit meshes/materials are shared, draw calls
## are grouped by shape/finish, and one body owns the explicit solid volumes.
const MATERIALS := preload("res://world/desert/DesertTownMaterials.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
static var _meshes: Dictionary = {}
var root: Node3D
var body: StaticBody3D
var groups: Dictionary = {}
var rail_step_bodies: Dictionary = {}
var pieces := 0

func _init(parent: Node3D, label: String, at: Vector3) -> void:
	root = Node3D.new()
	root.name = label
	root.position = at
	root.set_meta("desert_relic", true)
	parent.add_child(root)
	body = StaticBody3D.new()
	body.name = "RelicSolids"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("vehicle_surface", "hard")
	root.add_child(body)

func box(label: String, at: Vector3, size: Vector3, finish: String, solid := true, rotation := Vector3.ZERO) -> void:
	_add("box", finish, Transform3D(Basis.from_euler(rotation) * Basis.from_scale(size), at))
	if not solid: return
	var shape := BoxShape3D.new()
	shape.size = size
	_collision(label, at, rotation, shape)

func cylinder(label: String, at: Vector3, radius: float, height: float, finish: String, solid := true, rotation := Vector3.ZERO) -> void:
	_add("cylinder", finish, Transform3D(Basis.from_euler(rotation) * Basis.from_scale(Vector3(radius, height, radius)), at))
	if not solid: return
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	_collision(label, at, rotation, shape)

func rail_collision(label: String, at: Vector3, size: Vector3, rotation := Vector3.ZERO) -> void:
	# Authored horizontal rails are shallow steps, unlike the furniture/ruins
	# sharing this construction buffer. Group only rails with the same top level
	# so PedestrianStep3D receives the actual support height under the capsule.
	var top: float = at.y+size.y*.5
	if not rail_step_bodies.has(top):
		var rail_body := StaticBody3D.new()
		rail_body.name = "WalkableRelicRails"
		rail_body.collision_layer = 1
		rail_body.collision_mask = 0
		rail_body.set_meta("vehicle_surface","hard")
		rail_body.set_meta("pedestrian_step",true)
		rail_body.set_meta("pedestrian_step_top",top)
		root.add_child(rail_body)
		rail_step_bodies[top] = rail_body
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.name = label
	collider.shape = shape
	collider.position = at
	collider.rotation = rotation
	collider.set_meta("desert_relic_solid",label)
	(rail_step_bodies[top] as StaticBody3D).add_child(collider)

func beam(label: String, start: Vector3, end: Vector3, width: float, finish: String, solid := true) -> void:
	var delta := end - start
	var frame := Basis(Quaternion(Vector3.UP, delta.normalized()))
	box(label, (start + end) * .5, Vector3(width, delta.length(), width), finish, solid, frame.get_euler())

func _add(shape: String, finish: String, transform: Transform3D) -> void:
	var key := shape + ":" + finish
	if not groups.has(key): groups[key] = {"shape":shape, "finish":finish, "transforms":[]}
	groups[key].transforms.append(transform)
	pieces += 1

func _collision(label: String, at: Vector3, rotation: Vector3, shape: Shape3D) -> void:
	var collider := CollisionShape3D.new()
	collider.name = label
	collider.shape = shape
	collider.position = at
	collider.rotation = rotation
	collider.set_meta("desert_relic_solid", label)
	body.add_child(collider)

func finish() -> Node3D:
	for key in groups:
		var group: Dictionary = groups[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _mesh(group.shape)
		multimesh.instance_count = group.transforms.size()
		for i in group.transforms.size(): multimesh.set_instance_transform(i, group.transforms[i])
		var visual := MultiMeshInstance3D.new()
		visual.name = "RelicBatch_" + key.replace(":", "_")
		visual.multimesh = multimesh
		visual.material_override = G.material(Color("a99270"),true) if group.finish=="trail" else MATERIALS.material(group.finish)
		root.add_child(visual)
	if body.get_child_count() == 0: body.free()
	root.set_meta("relic_piece_count", pieces)
	return root

static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind): return _meshes[kind]
	var mesh: PrimitiveMesh
	if kind == "cylinder":
		var cylinder_mesh := CylinderMesh.new()
		cylinder_mesh.top_radius = 1.0
		cylinder_mesh.bottom_radius = 1.0
		cylinder_mesh.height = 1.0
		cylinder_mesh.radial_segments = 12
		cylinder_mesh.rings = 1
		mesh = cylinder_mesh
	else:
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3.ONE
		mesh = box_mesh
	_meshes[kind] = mesh
	return mesh
