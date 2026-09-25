extends Node
const Dialogue := preload("res://data/catalogs/ServiceDialogue.gd")
const HOSPITAL_PICKUP := Vector3(2,0,-1)
const FIRE_HEAL := Vector3(10,0,-120.0/28.0)
const AUTO_ORIGIN := Vector3(4925,0,-1198)/16.0
const AUTO_BAY := Rect2(-20.0/16.0,-155.0/16.0,40.0/16.0,48.0/16.0)
const AUTO_PRICE := 100
const AUTO_SECONDS := 4.5
var session
var hospital_cooldown := 0.0
var auto_serial := 0
var serviced_count := 0
var _car: CharacterBody3D
var _elapsed := 0.0
var _heal_accum := 0.0
var _fire_active := false
var _departing: CharacterBody3D
var _cross: Node3D
var _cross_room: Node3D
var _insufficient := false
var _last_vehicle := ""
var _auto_phase := "idle"
var _phase_elapsed := 0.0
var _auto_saved := {}
var _auto_committed := false
var _presentation: Node3D

func configure(owner_session) -> void:
	session = owner_session
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if session.world is Node:
		_presentation = preload("res://runtime/NorthgateServicePresentation.gd").new()
		_presentation.position = AUTO_ORIGIN
		session.world.add_child(_presentation)

func _physics_process(delta: float) -> void:
	if session == null or not session.ready_for_play or not is_finite(delta) or delta<=0: return
	if hospital_cooldown > 0: hospital_cooldown = maxf(0,hospital_cooldown-delta)
	_update_cross()
	var gameplay = session.world.gameplay
	var on_foot: bool = not session.world.driving.occupied and gameplay.health>0
	if on_foot and session.state.place_id == "harbor_hospital" and _near(HOSPITAL_PICKUP,.75):
		if hospital_cooldown<=0 and gameplay.heal(100):
			hospital_cooldown = 180
			if is_instance_valid(_cross): _cross.hide()
			session.save_game()
	var healing: bool = on_foot and session.state.place_id == "harbor_fire_station" and _near(FIRE_HEAL,1.05)
	if healing and gameplay.health<100:
		_heal_accum += delta*9.0
		var whole := int(_heal_accum)
		if whole > 0:
			_heal_accum -= whole
			gameplay.heal(whole)
			_fire_active = true
	if _fire_active and (not healing or gameplay.health>=100):
		_fire_active = false
		_heal_accum = 0
		session.save_game()
	if not healing: _heal_accum = 0
	_tick_auto(delta)

func _near(local: Vector3, radius: float) -> bool:
	return is_instance_valid(session.room) and session.world.player.global_position.distance_to(session.room.to_global(local))<=radius

func nearest_action() -> Dictionary:
	if session == null or session.world.driving.occupied or not is_instance_valid(session.room): return {}
	var choices: Dictionary = {}
	match session.state.place_id:
		"harbor_hospital": choices = {"hospital_triage":Vector3(2,0,-3.5)}
		"harbor_police": choices = {"police_terminal":Vector3(-4.2,0,1.5)}
		"harbor_fire_station": choices = {"fire_alarm":Vector3(-10,0,-120.0/28.0)}
	var npcs := _npc_points()
	choices.merge(npcs)
	var best := {}
	var nearest := INF
	for id in choices:
		var point: Vector3 = session.room.to_global(choices[id])
		var distance: float = session.world.player.global_position.distance_to(point)
		if distance <= (1.7 if npcs.has(id) else 1.15) and distance < nearest:
			nearest=distance
			best={"id":"original_service","target":id,"label":"Conversar" if npcs.has(id) else "Examinar","position":point}
	return best

func _npc_points() -> Dictionary:
	var result := {}
	if session==null or not is_instance_valid(session.room): return result
	var definition: Variant = session.room.get("definition")
	if not definition is Dictionary: return result
	for npc in definition.get("npcs",[]):
		if not Dialogue.PEOPLE.has(npc.get("id","")): continue
		var point: Variant = npc.get("local_position")
		if session.room.interaction_points.has(npc.id): point=session.room.to_local(session.room.interaction_points[npc.id])
		if point is Vector3: result[npc.id]=point
	return result

func perform(service: String) -> bool:
	# The production-compatible Monaliza service lives at the physical workbench;
	# FullSession deliberately has no generic remote-repair fallback.
	if service == "garage":
		if session == null or session.state.place_id != "maciota" or session.world.driving.occupied: return false
		session.show_message("Use a bancada para cuidar da Monaliza.")
		return true
	if not Dialogue.PEOPLE.has(service) or session == null or session.world.driving.occupied: return false
	var place: String = session.state.place_id
	var expected := "harbor_hospital" if service.begins_with("hospital") else ("harbor_fire_station" if service.begins_with("fire") else "harbor_police")
	if place != expected: return false
	if service in ["hospital_triage","police_terminal","fire_alarm"]:
		if nearest_action().get("target","") != service: return false
	else:
		var npcs := _npc_points()
		if npcs.has(service):
			if not _near(npcs[service],1.7): return false
		elif not npcs.is_empty(): return false
		elif not is_instance_valid(session.room) or session.world.player.global_position.distance_to(session.room.interaction_points.service)>1.7: return false
	session.show_dialogue(Dialogue.lines(service))
	return true

