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
	# Embaralha só com este gerador local, preservando o RNG de todos os outros sistemas.
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
	_meshes.shrub = WOOD._shrub_mesh()
	for row in [["trunk","514232"],["crown_0","364a32"],["crown_1","53613b"],["crown_2","435637"],["shrub","4b6039"]]:
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
	var fragile: Array[Dictionary] = []
	for tree in _trees:
		var point: Vector3 = tree.point
		if not rect.has_point(Vector2(point.x,point.z)): continue
		_put(batches,"trunk",point,Vector3(tree.radius/.04,tree.height,tree.radius/.04),tree.yaw)
		_put(batches,"crown_%d"%tree.variant,point+Vector3.UP*tree.height*.70,Vector3(tree.crown,tree.height*.54,tree.crown*.94),tree.yaw)
		var collision := CollisionShape3D.new()
		fragile.append(tree_entry(batches,tree,collision))
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
	var displays := {}
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
		displays[key] = display
	register_fragile_trees(node,fragile,displays)

## Índices da árvore recém-posta (tronco e copa) e o seu colisor, para o registro de quebráveis.
static func tree_entry(batches: Dictionary, tree: Dictionary, collision: CollisionShape3D) -> Dictionary:
	var crown_key := "crown_%d"%int(tree.variant)
	var trunks: Array = batches.trunk
	var crowns: Array = batches[crown_key]
	# Offset da copa a partir dos lotes: sem janela a MultiMesh devolve instâncias na origem.
	return {"trunk":trunks.size()-1,"crown_key":crown_key,"crown":crowns.size()-1,
		"offset":(trunks[-1] as Transform3D).affine_inverse()*(crowns[-1] as Transform3D),
		"collision":collision,"radius":float(tree.radius)}

## Playtest 29/10 ("algumas árvores não derrubam"): as árvores da mata (Lago Sereno e a faixa nova
## da costa de Harbor) só tinham tronco sólido, fora do FragileProps3D; o carro parava nelas a
## qualquer velocidade. Viram "woodland_tree": tombam na base com a copa junto (peça irmã) e o
## tronco solta o carro. O raio de contato passa o do colisor em 12 cm para a varredura do carro
## pegar a árvore antes da física nativa pará-lo no tronco.
static func register_fragile_trees(node: Node3D, entries: Array[Dictionary], displays: Dictionary) -> void:
	if entries.is_empty() or not displays.has("trunk"): return
	# O registro precisa da posição global; chunk montado fora da árvore registra ao entrar.
	if not node.is_inside_tree():
		node.tree_entered.connect(register_fragile_trees.bind(node,entries,displays),CONNECT_ONE_SHOT)
		return
	var fragile := preload("res://gameplay/street_physics/FragileProps3D.gd")
	var trunk: MultiMeshInstance3D = displays.trunk
	for entry in entries:
		var crown: MultiMeshInstance3D = displays[entry.crown_key]
		fragile.register_instance("woodland_tree",trunk.multimesh,entry.trunk,node,
			[{"multimesh":crown.multimesh,"index":entry.crown,"offset":entry.offset}],[entry.collision],trunk,float(entry.radius)+.12)

static func _put(batches: Dictionary, kind: String, point: Vector3, size: Vector3, yaw: float) -> void:
	if not batches.has(kind): batches[kind] = []
	batches[kind].append(Transform3D(Basis(Vector3.UP,yaw).scaled(size),point))
