extends Node
const BOARD := preload("res://activities/skate/SkateBody.gd")
const POSE := preload("res://activities/skate/SkatePose.gd")
const LAYOUT := preload("res://activities/skate/SkateParkLayout.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var session
var mounted := false
var recovering := false
var owned := false
var best := 0
var score := 0
var player_board: CharacterBody3D
var parked: CharacterBody3D
var boards: Array[CharacterBody3D] = []
var ambient: Array[Dictionary] = []
var _fallen: Array[Dictionary] = []
var _park_people: Array[WeakRef] = []
var hud: Label
var _clock := 0.0
var _recovery_time := 0.0
var _layer := 2
var _mask := 7
var _camera_size := 28.0
var _last_heading := 0.0

func configure(owner_session) -> void:
	session = owner_session
	process_physics_priority = 10
	var saved: Variant = session.state.world_state.get("skate", {})
	if not saved is Dictionary or (not saved.is_empty() and not validate_snapshot(saved)):
		session.controller.save_invalid = true
		session.show_message("Dados de skate inválidos; save preservado.")
	else:
		owned = bool(saved.get("owned", false))
		best = int(saved.get("best", 0))
	hud = Label.new()
	hud.position = Vector2(230, 620)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 5)
	session.world.hud.add_child(hud)

static func validate_snapshot(data: Dictionary) -> bool:
	return data.get("owned") is bool and (data.get("best") is int or data.get("best") is float) and is_finite(float(data.best)) and float(data.best) >= 0 and float(data.best) <= 100000000 and float(data.best) == floorf(float(data.best))

func snapshot() -> Dictionary: return {"owned": owned, "best": best}

func controls_locked() -> bool: return mounted or recovering

func available() -> bool:
	return session.ready_for_play and not session.modal and not session.is_transition_blocked() and session.state.region_id == "harbor" and session.state.place_id.is_empty() and not session.world.driving.occupied and not session.motocross.mounted and session.world.gameplay.health > 0

func nearest_action() -> Dictionary:
	if session == null or not available() or recovering: return {}
	if mounted: return {"id": "skate", "target": "dismount", "label": "Descer do skate"}
	for board in boards:
		if is_instance_valid(board) and not board.riding and absf(board.speed) < 1.5 and session.world.player.position.distance_to(board.position) < 1.7:
			return {"id": "skate", "target": str(board.get_instance_id()), "label": "Pegar skate"}
	return {}

func perform(target: String) -> bool:
	if nearest_action().get("target", "") != target: return false
	if target == "dismount": return dismount()
	for board in boards:
		if is_instance_valid(board) and str(board.get_instance_id()) == target: return mount(board)
	return false

func _new_board(at: Vector3, tint: Color = Color("d36c3e")) -> CharacterBody3D:
	var board := BOARD.new()
	board.color = tint
	board.position = at
	session.world.add_child(board)
	boards.append(board)
	return board

func mount(board: CharacterBody3D) -> bool:
	if not available() or mounted or recovering or not is_instance_valid(board) or board.riding: return false
	if session.world.player.position.distance_to(board.position) > 1.7: return false
	# Taking a loose board brings it under the player's feet; never move Dante
	# into the fallen rider's capsule or across a wall to mount.
	# The real player's swept body already established this support. A second
	# wider capsule at the foot origin incorrectly rejected sloping bowl floors.
	if not session.world.player.is_on_floor(): return false
	board.position = session.world.player.position
	if is_instance_valid(parked) and parked != board:
		boards.erase(parked)
		parked.queue_free()
	parked = board
	player_board = board
	owned = true
	mounted = true
	score = 0
	var player = session.world.player
	_layer = player.collision_layer
	_mask = player.collision_mask
	_camera_size = session.world.camera.target_size
	player.input_locked = true
	player.set_physics_process(false)
	player.collision_layer = 0
	player.collision_mask = 0
	player.clear_combat_weapon_pose()
	board.rider = player
	board.riding = true
	board.collision_layer = 4
	board.collision_mask = 7
	board._grace = .6
	board.bailed.connect(_player_bailed)
	board.trick_landed.connect(_landed)
	session.world.camera.target = board
	session.world.camera.target_size = 24
	session.world.gameplay.aiming = false
	return true

