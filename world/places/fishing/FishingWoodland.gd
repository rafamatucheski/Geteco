extends RefCounted
## Deterministic spatial MultiMeshes and native trunks; no per-frame processing.
const LAYOUT := preload("res://world/places/fishing/FishingRuralLayout.gd")
const LOCATION := preload("res://runtime/FishingLocation.gd")
const WOOD := preload("res://gameplay/urban_v1/FreightOutskirts.gd")
const CELL := 64.0
const TREE_LIMIT := 208
static var _trees: Array[Dictionary] = []
static var _shrubs: Array[Dictionary] = []
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _prepared := false

static func tree_inventory() -> Array[Dictionary]:
	_prepare()
	return _trees.duplicate(true)

static func _prepare() -> void:
	if _prepared: return
	_prepared = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 8102026
	var candidates: Array[Vector2] = []
	for ix in 20:
		for iz in 27:
			var point := Vector2(-578+ix*7.5,-121+iz*7.2)+Vector2(rng.randf_range(-1.2,1.2),rng.randf_range(-1.2,1.2))
			if LAYOUT.tree_available(point): candidates.append(point)
	# Shuffle with this local generator only, preserving every other system's RNG.
	for index in range(candidates.size()-1,0,-1):
		var other := rng.randi_range(0,index)
		var temporary := candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = temporary
	for index in mini(TREE_LIMIT,candidates.size()):
		var point := candidates[index]
		var height := rng.randf_range(8.0,12.8)
		var radius := rng.randf_range(.25,.39)
		_trees.append({"point":Vector3(point.x,0,point.y),"height":height,"radius":radius,
			"crown":rng.randf_range(5.2,7.3),"variant":rng.randi_range(0,2),"yaw":rng.randf()*TAU})
	for index in 650:
		var point := Vector2(rng.randf_range(-579,-435),rng.randf_range(-122,70))
		if not LAYOUT.tree_available(point): continue
		_shrubs.append({"point":Vector3(point.x,.30,point.y),"size":rng.randf_range(.7,1.45),"yaw":rng.randf()*TAU})
	_meshes.trunk = WOOD._wood_mesh()
	for variant in 3: _meshes["crown_%d"%variant] = WOOD._canopy_mesh(variant)
	var shrub := SphereMesh.new()
	shrub.radius = .5
	shrub.height = 1
	shrub.radial_segments = 8
	shrub.rings = 4
	_meshes.shrub = shrub
	for row in [["trunk","65503b"],["crown_0","425d36"],["crown_1","66784a"],["crown_2","526d43"],["shrub","5e7545"]]:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(row[1])
		material.vertex_color_use_as_albedo = true
		material.roughness = .94
		_materials[row[0]] = material

static func build_chunk(parent: Node3D, rect: Rect2) -> void:
	var pieces := LAYOUT.clipped_land(rect)
	if pieces.is_empty(): return
	preload("res://world/places/fishing/FishingGround.gd").finish_entrance_roads(parent,rect)
	_prepare()
	var node := Node3D.new()
	node.name = "SerenoWoodland"
	parent.add_child(node)
	var body := StaticBody3D.new()
	body.name = "WoodlandTrunks"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	var batches := {}
	for tree in _trees:
		var point: Vector3 = tree.point
		if not rect.has_point(Vector2(point.x,point.z)): continue
		_put(batches,"trunk",point,Vector3(tree.radius/.04,tree.height,tree.radius/.04),tree.yaw)
		_put(batches,"crown_%d"%tree.variant,point+Vector3.UP*tree.height*.70,Vector3(tree.crown,tree.height*.54,tree.crown*.94),tree.yaw)
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = tree.radius
		shape.height = tree.height*.67
		collision.shape = shape
		collision.position = point+Vector3.UP*shape.height*.5
		collision.set_meta("sereno_tree",point)
		body.add_child(collision)
	for shrub in _shrubs:
		var point: Vector3 = shrub.point
		if rect.has_point(Vector2(point.x,point.z)):
			_put(batches,"shrub",point,Vector3(1.2,.65,1.0)*shrub.size,shrub.yaw)
	for key in batches:
		var transforms: Array = batches[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _meshes[key]
		multimesh.instance_count = transforms.size()
		for index in transforms.size(): multimesh.set_instance_transform(index,transforms[index])
		var display := MultiMeshInstance3D.new()
		display.name = "Sereno_"+str(key)
		display.multimesh = multimesh
		display.material_override = _materials[key]
		if key=="shrub": display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(display)

static func _put(batches: Dictionary, kind: String, point: Vector3, size: Vector3, yaw: float) -> void:
	if not batches.has(kind): batches[kind] = []
	batches[kind].append(Transform3D(Basis(Vector3.UP,yaw).scaled(size),point))
