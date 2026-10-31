extends RefCounted
## Purchasable native 3D props. Callers own placement and room lifetime.
## Beds have a genuinely open front (-Z); the shallow cushion is a floor textile.

const MODEL := preload("res://runtime/cats/CatModel.gd")
static var _meshes: Dictionary = {}


static func create(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "CatFurniture_%s" % kind
	root.set_meta("cat_furniture", kind)
	match kind:
		"bed":
			_bed(root)
		"toy", "ball", "toys":
			_toy(root)
		"scratcher", "scratch":
			_scratcher(root)
		_:
			push_warning("Unknown cat furniture: %s" % kind)
	return root


static func animate(root: Node3D, delta: float, playing: bool) -> void:
	if not is_instance_valid(root):
		return
	var toy := root.get_node_or_null("Ball") as Node3D
	if toy != null:
		var strength := 2.8 if playing else 0.0
		toy.rotation.z += delta * strength
		toy.rotation.x += delta * strength * 0.63


static func _bed(root: Node3D) -> void:
	root.set_meta("footprint", Vector2(0.94, 0.82))
	root.set_meta("use_position", Vector3(0,0,-.12))
	root.set_meta("approach_position", Vector3(0, 0, -0.65))
	root.set_meta("use_activity", "sleep")
	if not _meshes.has("bed"):
		var parts: Array = []
		# Tecido verde-azulado denso, recorte costurado e debrum creme, com frente vazada.
		MODEL._oval(parts, Vector3(0, 0.007, 0), Vector3(0.425, 0.012, 0.354), Color("607e7a"))
		MODEL._oval(parts, Vector3(0, 0.014, -0.025), Vector3(0.347, 0.014, 0.286), Color("c8bfa6"))
		for side in [-1.0, 1.0]:
			MODEL._oval(parts, Vector3(side * 0.409, 0.093, 0.02), Vector3(0.061, 0.09, 0.371), Color("446661"))
			MODEL._oval(parts, Vector3(side * 0.405, 0.162, 0.018), Vector3(0.046, 0.014, 0.328), Color("8faaa0"))
		MODEL._oval(parts, Vector3(0, 0.101, 0.329), Vector3(0.413, 0.096, 0.081), Color("446661"))
		MODEL._oval(parts, Vector3(0, 0.182, 0.326), Vector3(0.374, 0.014, 0.047), Color("8faaa0"))
		_meshes.bed = MODEL._bake(parts)
	MODEL._node("FabricBed", _meshes.bed, root)
	# Três volumes separados preservam a entrada e a área de dormir.
	_solid_box(root, "LeftBolster", Vector3(-0.41, 0.086, 0.025), Vector3(0.12, 0.17, 0.72))
	_solid_box(root, "RightBolster", Vector3(0.41, 0.086, 0.025), Vector3(0.12, 0.17, 0.72))
	_solid_box(root, "BackBolster", Vector3(0, 0.09, 0.337), Vector3(0.81, 0.18, 0.14))


static func _toy(root: Node3D) -> void:
	root.set_meta("footprint", Vector2(0.20, 0.20))
	root.set_meta("use_position", Vector3(0, 0, -0.39))
	root.set_meta("approach_position", Vector3(0, 0, -0.68))
	root.set_meta("use_activity", "play")
	if not _meshes.has("toy"):
		var parts: Array = []
		MODEL._oval(parts, Vector3.ZERO, Vector3.ONE * 0.095, Color("d79853"))
		for n in range(3):
			var band := TorusMesh.new()
			band.inner_radius = 0.090
			band.outer_radius = 0.096
			band.rings = 16
			band.ring_segments = 6
			parts.append([band, Transform3D(Basis.from_euler(Vector3(float(n) * PI / 3.0, 0.0, PI / 2.0)), Vector3.ZERO), Color("678e9c")])
		_meshes.toy = MODEL._bake(parts)
	var ball := MODEL._node("Ball", _meshes.toy, root)
	ball.position.y = 0.095
	var body := StaticBody3D.new()
	body.name = "ToySolid"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id", "cat_toy")
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.095
	shape.shape = sphere
	shape.position.y = 0.095
	body.add_child(shape)
	root.add_child(body)


static func _scratcher(root: Node3D) -> void:
	root.set_meta("footprint", Vector2(0.52, 0.52))
	root.set_meta("use_position", Vector3(0, 0, -0.45))
	root.set_meta("approach_position", Vector3(0, 0, -0.78))
	root.set_meta("use_activity", "scratch")
	if not _meshes.has("scratcher"):
		var parts: Array = []
		var base := BoxMesh.new()
		base.size = Vector3(0.5, 0.065, 0.5)
		parts.append([base, Transform3D(Basis.IDENTITY, Vector3(0, 0.033, 0)), Color("625047")])
		var post := CylinderMesh.new()
		post.top_radius = 0.064
		post.bottom_radius = 0.07
		post.height = 0.62
		post.radial_segments = 12
		parts.append([post, Transform3D(Basis.IDENTITY, Vector3(0, 0.368, 0)), Color("bca682")])
		for n in range(12):
			var rope := TorusMesh.new()
			rope.inner_radius = 0.060
			rope.outer_radius = 0.071
			rope.rings = 12
			rope.ring_segments = 4
			parts.append([rope, Transform3D(Basis.IDENTITY, Vector3(0, 0.08 + float(n) * 0.05, 0)), Color("887554")])
		MODEL._oval(parts, Vector3(0, 0.69, 0), Vector3(0.083, 0.035, 0.083), Color("536e68"))
		_meshes.scratcher = MODEL._bake(parts)
	MODEL._node("SisalPost", _meshes.scratcher, root)
	_solid_box(root, "ScratcherBase", Vector3(0, 0.033, 0), Vector3(0.5, 0.065, 0.5))
	_solid_box(root, "ScratcherPost", Vector3(0, 0.38, 0), Vector3(0.15, 0.7, 0.15))


static func _solid_box(root: Node3D, label: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id", "cat_" + label.to_snake_case())
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = center
	body.add_child(collider)
	root.add_child(body)