func _clear_for_player(point: Vector3, board: CharacterBody3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.7
	query.shape = shape
	query.collision_mask = 7
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * .9)
	query.exclude = [session.world.player.get_rid(), board.get_rid()]
	return session.world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _release_board() -> void:
	if is_instance_valid(player_board):
		_last_heading = player_board.rotation.y
		player_board.riding = false
		player_board.collision_layer = 0
		player_board.collision_mask = 1
		player_board.drive(0, 0, true)
		player_board.rider = null
		player_board.trick = ""
		player_board.trick_total = 0
		player_board.deck.rotation = Vector3.ZERO
		if player_board.bailed.is_connected(_player_bailed): player_board.bailed.disconnect(_player_bailed)
		if player_board.trick_landed.is_connected(_landed): player_board.trick_landed.disconnect(_landed)
	player_board = null
	mounted = false
	session.world.camera.target = session.world.player
	session.world.camera.target_size = _camera_size
	session.world.player.collision_layer = _layer
	session.world.player.collision_mask = _mask

func dismount() -> bool:
	if not mounted or not is_instance_valid(player_board): return false
	if player_board.airborne or player_board.speed > 1.2:
		session.show_message("Freie para descer do skate.")
		return false
	for side in [-1, 1]:
		var point: Vector3 = player_board.position + player_board.global_basis.x * side * .8
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.5, point - Vector3.UP * 2, 1)
		var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty(): continue
		point = hit.position + Vector3.UP * .04
		if not session.position_clear(point): continue
		_release_board()
		session.world.player.teleport(point)
		_finish_recovery()
		session.save_game()
		return true
	session.show_message("Aproxime o skate de um lugar livre para descer.")
	return false

func handle_input(event: InputEvent) -> void:
	if not mounted or not is_instance_valid(player_board): return
	if event.is_action_pressed("interact") or event.is_action_pressed("exit_vehicle"): dismount()
	elif event.is_action_pressed("skate_ollie"): player_board.ollie()
	elif event.is_action_pressed("skate_flip"): player_board.start_trick("flip")
	elif event.is_action_pressed("skate_shove"): player_board.start_trick("shove")

func _landed(points: int, title: String) -> void:
	score += points
	best = maxi(best, score)
	session.show_message("%s · +%d" % [title, points])

func _player_bailed(damage: float) -> void:
	if not mounted: return
	var player = session.world.player
	player.velocity = -player_board.global_basis.z * player_board.speed * .55
	player.velocity.y = maxf(0, player_board.velocity.y) * .3
	_release_board()
	recovering = true
	hud.text = ""
	_recovery_time = 0
	player.input_locked = true
	score = 0
	# Falls injure the body, not the armor, just like environmental accidents.
	session.world.gameplay.damage_environment(damage)
	session.show_message("Caiu do skate")

func _finish_recovery() -> void:
	recovering = false
	POSE.restore(session.world.player)
	session.world.player.velocity = Vector3.ZERO
	session.world.player.set_physics_process(session.world.gameplay.health > 0 and not session.is_transition_blocked())
	session.world.player.input_locked = session.modal or session.is_transition_blocked() or session.world.gameplay.health <= 0
	hud.text = ""

func _physics_process(delta: float) -> void:
	if not LAYOUT.enabled(): return
	if session == null or not session.ready_for_play: return
	if controls_locked() and (session.is_transition_blocked() or session.world.gameplay.health <= 0 or not session.state.place_id.is_empty() or session.state.region_id != "harbor"):
		_release_board()
		_finish_recovery()
	if recovering:
		if session.modal: return
		_recovery_time += delta
		var player = session.world.player
		player.velocity.y -= 20 * delta
		player.velocity.x = move_toward(player.velocity.x, 0, delta * 5)
		player.velocity.z = move_toward(player.velocity.z, 0, delta * 5)
		player.move_and_slide()
		POSE.fall(player, _recovery_time, _last_heading)
		if _recovery_time >= 2.1 and player.is_on_floor(): _finish_recovery()
	elif mounted:
		if not is_instance_valid(player_board):
			_release_board()
			_finish_recovery()
			return
		if session.modal:
			player_board.drive(0, 0, true)
		else:
			var controls = get_node("/root/GameInput")
			var throttle := maxf(Input.get_action_strength("move_up"), Input.get_action_strength("accelerate"))
			var steer := Input.get_axis("move_right", "move_left")
			if not controls.touch_move.is_zero_approx():
				throttle = maxf(0, -controls.touch_move.y)
				steer = -controls.touch_move.x
			player_board.drive(throttle, steer, Input.is_action_pressed("move_down") or Input.is_action_pressed("brake") or controls.touch_move.y > .2)
		session.world.player.position = player_board.position
		POSE.apply(session.world.player, player_board)
		hud.text = "%d km/h · %d pts · recorde %d\nW remar · S frear · Espaço ollie · Q flip · R shove-it · E descer" % [roundi(player_board.speed * 3.6), score, best]
	_clock += delta
	if _clock >= 1:
		_clock = 0
		_update_population()
	_update_ambient(delta)
	_update_fallen(delta)

