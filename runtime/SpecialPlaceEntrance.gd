extends Node
## Entra andando no porão do navio ou na caverna; o esgoto usa interação explícita.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SEWERS := preload("res://world/places/sewers/SewerNetwork.gd")
const UNDER := preload("res://world/desert/underground/DesertUnderground.gd")
const CULVERT := "desert_under_culvert"
const IDS := ["harbor_sewer", "sewer_market", "sewer_quay", "sewer_warehouse", "sewer_pipe", "sewer_cistern", "sewer_port", "santa_mare_hold", "mountain_mystery_cave"]
const ZOOM_SECONDS := .55
var session: Node
var definitions: Dictionary = {}
var busy := false
var blocked_id := ""
var current_place := ""
var exit_armed := false
var _arrival_clock := 0.0
var hatch: Node3D
var hatch_id := ""
var culvert_hold := 0.0

func handles_place(id: String) -> bool:
	return id in IDS or preload("res://world/desert/underground/DesertUnderground.gd").is_underground(id)

func _ready() -> void:
	for id in IDS: definitions[id] = PLACES.get_definition(id)
	for id in UNDER.ids(): definitions[id] = PLACES.get_definition(id)

func _blocked() -> bool:
	return busy or session.modal or session.is_transition_blocked() or session.world.player.input_locked or session.world.gameplay.health <= 0 or session.world.driving.occupied or session.world.driving.is_body_transition_active()

func _door(id: String) -> Vector3:
	var definition: Dictionary = definitions[id]
	if id == "mountain_mystery_cave": return definition.exterior_position + Vector3(0,0,.9)
	return definition.entry_position

func update(delta: float) -> void:
	if not session.ready_for_play or session.get_tree().paused: return
	var place: String = session.state.place_id
	if place != current_place:
		current_place = place
		exit_armed = false
		_arrival_clock = 0.0
	if handles_place(place):
		if not is_instance_valid(session.room) or _blocked(): return
		if place == CULVERT:
			var local: Vector3 = session.room.to_local(session.world.player.global_position)
			var focus: Vector3 = session.room.to_global(Vector3(clampf(local.x, -12.0, 12.0), .7, 0))
			session.anchor.position = session.anchor.position.lerp(focus, 1.0-exp(-delta*7.0))
		var branch_offset: Vector3 = session.room.exit_position-session.world.player.global_position
		branch_offset.y = 0
		# Também arma 1 s depois de chegar: no Cano Entupido e no Dreno do Porto a
		# chegada fica a 0,5 m da escada e entulho impede afastar 1,3 m; a saída nunca
		# armava. Continua exigindo empurrar rumo à escada, então ninguém sai ao pousar.
		_arrival_clock += delta
		if branch_offset.length() > 1.3 or _arrival_clock > 1.0: exit_armed = true
		var player: CharacterBody3D = session.world.player
		var toward := branch_offset.normalized()
		# Encostado na parede da escada a velocidade zera antes dos 0,8 m: contava só a
		# velocidade e o jogador empurrando a escada nunca saía do bueiro (auditoria de
		# portas 15/10: parado a 0,5 m da saída). Pedir movimento rumo à saída vale.
		var pushing := player.velocity.dot(toward) > .3 or Vector3(player.move_intent.x, 0, player.move_intent.z).dot(toward) > .5
		if exit_armed and branch_offset.length() < .8 and pushing:
			_leave(place)
		return
	if not place.is_empty(): return
	if session.state.region_id == "desert":
		_update_culvert(delta)
		return
	var point: Vector3 = session.world.player.global_position
	var id := ""
	var distance := INF
	for candidate in IDS:
		if SEWERS.is_manhole(candidate): continue
		if definitions[candidate].region != session.state.region_id: continue
		var d := point.distance_squared_to(_door(candidate))
		if d < distance: distance = d; id = candidate
	if id.is_empty(): return
	if not blocked_id.is_empty() and (blocked_id != id or distance > 6.25): blocked_id = ""
	_update_hatch(id, distance < 9.0 and not _blocked(), delta)
	if _blocked() or blocked_id == id: return
	var offset := point-_door(id)
	if id == "mountain_mystery_cave":
		if absf(offset.x) > .72 or offset.z < -.25 or offset.z > .6 or session.world.player.velocity.z > -.5: return
	elif distance > .55*.55 or session.world.player.velocity.length_squared() < .3:
		return
	blocked_id = id
	_enter(id)

