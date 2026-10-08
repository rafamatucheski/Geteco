extends Node3D
## A real locked side room. The original lockpicking interaction consumes one
## carried tool only on success and records the opened door independently of loot.
const CONTENT := preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")
const MATERIALS := preload("res://world/places/harbor_buildings/HarborBuildingMaterials.gd")
const LOCKPICK := preload("res://runtime/BankLockpick.gd")
var session
var room: Node3D
var specification: Dictionary = {}
var door: MeshInstance3D
var door_body: StaticBody3D
var door_bounds := AABB()
var lockpick: CanvasLayer
var opened := false
var _owns_modal := false
var _active := true

static func populate(floor_room: Node3D, definition: Dictionary, floor_index: int, owner_session = null) -> Node3D:
	var node := new()
	node.name = "BuildingSecrets"
	node.room = floor_room
	node.session = owner_session
	node.specification = CONTENT.secret_spec(definition, floor_index)
	floor_room.add_child(node)
	node._build()
	node.reconcile()
	return node

func _build() -> void:
	if specification.is_empty():
		set_process(false)
		return
	var point: Vector3 = specification.door_position
	var rear: float = specification.room_back
	var front: float = specification.room_front
	var left: float = specification.room_left
	var door_start := point.z - .62
	var door_end := point.z + .62
	_solid("SecretRearPartition", Vector3(point.x, .61, (rear + door_start) * .5), Vector3(.13, 1.22, door_start - rear), "b0ad9d")
	_solid("SecretFrontPartition", Vector3(point.x, .61, (door_end + front) * .5), Vector3(.13, 1.22, front - door_end), "b0ad9d")
	_solid("SecretRoomFront", Vector3((left + point.x) * .5, .60, front), Vector3(point.x - left, 1.20, .14), "b0ad9d")
	# A visible masonry return closes the exact T-joint. Jolt can miss the
	# degenerate collinear seam of two thin boxes during one large body sweep.
	_solid("SecretCornerPost", Vector3(point.x, .625, front), Vector3(.28, 1.25, .28), "b0ad9d")
	door_bounds = AABB(point + Vector3(-.08, 0, -.60), Vector3(.16, 2.13, 1.20))
	door = _mesh(point + Vector3(0, 1.065, 0), Vector3(.10, 2.13, 1.18), "695d4d", "wood")
	door.name = "LockedRoomDoor"
	room._box_solid("BuildingSecretDoor", door_bounds)
	door_body = room.solid_bodies.back()
	var handle := _mesh(point + Vector3(.08, 1.02, .36), Vector3(.065, .10, .22), "a79774", "metal")
	handle.reparent(door, true)
	_mesh(point + Vector3(0, 2.18, -.4), Vector3(.13, .075, 2.15), "626e67", "metal")
	lockpick = LOCKPICK.new()
	lockpick.lock_title = "FECHADURA"
	lockpick.instruction_text = "ESPAÇO / CLIQUE — travar na faixa verde\nESC — desistir"
	add_child(lockpick)
	lockpick.unlocked.connect(_unlocked)
	lockpick.cancelled.connect(_cancelled)
	set_process(false)

func reconcile() -> void:
	if specification.is_empty() or session == null: return
	if session.state.world_state.get("harbor_building_unlocks", {}).get(specification.id, false): _open(false)

func set_active(value: bool) -> void:
	_active = value
	if value or not is_instance_valid(lockpick): return
	# CanvasLayer is independent of the room's 3D visibility. Cancel explicitly
	# before a sleeping room disables the child callback that normally does it.
	if lockpick.active: lockpick.finish(false)
	lockpick.hide()
	_cancelled()

func nearest_action() -> Dictionary:
	if not _active or specification.is_empty() or opened or session == null or session.modal or session.is_transition_blocked(): return {}
	if session.world.gameplay.health <= 0 or not is_visible_in_tree(): return {}
	var point: Vector3 = room.to_global(specification.door_position + Vector3(.60, 0, 0))
	if session.world.player.global_position.distance_to(point) > 1.2: return {}
	return {"id":"building_lockpick", "provider":self, "label":"Abrir fechadura · 1 lockpick"}

func perform(_action: Dictionary = {}) -> bool:
	if nearest_action().is_empty(): return false
	if int(session.state.economy.inventory.get("lockpick", 0)) < 1:
		session.show_message("É necessário um lockpick.")
		return false
	session.modal = true
	session.world.player.input_locked = true
	_owns_modal = true
	lockpick.begin()
	set_process(true)
	return true

func _process(_delta: float) -> void:
	if not _owns_modal: return
	if session == null or session.world.gameplay.health <= 0 or session.is_transition_blocked() or not is_visible_in_tree():
		if lockpick.active: lockpick.finish(false)
		_cancelled()

func _unlocked() -> void:
	if not _owns_modal or session == null: return
	if session.world.gameplay.health <= 0 or session.is_transition_blocked(): _cancelled(); return
	var target: Vector3 = room.to_global(specification.door_position + Vector3(.60, 0, 0))
	if session.world.player.global_position.distance_to(target) > 1.4: _cancelled(); return
	if not session.state.economy.consume_item("lockpick", 1): _cancelled(); return
	var state: Dictionary = session.state.world_state.get("harbor_building_unlocks", {}).duplicate()
	state[specification.id] = true
	session.state.world_state.harbor_building_unlocks = state
	_open(true)
	_cancelled()
	var occupants := room.get_node_or_null("BuildingOccupants")
	if is_instance_valid(occupants): occupants.notice_intrusion(session.world.player.global_position, session)
	session.save_game()

func _cancelled() -> void:
	set_process(false)
	if not _owns_modal: return
	_owns_modal = false
	if session != null and not session.is_transition_blocked(): session.close_menu()

func _open(animate: bool) -> void:
	if opened: return
	opened = true
	# A pocket door slides into its solid partition, never across the approach.
	if animate:
		var tween := create_tween()
		tween.tween_property(door, "position:z", door.position.z - 1.30, .32)
		tween.tween_callback(_release_door)
	else:
		door.position.z -= 1.30
		_release_door()

func _release_door() -> void:
	if is_instance_valid(door_body): door_body.collision_layer = 0
	if is_instance_valid(room): room.solid_bounds.erase(door_bounds)

func _exit_tree() -> void:
	if _owns_modal: _cancelled()

func _solid(id: String, at: Vector3, size: Vector3, color: String) -> void:
	if size.x <= 0 or size.z <= 0: return
	var mesh := _mesh(at, size, color, "stone")
	mesh.set_meta("interior_solid_id", id)
	room._box_solid(id, AABB(at - size * .5, size))

func _mesh(at: Vector3, size: Vector3, color: String, kind: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = MATERIALS.material(kind, Color(color))
	add_child(node)
	return node