func _update_population() -> void:
	boards = boards.filter(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion())
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty():
		_clear_ambient()
		return
	var p: Vector3 = session.world.player.position
	if p.distance_to(LAYOUT.CENTER) < 65 and not get_tree().get_nodes_in_group("skate_park").is_empty():
		if not is_instance_valid(parked) and not controls_locked(): parked = _new_board(LAYOUT.ENTRY)
		_park_people = _park_people.filter(func(ref): return is_instance_valid(ref.get_ref()))
		if _park_people.is_empty():
			for i in 2:
				var actor := ACTOR.new()
				actor.identity = 4 + i
				actor.position = _park_route()[i * 12] + Vector3.UP * .03
				actor.set_meta("region_id", "harbor")
				session.world.add_child(actor)
				_park_people.append(weakref(actor))
				var board := _new_board(actor.position, Color("487d9b") if i == 0 else Color("c3a842"))
				_attach_ambient(actor, board, true)
	# Retire only distant riders: street skaters must survive leaving the park.
	for row in ambient.duplicate():
		if not is_instance_valid(row.actor) or row.actor.position.distance_to(p) > (80 if row.park else 100):
			_retire_ambient(row)
	for ref in _park_people.duplicate():
		var actor = ref.get_ref()
		if not is_instance_valid(actor): _park_people.erase(ref)
		elif actor.position.distance_to(p) > 80:
			actor.queue_free()
			_park_people.erase(ref)
	# Occasionally borrow an ordinary, healthy street pedestrian's existing route.
	var street_count := 0
	for row in ambient:
		if not row.park: street_count += 1
	street_count += _fallen.size()
	if street_count < 3:
		for actor in session.world.people:
			if not is_instance_valid(actor) or actor.dead or actor.health < 100 or actor.route.size() < 2 or actor.input_locked or not actor.is_physics_processing(): continue
			if actor.identity % 5 != 0 or actor.position.distance_to(p) > 85 or not actor.is_on_floor(): continue
			if actor.has_meta("skate_used"): continue
			actor.set_meta("skate_used", true)
			var palette := [Color("d36c3e"), Color("487d9b"), Color("c3a842"), Color("79559b"), Color("44866a")]
			var board := _new_board(actor.position, palette[(actor.identity / 5) % palette.size()])
			_attach_ambient(actor, board, false)
			break
	for board in boards.duplicate():
		if board == parked or board.riding: continue
		if board.position.distance_to(p) > 90 or boards.size() > 7:
			boards.erase(board)
			board.queue_free()

func _attach_ambient(actor, board, park: bool) -> void:
	actor.set_physics_process(false)
	actor.visual.get_child(0).set_process(false)
	board.add_collision_exception_with(actor)
	board.rider = actor
	board.riding = true
	board.collision_layer = 4
	board.collision_mask = 7
	board.bailed.connect(func(damage): _ambient_bail(actor, board, damage))
	var route: PackedVector3Array = actor.route
	if park: route = _park_route()
	var waypoint: int = int(actor.waypoint) % route.size()
	if park: waypoint = 1
	if park and actor.identity % 2 == 1: waypoint = 13
	board._push_clock = fposmod(actor.identity * .173, .72)
	ambient.append({"actor": actor, "board": board, "route": route, "waypoint": waypoint, "health": actor.health, "park": park, "stalled": 0.0, "pace": 2.2 if park else 2.7 + (actor.identity % 4) * .45})
	board.rotation.y = atan2(-(route[waypoint] - actor.position).x, -(route[waypoint] - actor.position).z)

