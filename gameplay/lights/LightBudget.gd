extends RefCounted
## Só registra faróis e giroflex de VehicleEquipment: neon e fogo têm outros donos.
static var enabled := OS.get_environment("GETECO_LIGHT_BUDGET") != "0"
const MAX_LIGHTS := 8
const MAX_NPC_HEADLIGHTS := 2
const LIGHT_RADIUS := 25.0
const NPC_HANDOFF_SECONDS := .16
const NPC_PRIORITY_MARGIN := 1.5
static var _owners: Dictionary = {}
static var _frame := -1
static var _npc_incumbents: Dictionary = {}
static var _npc_fades: Dictionary = {}
static var _last_tick := 0

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
	var all_lights: Array[Light3D] = []
	for id in _owners.keys():
		var owner = _owners[id].get_ref()
		if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.is_queued_for_deletion():
			_owners.erase(id)
			continue
		var request: Dictionary = owner._budget_request()
		all_lights.append_array(request.lights)
		for source: Dictionary in request.wanted:
			var distance: float = source.light.global_position.distance_to(request.camera)
			var race_headlight: bool = bool(request.get("race_headlights",false)) and source.headlight
			# Fade by distance to the player, independent of camera elevation/zoom.
			var energy := float(source.light.get_meta("budget_energy", source.light.light_energy))
			var weight := 1.0 if request.player or race_headlight else 1.0 - smoothstep(22.0, LIGHT_RADIUS, distance)
			var target := energy * weight
			if not is_equal_approx(source.light.light_energy, target): source.light.light_energy = target
			if request.player or race_headlight or distance <= LIGHT_RADIUS:
				lights.append({"node": source.light, "player": request.player, "headlight": source.headlight, "distance": distance, "race_headlight": race_headlight})
	lights.sort_custom(_nearer)
	# Real shadowed traffic beams replace the emissive pavement decals. Bound
	# their cost independently so the player's projectors always keep priority.
	var selected_lights: Array[Dictionary] = []
	var desired_npc: Dictionary = {}
	var eligible_npc: Dictionary = {}
	var npc_headlights := 0
	for entry in lights:
		if not entry.player and entry.headlight:
			var id: int = entry.node.get_instance_id()
			eligible_npc[id] = entry
			if npc_headlights < MAX_NPC_HEADLIGHTS:
				desired_npc[id] = true
				npc_headlights += 1
		else: selected_lights.append(entry)
	_npc_incumbents = desired_npc
	# Nearby cars used to swap fully powered beams at every distance tie.
	# Keep a small positional margin and cross-fade a handoff, within MAX_LIGHTS.
	var now := Time.get_ticks_usec()
	var delta := minf(.05,float(now-_last_tick)/1000000.0) if _last_tick > 0 else 1.0/60.0
	_last_tick = now
	for id in desired_npc:
		if not _npc_fades.has(id): _npc_fades[id] = 0.0
	var transitional: Array[Dictionary] = []
	for id in _npc_fades.keys():
		# Power-off, damage, despawn and out-of-range are immediate. Only a
		# priority handoff fades; a dead or hidden owner cannot keep emitting.
		if not eligible_npc.has(id):
			_npc_fades.erase(id)
			continue
		var gain := move_toward(float(_npc_fades[id]),1.0 if desired_npc.has(id) else 0.0,delta/NPC_HANDOFF_SECONDS)
		if gain <= .0001 and not desired_npc.has(id):
			_npc_fades.erase(id)
			continue
		_npc_fades[id] = gain
		var entry: Dictionary = eligible_npc[id]
		var faded_energy: float = entry.node.light_energy * gain
		if not is_equal_approx(entry.node.light_energy,faded_energy): entry.node.light_energy = faded_energy
		if gain > .0001: transitional.append(entry)
	transitional.sort_custom(_nearer)
	# Two steady traffic sources; up to two retiring sources only for the
	# brief handoff. Player projectors and the total eight-light cap remain.
	selected_lights.append_array(transitional.slice(0,MAX_NPC_HEADLIGHTS*2))
	selected_lights.sort_custom(_nearer)
	_apply(all_lights, selected_lights, MAX_LIGHTS)

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
	# A framed physical opponent uses the same two NPC slots, ahead of ambient
	# traffic. Neither the total cap nor the number of steady NPC sources grows.
	var a_race: bool = bool(a.get("race_headlight",false))
	var b_race: bool = bool(b.get("race_headlight",false))
	if a_race != b_race: return a_race
	var a_distance: float = a.distance - (NPC_PRIORITY_MARGIN if not a.player and a.headlight and _npc_incumbents.has(a.node.get_instance_id()) else 0.0)
	var b_distance: float = b.distance - (NPC_PRIORITY_MARGIN if not b.player and b.headlight and _npc_incumbents.has(b.node.get_instance_id()) else 0.0)
	if not is_equal_approx(a_distance, b_distance): return a_distance < b_distance
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
	return result
