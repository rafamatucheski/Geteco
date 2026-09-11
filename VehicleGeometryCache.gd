extends RefCounted
## Protótipos sem script guardam somente a geometria inicial. Cada carro recebe
## materiais próprios, e o script de dano registra suas próprias peças em _ready.
static var _models: Dictionary = {}
static var hits := 0

static func prepare_common_models(tree: SceneTree) -> void:
	# Prepare one type per loading-screen frame, before control returns to play.
	for name in ["UnionSedan", "MetroHatch", "CourierVan", "RouteCity", "SummitSUV", "Boxrunner", "RanchSingle", "Towmaster", "ArcticJeep"]:
		var path: String = "res://prototypes/living_cast/models/" + name + "Model.gd"
		if _models.has(path): continue
		await tree.process_frame
		var model: Node3D = load(path).new()
		model.free()

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
