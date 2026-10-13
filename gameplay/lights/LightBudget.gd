extends RefCounted
## Só registra faróis e giroflex de VehicleEquipment: neon e fogo têm outros donos.
static var enabled := OS.get_environment("GETECO_LIGHT_BUDGET") != "0"
const MAX_LIGHTS := 8
const MAX_DECALS := 8
const LIGHT_RADIUS := 25.0
static var _owners: Dictionary = {}
static var _frame := -1

static func register(owner: Node) -> void:
	_owners[owner.get_instance_id()] = weakref(owner)
	_frame = -1

static func unregister(owner: Node) -> void:
	_owners.erase(owner.get_instance_id())
	_frame = -1

static func refresh(force: bool = false) -> void:
	if not enabled: return
	var frame := Engine.get_process_frames()
	if not force and frame == _frame: return
	_frame = frame
	var lights: Array[Dictionary] = []
	var decals: Array[Dictionary] = []
	var all_lights: Array[Light3D] = []
	var all_decals: Array[Decal] = []
	for id in _owners.keys():
		var owner = _owners[id].get_ref()
		if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.is_queued_for_deletion():
			_owners.erase(id)
			continue
		var request: Dictionary = owner._budget_request()
		all_lights.append_array(request.lights)
		if is_instance_valid(request.decal): all_decals.append(request.decal)
		for source: Dictionary in request.wanted:
			var distance: float = source.light.global_position.distance_to(request.camera)
			# A fonte de NPC termina suavemente no limite de 25 m. O jogador
			# conserva a energia original, inclusive na câmera aérea a 36 m.
			var energy := float(source.light.get_meta("budget_energy", source.light.light_energy))
			var weight := 1.0 if request.player else 1.0 - smoothstep(22.0, LIGHT_RADIUS, distance)
			var target := energy * weight
			if not is_equal_approx(source.light.light_energy, target): source.light.light_energy = target
			if request.player or distance <= LIGHT_RADIUS:
				lights.append({"node": source.light, "player": request.player, "headlight": source.headlight, "distance": distance})
		if request.pool and is_instance_valid(request.decal):
			var offset: Vector3 = request.decal.global_position - request.camera
			decals.append({"node": request.decal, "player": request.player, "headlight": true, "distance": Vector2(offset.x, offset.z).length()})
	lights.sort_custom(_nearer)
	decals.sort_custom(_nearer)
	_apply(all_lights, lights, MAX_LIGHTS)
	_apply(all_decals, decals, MAX_DECALS)

static func _apply(nodes: Array, ranked: Array[Dictionary], maximum: int) -> void:
	var selected := {}
	for index in mini(maximum, ranked.size()): selected[ranked[index].node.get_instance_id()] = true
	# Desliga os perdedores primeiro: uma troca nunca acende nove fontes,
	# nem temporariamente durante a mudança de câmera ou o roubo de um carro.
	for node: Node3D in nodes:
		if node.visible and not selected.has(node.get_instance_id()): node.hide()
	for index in mini(maximum, ranked.size()):
		var node: Node3D = ranked[index].node
		if not node.visible: node.show()

static func _nearer(a: Dictionary, b: Dictionary) -> bool:
	if a.player != b.player: return a.player
	# Protege o par de faróis do jogador antes do halo da sua sirene.
	if a.player and a.headlight != b.headlight: return a.headlight
	if not is_equal_approx(a.distance, b.distance): return a.distance < b.distance
	return a.node.get_instance_id() < b.node.get_instance_id()

static func counts() -> Dictionary:
	var result := {"registered": 0, "active_lights": 0, "active_decals": 0}
	for reference: WeakRef in _owners.values():
		var owner = reference.get_ref()
		if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.is_queued_for_deletion(): continue
		result.registered += 1
		var request: Dictionary = owner._budget_request()
		for light: Light3D in request.lights:
			if light.is_visible_in_tree() and light.light_energy > 0: result.active_lights += 1
		if is_instance_valid(request.decal) and request.decal.is_visible_in_tree(): result.active_decals += 1
	return result
