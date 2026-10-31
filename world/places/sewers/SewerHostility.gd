extends Node
## One room owns its social graph and walkable grid; never enroll service staff.
const RESIDENT := preload("res://world/places/sewers/SewerResident.gd")
const LOADOUTS := {
	"sewer_market_abel": "bottle", "sewer_quay_marlene": "knife",
	"sewer_warehouse_zeca": "pistol", "sewer_pipe_maluco": "claw",
}
var session: Node
var room: Node3D
var residents: Array[CharacterBody3D] = []
var grid := AStarGrid2D.new()
var _relay_left := .6

static func install(owner_session: Node, spec: Dictionary, point: Vector3) -> CharacterBody3D:
	var owner_room: Node3D = owner_session.room
	var ecosystem = owner_room.get_node_or_null("SewerHostility")
	if ecosystem == null:
		ecosystem = load("res://world/places/sewers/SewerHostility.gd").new()
		ecosystem.name = "SewerHostility"
		ecosystem.session = owner_session
		ecosystem.room = owner_room
		owner_room.add_child(ecosystem)
	var actor = RESIDENT.new()
	actor.definition = spec.duplicate(true)
	actor.ecosystem = ecosystem
	actor.gameplay = owner_session.world.gameplay
	actor.position = point
	actor.weapon_id = str(spec.get("weapon", LOADOUTS.get(str(spec.id), ["fists", "knife", "claw", "bottle", "pistol"][ecosystem.residents.size() % 5])))
	owner_session.world.add_child(actor)
	ecosystem.residents.append(actor)
	return actor

func _ready() -> void:
	var size: Vector2 = room.definition.size
	grid.region = Rect2i(Vector2i.ZERO, Vector2i(ceil(size.x / .5), ceil(size.y / .5)))
	grid.cell_size = Vector2(.5, .5)
	grid.offset = -size * .5 + Vector2(.25, .25)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for y in grid.region.size.y:
		for x in grid.region.size.x:
			var cell := Vector2i(x, y)
			var point := grid.get_point_position(cell)
			grid.set_point_solid(cell, not room.is_floor_clear(Vector3(point.x, 0, point.y), .36))

func active() -> bool:
	return is_instance_valid(session) and is_instance_valid(room) and room.active \
		and session.state.place_id == room.definition.id and not session.world.player.input_locked \
		and session.world.gameplay.health > 0

func provoke(victim: CharacterBody3D, source: Node3D) -> void:
	if not active() or source != session.world.player: return
	victim.engage(source)
	# Espalha pelos vizinhos presentes no grito, antes de correrem em direção ao
	# Dante e saírem do alcance de audição do próximo aliado. Cada ator entra no máximo uma vez.
	var callers: Array[CharacterBody3D] = [victim]
	while not callers.is_empty():
		var caller: CharacterBody3D = callers.pop_front()
		callers.append_array(_relay(caller, source))

func _relay(caller: CharacterBody3D, source: Node3D) -> Array[CharacterBody3D]:
	var awakened: Array[CharacterBody3D] = []
	for peer in residents:
		if not is_instance_valid(peer) or peer.dead or peer.hostile or peer == caller: continue
		var distance := caller.global_position.distance_to(peer.global_position)
		# Nearby shouts pass through clutter; more distant allies must see the caller.
		if distance > 12.0 or (distance > 6.0 and not caller.can_see(peer)): continue
		peer.engage(source)
		awakened.append(peer)
	return awakened

func _physics_process(delta: float) -> void:
	if not active(): return
	_relay_left -= delta
	if _relay_left > 0: return
	_relay_left = .6
	for actor in residents:
		if is_instance_valid(actor) and not actor.dead and actor.hostile:
			_relay(actor, session.world.player)

func _cell(point: Vector3) -> Vector2i:
	var local := room.to_local(point)
	return Vector2i(roundi((local.x-grid.offset.x)/.5), roundi((local.z-grid.offset.y)/.5))

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start := _cell(from)
	var end := _cell(to)
	var result := PackedVector3Array()
	if not grid.is_in_boundsv(start) or not grid.is_in_boundsv(end): return result
	# A body may stand between cells; choose a clear adjacent cell, never teleport.
	for which in 2:
		var cell := start if which == 0 else end
		if not grid.is_point_solid(cell): continue
		var best := cell
		var closest := INF
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var candidate := cell + Vector2i(dx, dy)
				if not grid.is_in_boundsv(candidate) or grid.is_point_solid(candidate): continue
				var distance := Vector2(candidate-cell).length_squared()
				if distance < closest: best = candidate; closest = distance
		if closest == INF: return result
		if which == 0: start = best
		else: end = best
	for point in grid.get_point_path(start, end):
		result.append(room.to_global(Vector3(point.x, .04, point.y)))
	return result
