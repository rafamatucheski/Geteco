extends RefCounted
## Protótipos sem script guardam somente a geometria inicial. Cada carro recebe
## materiais próprios, e o script de dano registra suas próprias peças em _ready.
static var _models: Dictionary = {}
static var hits := 0
static var _prepared: Dictionary = {}
const STARTUP_PRESENTATION_MARGIN := 320.0

static func is_startup_relevant(actor: Node2D) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not actor.is_visible_in_tree():
		return false
	if actor.get_meta("proximity_sleeping", false):
		return false
	if actor.get("is_driven_by_player") == true:
		return true
	var screen_position := actor.get_global_transform_with_canvas().origin
	return screen_position.is_finite() and actor.get_viewport_rect().grow(STARTUP_PRESENTATION_MARGIN).has_point(screen_position)

static func prepare_common_models(tree: SceneTree) -> void:
	var batch := preload("res://ui/LoadingWorkBatch.gd").new()
	# Warm the entire expensive geometry path, not only the raw constructor.
	# Wheel-well cutting and surface batching otherwise first run in gameplay.
	var staging := Node3D.new()
	staging.name = "VehicleGeometryPreparation"
	staging.visible = false
	staging.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(staging)
	for name in ["UnionSedan", "SportEstate", "NordicEstate", "MetroHatch", "CourierVan", "RouteCity", "SummitSUV", "PoliceSUV", "Boxrunner", "RanchSingle", "Towmaster", "ArcticJeep", "OrbitaMicro", "AuroraExecutive", "ValeCrossover", "NimbusMinivan", "VerticeMidEngine", "BravioCrew", "DockDeliveryVan"]:
		var path: String = "res://prototypes/living_cast/models/" + name + "Model.gd"
		if _prepared.has(path): continue
		await batch.checkpoint(tree)
		var model: Node3D = load(path).new()
		staging.add_child(model)
		var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
		rig.mount(model)
		preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
		model.free()
		_prepared[path] = true
	for path in ["res://geodata/transit/RegionalIntercityCoachModel.gd"]:
		if _prepared.has(path): continue
		await batch.checkpoint(tree)
		var res = load(path)
		if res:
			var model: Node3D = res.new()
			staging.add_child(model)
			var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
			rig.mount(model)
			preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
			model.free()
			_prepared[path] = true
	staging.free()

static func prepare_resident_presentations(tree: SceneTree) -> int:
	var batch := preload("res://ui/LoadingWorkBatch.gd").new()
	# Only the entry view belongs on the critical loading path. Deferred actors
	# already keep a lightweight silhouette and remain queued in PresentationBudget,
	# which resolves them shortly before they enter the camera. Building the whole
	# city's rigs here made every save wait for distant residents it could not see.
	var prepared := 0
	for vehicle in tree.get_nodes_in_group("modern_traffic"):
		if not is_instance_valid(vehicle) or not vehicle.has_method("ensure_presentation"): continue
		if vehicle.get("_pending_spec") == null or vehicle.get("_pending_spec").is_empty(): continue
		if not is_startup_relevant(vehicle): continue
		await batch.checkpoint(tree)
		if not is_instance_valid(vehicle) or not vehicle.is_inside_tree(): continue
		vehicle.ensure_presentation()
		prepared += 1
	for car in tree.get_nodes_in_group("modern_parked_vehicle") + tree.get_nodes_in_group("regional_coach"):
		if not is_instance_valid(car) or not car.has_method("ensure_presentation"): continue
		if car.get("_pending_spec") == null or car.get("_pending_spec").is_empty(): continue
		if not is_startup_relevant(car): continue
		await batch.checkpoint(tree)
		if not is_instance_valid(car) or not car.is_inside_tree(): continue
		car.ensure_presentation()
		prepared += 1
	for walker in tree.get_nodes_in_group("pedestrian") + tree.get_nodes_in_group("authored_sidewalk_pedestrian"):
		if not is_instance_valid(walker) or not walker.has_method("ensure_presentation"): continue
		if walker.get("viewport") != null: continue
		if not is_startup_relevant(walker): continue
		await batch.checkpoint(tree)
		if not is_instance_valid(walker) or not walker.is_inside_tree(): continue
		walker.ensure_presentation()
		prepared += 1
	for signal_post in tree.get_nodes_in_group("fixed_traffic_signal"):
		if not is_instance_valid(signal_post) or not signal_post.has_method("ensure_presentation"): continue
		if not is_startup_relevant(signal_post): continue
		await batch.checkpoint(tree)
		if not is_instance_valid(signal_post) or not signal_post.is_inside_tree(): continue
		var original_state: int = int(signal_post.get("signal_state"))
		for state in [0, 1, 2]:
			signal_post.signal_state = state
			signal_post.ensure_presentation()
		signal_post.signal_state = original_state
		signal_post.ensure_presentation()
		prepared += 1
	return prepared

static func restore(model: Node3D) -> bool:
	var key: String = model.get_script().resource_path
	if not key.begins_with("res://prototypes/living_cast/models/"): return false
	if not _models.has(key): return false
	var data: Dictionary = _models[key]
	var raw: Node3D = data.scene.instantiate()
	var copies := {}
	model.materials = {}
	for role in data.materials:
		model.materials[role] = _material(data.materials[role],copies)
	model.paint = _material(data.paint,copies)
	model.vehicle_id = data.vehicle_id
	_rebind(raw,copies)
	_own_children(raw,null)
	for metadata in raw.get_meta_list(): model.set_meta(metadata,raw.get_meta(metadata))
	for child in raw.get_children():
		raw.remove_child(child)
		model.add_child(child)
	raw.free()
	hits += 1
	return true

static func capture(model: Node3D) -> void:
	var key: String = model.get_script().resource_path
	if not key.begins_with("res://prototypes/living_cast/models/"): return
	if _models.has(key) or not _static_children(model): return
	# Equipamentos com âncoras de operação (canhão d'água, guindaste) ainda
	# precisam executar seu construtor para ligar as referências de gameplay.
	for property in model.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and _has_node_reference(model.get(property.name)):
			return
	var raw := model.duplicate(0) as Node3D
	var copies := {}
	var materials := {}
	for role in model.materials: materials[role] = _material(model.materials[role],copies)
	var paint := _material(model.paint,copies)
	_rebind(raw,copies)
	_own_children(raw,raw)
	var scene := PackedScene.new()
	if scene.pack(raw) == OK:
		_models[key] = {"scene":scene,"materials":materials,"paint":paint,"vehicle_id":model.vehicle_id}
	raw.free()

static func _has_node_reference(value: Variant) -> bool:
	if value is Node: return true
	if value is Array:
		for item in value:
			if _has_node_reference(item): return true
	if value is Dictionary:
		for key in value:
			if _has_node_reference(key) or _has_node_reference(value[key]): return true
	return false

static func _static_children(node: Node) -> bool:
	for child in node.get_children():
		if child.get_script() != null or not _static_children(child): return false
	return true

static func _own_children(node: Node,owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own_children(child,owner_node)

static func _material(source: Material,copies: Dictionary) -> Material:
	if source == null: return null
	if not copies.has(source): copies[source] = source.duplicate()
	return copies[source]

static func _rebind(node: Node,copies: Dictionary) -> void:
	if node is GeometryInstance3D:
		node.material_override = _material(node.material_override,copies)
		node.material_overlay = _material(node.material_overlay,copies)
	for child in node.get_children(): _rebind(child,copies)