func _park_route() -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in 24:
		var angle := TAU * i / 24.0
		var p := Vector2(LAYOUT.CENTER.x, LAYOUT.CENTER.z) + Vector2(cos(angle), sin(angle)) * LAYOUT.RADII * .55
		result.append(Vector3(p.x, LAYOUT.height_at(p), p.y))
	return result

func _update_ambient(delta: float) -> void:
	for row in ambient.duplicate():
		if not is_instance_valid(row.actor) or not is_instance_valid(row.board):
			_retire_ambient(row)
			continue
		if row.actor.dead or row.actor.health < row.health:
			row.board.bail(0)
			continue
		if session.modal:
			row.board.drive(0, 0, true)
			continue
		var target: Vector3 = row.route[row.waypoint]
		var toward: Vector3 = target - row.board.position
		toward.y = 0
		if toward.length() < (.65 if row.park else 1.5): row.waypoint = (int(row.waypoint) + 1) % row.route.size()
		var angle := angle_difference(row.board.rotation.y, atan2(-toward.x, -toward.z))
		var pace: float = row.pace
		row.board.drive(1 if row.board.speed < pace else 0, clampf(angle * 2, -1, 1), (absf(angle) > .65 and row.board.speed > 1.5) or row.board.speed > pace + .7)
		row.stalled = float(row.stalled) + delta if row.board.speed < .4 else 0.0
		if row.stalled > 4: row.board.bail(0); continue
		row.actor.position = row.board.position
		POSE.apply(row.actor, row.board)

func _ambient_bail(actor, board, damage: float) -> void:
	for row in ambient.duplicate():
		if row.board != board: continue
		ambient.erase(row)
		board.rider = null
		if is_instance_valid(actor):
			if not actor.dead:
				POSE.restore(actor)
				if damage > 0: actor.receive_damage(damage, board)
				if actor.dead: continue
				actor.set_physics_process(false)
				actor.visual.get_child(0).set_process(false)
				actor.velocity = -board.global_basis.z * board.speed * .45
				actor.input_locked = true
				_fallen.append({"actor": actor, "age": 0.0, "heading": board.rotation.y, "park": row.park})
		# Board remains physical and collectible; ownership only changes on pickup.

func _update_fallen(delta: float) -> void:
	if session.modal: return
	for row in _fallen.duplicate():
		var actor = row.actor
		if not is_instance_valid(actor) or actor.dead:
			_fallen.erase(row)
			continue
		row.age += delta
		actor.velocity.y -= 20 * delta
		actor.velocity.x = move_toward(actor.velocity.x, 0, 5 * delta)
		actor.velocity.z = move_toward(actor.velocity.z, 0, 5 * delta)
		actor.move_and_slide()
		POSE.fall(actor, row.age, row.heading)
		if row.age >= 2.1 and actor.is_on_floor():
			POSE.restore(actor)
			actor.input_locked = false
			actor.set_physics_process(true)
			_fallen.erase(row)

func _retire_ambient(row: Dictionary) -> void:
	if is_instance_valid(row.actor):
		if row.park: row.actor.queue_free()
		elif not row.actor.dead:
			POSE.restore(row.actor)
			row.actor.waypoint = int(row.waypoint)
			row.actor.set_physics_process(true)
	if is_instance_valid(row.board):
		boards.erase(row.board)
		row.board.queue_free()
	ambient.erase(row)

func _clear_ambient() -> void:
	for row in ambient.duplicate():
		_retire_ambient(row)
	for row in _fallen:
		if not is_instance_valid(row.actor) or row.actor.dead: continue
		POSE.restore(row.actor)
		row.actor.input_locked = false
		row.actor.set_physics_process(true)
	_fallen.clear()
	for ref in _park_people:
		var actor = ref.get_ref()
		if is_instance_valid(actor): actor.queue_free()
	_park_people.clear()

func _exit_tree() -> void:
	_clear_ambient()
	if is_instance_valid(hud): hud.queue_free()