func _update_culvert(delta: float) -> void:
	var player: CharacterBody3D = session.world.player
	var definition: Dictionary = definitions[CULVERT]
	if player.global_position.distance_squared_to(definition.entry_position) > 144.0:
		if hatch_id == CULVERT and is_instance_valid(hatch) and not busy: hatch.set_open_amount(0.0)
		blocked_id = ""
		return
	if hatch_id != CULVERT or not is_instance_valid(hatch):
		hatch = session._find_sewer_hatch(CULVERT)
		hatch_id = CULVERT
	if not is_instance_valid(hatch) or _blocked(): return
	var local: Vector3 = hatch.to_local(player.global_position)
	if local.z > 1.5: blocked_id = ""
	var intent: Vector3 = session.weapon_shop_entrance._movement_intent(player)
	var inward: Vector3 = -hatch.global_basis.z
	var pushing := absf(local.x) < .95 and local.z >= -.1 and local.z <= .75 and intent.dot(inward) > .3
	if pushing:
		if culvert_hold <= 0.0 and hatch.open_amount < .1:
			var gesture = session.weapon_shop_entrance
			gesture._push_age = 0.0
			gesture._push_inward = inward
			gesture.set_physics_process(true)
		culvert_hold = .7
	else: culvert_hold = maxf(0.0, culvert_hold-delta)
	if hatch.open_amount > .1 and absf(local.x) < 1.0 and absf(local.z-.1) < .65:
		culvert_hold = maxf(culvert_hold, .2)
	hatch.set_open_amount(move_toward(hatch.open_amount, 1.0 if culvert_hold > 0.0 else 0.0, delta/.35))
	if blocked_id == CULVERT or hatch.open_amount < .85: return
	if absf(local.x) < .9 and local.z < .05 and local.z > -.65 and intent.dot(inward) > .3:
		blocked_id = CULVERT
		_enter(CULVERT)

func _update_hatch(id: String, opened: bool, delta: float) -> void:
	if hatch_id != id:
		if is_instance_valid(hatch): hatch.set_open_amount(0.0)
		hatch = null
		hatch_id = id
	if not is_instance_valid(hatch) and opened:
		if id == "santa_mare_hold": hatch = get_tree().get_first_node_in_group("santa_mare_hold_hatch") as Node3D
	if is_instance_valid(hatch) and not busy:
		hatch.set_open_amount(move_toward(float(hatch.get("open_amount")),1.0 if opened else 0.0,delta/.35))

func _enter(id: String) -> void:
	busy = true
	var player: CharacterBody3D = session.world.player
	var camera = session.world.camera
	var generation: int = session.transition_generation
	player.input_locked = true
	camera.focus_on_store(_door(id)+Vector3.UP*.5,8.0,ZOOM_SECONDS)
	await get_tree().create_timer(ZOOM_SECONDS).timeout
	var admitted: bool = session.transition_generation == generation and not session.modal and not session.is_transition_blocked() and session.world.gameplay.health > 0
	if admitted:
		player.input_locked = false
		await session.enter_place(id,true,id)
	if is_instance_valid(hatch): hatch.set_open_amount(0.0)
	if is_instance_valid(camera): camera.clear_store_focus()
	if not session.modal and not session.is_transition_blocked(): player.input_locked = false
	busy = false

func _leave(id: String) -> void:
	busy = true
	var left: bool = await session.leave_place()
	if left:
		blocked_id = id
		var player = session.world.player
		player.input_locked = true
		var camera = session.world.camera
		camera.zoom_out_from_store(_door(id),8.0,ZOOM_SECONDS)
		camera._process(0.0)
		await get_tree().create_timer(ZOOM_SECONDS).timeout
		camera.clear_store_focus()
		if not session.modal and not session.is_transition_blocked(): player.input_locked = false
	busy = false