func _auto_eligible(car) -> bool:
	if not is_instance_valid(car) or not session.state.place_id.is_empty() or session.state.region_id != "harbor": return false
	if not session.world.driving.occupied or session.world.driving.car != car or session.world.gameplay.health<=0 or car.health<=0: return false
	# Boarding owns temporary input locks; service starts only after the driver is seated.
	if session.world.driving.is_body_transition_active() or not car.controlled or car.input_locked: return false
	var relative: Vector3 = car.global_position-AUTO_ORIGIN
	return absf(car.speed)<.15 and car.horizontal_velocity.length()<.2 and AUTO_BAY.has_point(Vector2(relative.x,relative.z))

func _tick_auto(delta: float) -> void:
	var car = session.world.driving.car if session.world.driving.occupied else null
	_update_auto_presentation(car)
	if _auto_phase != "idle" and not is_instance_valid(_car):
		cancel_auto_service("vehicle_removed")
		return
	if not is_instance_valid(_car) and is_instance_valid(car) and car.vehicle_id == _last_vehicle:
		if car.global_position.distance_to(AUTO_ORIGIN)<=210.0/16.0: return
		_last_vehicle = ""
	if is_instance_valid(_departing):
		if _departing.global_position.distance_to(AUTO_ORIGIN)>210.0/16.0: _departing=null
		elif car == _departing: return
	if is_instance_valid(_car):
		if not _auto_still_valid(car):
			cancel_auto_service("interrupted")
			return
		_tick_active_auto(delta)
	elif _auto_eligible(car):
		if session.state.economy.balance < AUTO_PRICE:
			if not _insufficient: session.show_message("Serviço: R$ 100 · dinheiro insuficiente.")
			_insufficient = true
			return
		_insufficient = false
		_start_auto_service(car)
		session.show_message("Reparando veículo…")
	else: _insufficient = false

func _update_auto_presentation(car) -> void:
	if not is_instance_valid(_presentation): return
	var in_harbor: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
	_presentation.visible = in_harbor
	if not in_harbor or is_instance_valid(_car): return
	var visitor: Node3D = car if is_instance_valid(car) else session.world.player
	_presentation.set_shutter_open(is_instance_valid(visitor) and visitor.global_position.distance_to(AUTO_ORIGIN) < 210.0/16.0)

func _start_auto_service(target: CharacterBody3D) -> void:
	_car = target
	_elapsed = 0
	_phase_elapsed = 0
	_auto_phase = "closing"
	_auto_committed = false
	_auto_saved = {
		"physics":target.is_physics_processing(),
		"layer":target.collision_layer,
		"mask":target.collision_mask,
		"input_locked":target.get("input_locked") == true,
		"player_locked":session.world.player.get("input_locked") == true,
	}
	target.set_meta("pay_n_spray_busy",true)
	session.world.player.set_meta("pay_n_spray_busy",true)
	if "input_locked" in target: target.input_locked = true
	if "input_locked" in session.world.player: session.world.player.input_locked = true
	if "speed" in target: target.speed = 0.0
	if "horizontal_velocity" in target: target.horizontal_velocity = Vector3.ZERO
	target.velocity = Vector3.ZERO
	target.collision_layer = 0
	target.collision_mask = 0
	target.set_physics_process(false)
	if is_instance_valid(_presentation): _presentation.begin_service()

func _auto_still_valid(current) -> bool:
	if not is_instance_valid(_car) or _car.is_queued_for_deletion() or current != _car: return false
	if not session.world.driving.occupied or session.world.gameplay.health <= 0 or _car.health <= 0: return false
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty(): return false
	if absf(float(_car.get("speed"))) > .15: return false
	if session.has_method("is_transition_blocked") and session.is_transition_blocked(): return false
	return true

func _tick_active_auto(delta: float) -> void:
	var remaining := delta
	while remaining > 0.0 and is_instance_valid(_car):
		# AUTO_SECONDS remains the productive admission-to-result contract; the
		# shutter close is part of that interval, while reopening releases controls.
		var duration := .35 if _auto_phase in ["closing","opening"] else AUTO_SECONDS-.35
		var step := minf(remaining,maxf(0.0,duration-_phase_elapsed))
		_phase_elapsed += step
		_elapsed += step
		remaining -= step
		if _phase_elapsed + .0001 < duration: break
		_phase_elapsed = 0.0
		match _auto_phase:
			"closing":
				_auto_phase = "repair"
				if is_instance_valid(_presentation): _presentation.begin_repair()
			"repair":
				if not _commit_auto_service():
					cancel_auto_service("payment_failed")
					return
				_auto_phase = "opening"
				if is_instance_valid(_presentation): _presentation.finish_service()
			"opening":
				_finish_auto_service()
				return
			_:
				return

