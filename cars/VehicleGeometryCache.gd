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
	# Warm the entire expensive geometry and GPU pipeline path.
	# Compiling CSG/SurfaceTool geometry and Vulkan shaders in warmup prevents 150ms hitches during gameplay.
	var warmup_view := SubViewport.new()
	warmup_view.name = "VehicleWarmupViewport"
	warmup_view.size = Vector2i(96, 96)
	warmup_view.own_world_3d = true
	warmup_view.transparent_bg = true
	warmup_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	tree.root.add_child(warmup_view)

	var cam := Camera3D.new()
	warmup_view.add_child(cam)
	cam.look_at_from_position(Vector3(0, 8, 4), Vector3(0, 0.45, 0), Vector3.UP)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.0

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	warmup_view.add_child(sun)

	var model_names := [
		"UnionSedan", "SportEstate", "NordicEstate", "MetroHatch", "CourierVan",
		"RouteCity", "SummitSUV", "PoliceSUV", "Boxrunner", "RanchSingle",
		"Towmaster", "ArcticJeep", "OrbitaMicro", "AuroraExecutive", "ValeCrossover",
		"NimbusMinivan", "VerticeMidEngine", "BravioCrew", "DockDeliveryVan",
		"YellowCab", "AmericanDump", "AmericanFlatbed", "AmericanTanker"
	]
	for name in model_names:
		var path: String = "res://prototypes/living_cast/models/" + name + "Model.gd"
		if _prepared.has(path) or not ResourceLoader.exists(path): continue
		await batch.checkpoint(tree)
		var res = load(path)
		if res:
			var model: Node3D = res.new()
			warmup_view.add_child(model)
			var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
			rig.mount(model)
			preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
			warmup_view.render_target_update_mode = SubViewport.UPDATE_ONCE
			model.free()
		_prepared[path] = true

	for path in [
		"res://prototypes/living_cast/CabrioletModel.gd",
		"res://prototypes/living_cast/BossMuscleModel.gd",
		"res://geodata/transit/RegionalIntercityCoachModel.gd"
	]:
		if _prepared.has(path) or not ResourceLoader.exists(path): continue
		await batch.checkpoint(tree)
		var res = load(path)
		if res:
			var model: Node3D = res.new()
			warmup_view.add_child(model)
			var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
			rig.mount(model)
			preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
			warmup_view.render_target_update_mode = SubViewport.UPDATE_ONCE
			model.free()
		_prepared[path] = true

	# Modelos dos veículos que existem no mundo carregado e ficaram fora da lista fixa
	for group in ["modern_traffic", "modern_parked_vehicle", "regional_coach"]:
		for vehicle in tree.get_nodes_in_group(group):
			if not is_instance_valid(vehicle): continue
			var spec = vehicle.get("_pending_spec")
			if not spec is Dictionary or spec.is_empty(): continue
			var path := String(spec.get("model_class", ""))
			if path.is_empty() or _prepared.has(path) or not ResourceLoader.exists(path): continue
			await batch.checkpoint(tree)
			var res = load(path)
			if res:
				var model: Node3D = res.new()
				warmup_view.add_child(model)
				var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
				rig.mount(model)
				preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
				warmup_view.render_target_update_mode = SubViewport.UPDATE_ONCE
				model.free()
			_prepared[path] = true
	warmup_view.queue_free()

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
	if not (key.begins_with("res://prototypes/living_cast/models/") or key.begins_with("res://prototypes/living_cast/")): return false
	if not _models.has(key): return false
	var data: Dictionary = _models[key]
	var raw: Node3D = data.scene.instantiate()
	var copies := {}
	model.materials = {}
	for role in data.materials:
		model.materials[role] = _material(data.materials[role],copies)
	if "vehicle_id" in model: model.vehicle_id = data.get("vehicle_id", "")
	if "paint" in model:
		model.paint = _material(data.get("paint"), copies)
		if model.paint == null and model.materials.has("paint"):
			model.paint = model.materials["paint"]
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
	if not (key.begins_with("res://prototypes/living_cast/models/") or key.begins_with("res://prototypes/living_cast/")): return
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
		_models[key] = {"scene":scene,"materials":materials,"paint":paint,"vehicle_id":model.get("vehicle_id") if "vehicle_id" in model else ""}
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