func _commit_auto_service() -> bool:
	if _auto_committed: return true
	var receipt := "northgate_auto:%d"%(auto_serial+1)
	if not session.state.economy.spend(AUTO_PRICE,receipt): return false
	_auto_committed = true
	auto_serial += 1
	serviced_count += 1
	_car.repair()
	session.world.gameplay.clear_wanted()
	_last_vehicle = _car.vehicle_id
	return true

func _finish_auto_service() -> void:
	var finished := _car
	_release_auto_service()
	if is_instance_valid(finished): _departing = finished
	session.show_message("Veículo reparado.")
	session.save_game()

func cancel_auto_service(_reason := "cancelled") -> void:
	if not is_instance_valid(_car):
		if is_instance_valid(session.world.player):
			session.world.player.remove_meta("pay_n_spray_busy")
			if "input_locked" in session.world.player: session.world.player.input_locked = bool(_auto_saved.get("player_locked",false))
		_car = null
		_auto_phase = "idle"
		_phase_elapsed = 0
		_elapsed = 0
		_auto_saved = {}
		_auto_committed = false
		if is_instance_valid(_presentation): _presentation.cancel_service()
		return
	var committed := _auto_committed
	var interrupted := _car
	_release_auto_service()
	if committed:
		_departing = interrupted
		session.show_message("Veículo reparado.")
		session.save_game()
	if is_instance_valid(_presentation): _presentation.cancel_service()

func _release_auto_service() -> void:
	var released := _car
	if is_instance_valid(released):
		released.remove_meta("pay_n_spray_busy")
		released.collision_layer = int(_auto_saved.get("layer",4))
		released.collision_mask = int(_auto_saved.get("mask",7))
		if "input_locked" in released: released.input_locked = bool(_auto_saved.get("input_locked",false))
		released.velocity = Vector3.ZERO
		if "horizontal_velocity" in released: released.horizontal_velocity = Vector3.ZERO
		if "speed" in released: released.speed = 0.0
		released.set_physics_process(bool(_auto_saved.get("physics",true)))
	if is_instance_valid(session.world.player):
		session.world.player.remove_meta("pay_n_spray_busy")
		if "input_locked" in session.world.player: session.world.player.input_locked = bool(_auto_saved.get("player_locked",false))
	_car = null
	_auto_phase = "idle"
	_phase_elapsed = 0
	_elapsed = 0
	_auto_saved = {}
	_auto_committed = false

func _update_cross() -> void:
	if session.state.place_id != "harbor_hospital" or not is_instance_valid(session.room):
		if is_instance_valid(_cross): _cross.queue_free()
		_cross = null
		_cross_room = null
		return
	if _cross_room != session.room or not is_instance_valid(_cross):
		if is_instance_valid(_cross): _cross.queue_free()
		_cross = Node3D.new()
		_cross.position = HOSPITAL_PICKUP+Vector3.UP*.65
		session.room.add_child(_cross)
		_cross_room = session.room
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("ef647d")
		material.emission_enabled = true
		material.emission = Color("762238")
		for size in [Vector3(.9,.28,.24),Vector3(.28,.9,.24)]:
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = size
			mesh.mesh = box
			mesh.material_override = material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_cross.add_child(mesh)
	_cross.visible = hospital_cooldown<=0

func snapshot() -> Dictionary:
	# Unpaid repairs deliberately restart after loading, never apply halfway.
	return {"version":1,"hospital_cooldown":hospital_cooldown,"auto_serial":auto_serial,"serviced_count":serviced_count,"last_vehicle":_last_vehicle}

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	if is_instance_valid(_car): cancel_auto_service("restore")
	hospital_cooldown = float(data.hospital_cooldown)
	auto_serial = int(data.auto_serial)
	serviced_count = int(data.serviced_count)
	_last_vehicle = str(data.last_vehicle)
	_car = null
	_elapsed = 0
	_heal_accum = 0
	_fire_active = false
	return true

func _exit_tree() -> void:
	if is_instance_valid(_car): _release_auto_service()
	if is_instance_valid(_presentation): _presentation.cancel_service()

static func validate_snapshot(data: Dictionary) -> bool:
	if data.get("version") != 1: return false
	if not data.get("last_vehicle") is String or data.last_vehicle.length()>160: return false
	var cooldown: Variant = data.get("hospital_cooldown")
	if typeof(cooldown) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(cooldown)) or float(cooldown)<0 or float(cooldown)>180: return false
	for key in ["auto_serial","serviced_count"]:
		var value: Variant = data.get(key)
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)<0 or float(value)>10000000 or float(value)!=floorf(float(value)): return false
	return data.auto_serial == data.serviced_count
