extends RefCounted
## Garagens e oficinas com carro da FullSession: entrar e sair dirigindo (Maciota, garagem do chefe do
## porto, oficina do Digo), o portão de veículo do Digo, a retomada do motorista salvo sentado e o ponto
## de entrada a pé que não cai em cima de um carro guardado; mais o retrato/restauração do estado de uma
## transição de veículo. Separado em 01/11 (Onda 2 de docs/plano-divisao-arquivos-grandes-20261101.md).
## O estado (room, transition_generation, saved_heading...) continua na sessão; cada função antiga virou
## delegação de uma linha (as corrotinas com await), então quem chama por nome não muda.
## `g` fica como Node, e não como o script da FullSession, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem position_clear e
## show_message numa subclasse da sessão e o despacho tem de continuar igual.

const PLACES := preload("res://world/places/PlaceCatalog.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func _vehicle_transition_snapshot(car: CharacterBody3D) -> Dictionary:
	return {
		"generation": g.transition_generation,
		"occupied": g.world.driving.occupied,
		"driving_car": g.world.driving.car,
		"car_locked": car.input_locked,
		"car_controlled": car.controlled,
		"car_external_input": car.external_input,
		"player_locked": g.world.player.input_locked,
		"player_visible": g.world.player.visible,
		"player_physics": g.world.player.is_physics_processing(),
		"player_layer": g.world.player.collision_layer,
		"player_mask": g.world.player.collision_mask,
		"camera_target": g.world.camera.target,
		"camera_offset": g.world.camera.offset,
		"camera_heading": g.world.camera.heading,
		"camera_target_size": g.world.camera.target_size,
		"camera_size": g.world.camera.size,
		"camera_locked": g.world.camera.locked,
	}

func _restore_vehicle_transition_snapshot(snapshot: Dictionary, car: CharacterBody3D) -> void:
	if int(snapshot.generation) != g.transition_generation: return
	# Morte/prisão agora é dona do ator. Solta só a nossa trava provisória do carro;
	# restaurar ocupação, colisão ou câmera antigas reviveria um estado velho.
	if g.world.gameplay.health <= 0 or g.rescue_pending or g.arrest_pending:
		if is_instance_valid(car) and not car.controlled: car.input_locked = bool(snapshot.car_locked)
		return
	if is_instance_valid(car):
		car.input_locked = bool(snapshot.car_locked)
		car.controlled = bool(snapshot.car_controlled)
		car.external_input = bool(snapshot.car_external_input)
	g.world.driving.occupied = bool(snapshot.occupied)
	g.world.driving.car = snapshot.driving_car if is_instance_valid(snapshot.driving_car) else car
	g.world.player.input_locked = bool(snapshot.player_locked)
	g.world.player.visible = bool(snapshot.player_visible)
	g.world.player.set_physics_process(bool(snapshot.player_physics))
	g.world.player.collision_layer = int(snapshot.player_layer)
	g.world.player.collision_mask = int(snapshot.player_mask)
	if is_instance_valid(snapshot.camera_target): g.world.camera.target = snapshot.camera_target
	g.world.camera.offset = snapshot.camera_offset
	g.world.camera.heading = float(snapshot.camera_heading)
	g.world.camera.target_size = float(snapshot.camera_target_size)
	g.world.camera.size = float(snapshot.camera_size)
	g.world.camera.locked = bool(snapshot.camera_locked)
	g.world.camera.initialized = false

func restore_transition_player_lock(previous: bool, token: int) -> void:
	if token != g.transition_generation or g.world.gameplay.health <= 0 or g.rescue_pending or g.arrest_pending: return
	g.world.player.input_locked = previous

func _discard_place_candidate(candidate: Node3D, owned: bool) -> void:
	if not is_instance_valid(candidate): return
	if g.building_entrance != null and candidate == g.building_entrance.staged: g.building_entrance.departed(candidate)
	if candidate == g.world.maciota_place: candidate.set_interior_active(false)
	elif owned: candidate.queue_free()

func _garage_transfer_valid(token: int, car: CharacterBody3D, place_id: String, entering: bool, expected_room: Node3D) -> bool:
	if not g.owns_transition(token) or not is_instance_valid(car) or car.health <= 0 or g.world.gameplay.health <= 0: return false
	if not g.world.driving.occupied or g.world.driving.car != car or g.room != expected_room: return false
	if car.get("engine_disabled") == true: return false
	if entering and not preload("res://runtime/ShopSafety.gd").admission_allowed(place_id,g.world.gameplay.stars): return false
	if entering and place_id == "desert_digo" and not preload("res://systems/campaign/DigoProgress.gd").workshop_unlocked(g.state.world_state): return false
	return g.state.place_id.is_empty() if entering else g.state.place_id == place_id

func transfer_garage_vehicle(place_id: String, car: CharacterBody3D, entering: bool) -> bool:
	var access_speed := 2.2 if place_id == "desert_digo" else .5
	if g.is_transition_blocked() or not is_instance_valid(car) or car.health<=0 or absf(car.speed)>access_speed: return false
	if not g.world.driving.occupied or g.world.driving.car != car: return false
	if entering and (not g.state.place_id.is_empty() or is_instance_valid(g.room)): return false
	if not entering and g.state.place_id != place_id: return false
	if entering and not preload("res://runtime/ShopSafety.gd").admission_allowed(place_id,g.world.gameplay.stars): return false
	if entering and place_id == "desert_digo" and not preload("res://systems/campaign/DigoProgress.gd").workshop_unlocked(g.state.world_state): return false
	var definition: Dictionary = PLACES.get_definition(place_id)
	if place_id == "maciota":
		if g.state.region_id != "harbor": return false
	elif definition.is_empty() or definition.get("region","") != g.state.region_id or not definition.has("vehicle_spawn"):
		return false
	var token: int = g.begin_transition("garage_vehicle",true)
	if token < 0: return false
	var snapshot: Dictionary = g._vehicle_transition_snapshot(car)
	var expected_room: Node3D = g.room
	car.input_locked = true
	g.world.player.input_locked = true
	car.speed = 0
	car.horizontal_velocity = Vector3.ZERO
	if place_id == "desert_digo": await g.door_transition.fade_to(1.0,.18)
	if place_id == "desert_digo" and not g._set_digo_vehicle_gate(true,token,car):
		g._restore_vehicle_transition_snapshot(snapshot,car)
		g.finish_transition(token)
		g.show_message("Aguarde o portão da oficina ficar disponível.")
		return false
	var destination: Vector3
	var yaw := 0.0
	var next_room: Node3D = null
	var owns_next_room := false
	if entering:
		if place_id == "maciota":
			next_room = g.world.maciota_place
			next_room.set_interior_active(true)
			destination = next_room.interior_origin+Vector3(0,.1,1)
		else:
			next_room = PLACES.create_place(place_id)
			if next_room == null:
				if place_id == "desert_digo": g._set_digo_vehicle_gate(false)
				g._restore_vehicle_transition_snapshot(snapshot,car)
				g.finish_transition(token)
				return false
			owns_next_room = true
			next_room.position = Vector3(0,0,-2400)
			g.world.add_child(next_room)
			destination = next_room.to_global(definition.vehicle_spawn)+Vector3.UP*.08
			yaw = float(definition.get("vehicle_spawn_yaw",0.0))
	else:
		destination = g.world.maciota_place.exterior_vehicle_return+Vector3.UP*.1 if place_id == "maciota" else definition.vehicle_return+Vector3.UP*.08
		yaw = g.world.maciota_place.exterior_vehicle_yaw if place_id == "maciota" else float(definition.get("vehicle_return_yaw",0))
		g.controller.region.set_focus(destination)
	for i in 3:
		await g.get_tree().physics_frame
		if not g._garage_transfer_valid(token,car,place_id,entering,expected_room):
			if place_id == "desert_digo": g._set_digo_vehicle_gate(false)
			g._discard_place_candidate(next_room,owns_next_room)
			g.controller.region.set_focus(car.global_position if is_instance_valid(car) else g.world.player.global_position)
			g._restore_vehicle_transition_snapshot(snapshot,car)
			g.finish_transition(token)
			return false
	if not g.controller.vehicle_position_clear(car,destination,yaw):
		if place_id == "desert_digo": g._set_digo_vehicle_gate(false)
		g._discard_place_candidate(next_room,owns_next_room)
		g.controller.region.set_focus(car.global_position)
		g._restore_vehicle_transition_snapshot(snapshot,car)
		g.finish_transition(token)
		g.show_message("Passagem do veículo ocupada. Aguarde espaço livre.")
		return false
	if entering:
		g.saved_heading = g.world.camera.heading
		g.saved_size = g.world.camera.target_size
		g.room = next_room
		g.return_point = g.room.exterior_return if place_id == "maciota" else definition.return_position
		g.state.set_location(g.state.region_id,place_id)
		g.state.checkpoint_id = place_id
		g.anchor.position = g.room.camera_target
		g.world.camera.target = g.anchor
		g.world.camera.offset = Vector3(0,18,15)
		g.world.camera.heading = 0
		g.world.camera.target_size = g.room.camera_size
		g.world.camera.size = g.room.camera_size
		g.world.camera.locked = true
	else:
		g._clear_service_npcs()
		if g.room == g.world.maciota_place: g.room.set_interior_active(false)
		else: g.room.queue_free()
		g.room = null
		g.state.set_location(g.state.region_id)
		g.world.camera.target = car
		g.world.camera.offset = g.world.camera.EXTERIOR_OFFSET
		g.world.camera.heading = g.saved_heading
		g.world.camera.target_size = g.saved_size
		g.world.camera.locked = false
	car.set_meta("garage_place",place_id if entering else "")
	car.set_meta("region_id",g.state.region_id)
	car.place(destination,yaw)
	g.world.player.teleport(destination)
	# Actor.teleport solta a pose sentada; esta transferência mantém o mesmo motorista.
	if car.has_method("shows_seated_driver") and car.shows_seated_driver():
		preload("res://gameplay/VehicleInterior.gd").attach(car)
		preload("res://gameplay/VehicleInterior.gd").seat_driver(g.world.player,car,0.0)
	g.sync_location_presentation()
	g.world.camera.initialized = false
	g.world.camera._process(1)
	if place_id == "desert_digo": g._set_digo_vehicle_gate(false)
	car.input_locked = bool(snapshot.car_locked)
	g.world.player.input_locked = bool(snapshot.player_locked)
	g.finish_transition(token)
	if entering and place_id != "maciota": g._install_service_npc()
	g.arrival.on_location_changed()
	g.refresh_routine_context()
	g.sync_dispatch_location()
	return true

func _set_digo_vehicle_gate(opened: bool, token := -1, car: CharacterBody3D = null) -> bool:
	var from_inside: bool = g.state.place_id == "desert_digo"
	var authorize := func() -> bool:
		if not is_instance_valid(car) or not g.owns_transition(token) or g.transition_kind != "garage_vehicle" or not car.input_locked or not g.world.player.input_locked or not g.world.driving.occupied or g.world.driving.car != car or g.state.region_id != "desert" or car.health <= 0 or g.world.gameplay.health <= 0: return false
		if from_inside: return g.state.place_id == "desert_digo" and is_instance_valid(g.room)
		return g.state.place_id.is_empty() and preload("res://runtime/ShopSafety.gd").admission_allowed("desert_digo",g.world.gameplay.stars) and preload("res://systems/campaign/DigoProgress.gd").workshop_unlocked(g.state.world_state)
	var changed := false
	var groups: Array = ["digo_interior_vehicle_gate" if from_inside else "digo_vehicle_gate"] if opened else ["digo_vehicle_gate","digo_interior_vehicle_gate"]
	for group in groups:
		for gate in g.get_tree().get_nodes_in_group(group):
			if g.world.is_ancestor_of(gate) and gate.has_method("set_vehicle_access"):
				changed = bool(gate.set_vehicle_access(opened,authorize)) or changed
	return changed

func restore_garage_driver(car: CharacterBody3D) -> bool:
	if g.is_transition_blocked() or not is_instance_valid(car) or car.health<=0 or g.world.driving.occupied: return false
	var place: String = g.state.place_id
	if place not in ["","maciota","port_boss_garage","desert_digo"] or car.get_meta("garage_place","") != place: return false
	if car.get_meta("region_id",g.state.region_id) != g.state.region_id or car.get("engine_disabled") == true: return false
	if place == "maciota" and g.state.region_id != "harbor": return false
	var definition := PLACES.get_definition(place)
	if not place.is_empty() and place != "maciota" and (definition.is_empty() or definition.get("region","") != g.state.region_id): return false
	var token: int = g.begin_transition("restore_garage_driver",true)
	if token < 0: return false
	var snapshot: Dictionary = g._vehicle_transition_snapshot(car)
	var expected_room: Node3D = g.room
	car.input_locked = true
	for i in 3:
		await g.get_tree().physics_frame
		if not g.owns_transition(token) or not is_instance_valid(car) or g.state.place_id != place or g.room != expected_room or g.world.driving.occupied or g.modal or g.world.gameplay.health <= 0:
			g._restore_vehicle_transition_snapshot(snapshot,car)
			g.finish_transition(token)
			return false
	if car.health<=0 or not car.is_visible_in_tree() or car.collision_layer == 0 or not g.controller.vehicle_position_clear(car,car.position,car.rotation.y):
		g._restore_vehicle_transition_snapshot(snapshot,car)
		g.finish_transition(token)
		return false
	var checkpoint: Vector3 = g.world.player.position
	var previous_car: CharacterBody3D = g.world.driving.car
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.7
	for side in [-1,1]:
		var point := car.to_global(Vector3(side*(car.half_width+.65),.05,.15))
		# Cabines longas ficam além do alcance da âncora genérica ao lado do carro.
		if car.boarding_class() in ["truck", "bus"]:
			point = car.driver_door_anchor(side) + car.global_basis.x * float(side) * .11 + Vector3.UP * .01
		if not g.position_clear(point): continue
		# Restoring a seated save may relocate the actor to a door only through
		# a continuous clear walking corridor, never across a car or furniture.
		var paths: Array[PackedVector3Array] = [PackedVector3Array([point])]
		var routed: PackedVector3Array = g.world.gameplay.find_path(checkpoint,point)
		if not routed.is_empty():
			routed.append(point)
			paths.append(routed)
		var reachable := false
		for path in paths:
			var from := checkpoint
			var clear := true
			for destination in path:
				if not g.position_clear(destination): clear = false; break
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.collision_mask = 7
				query.exclude = [g.world.player.get_rid()]
				query.transform = Transform3D(Basis.IDENTITY,from+Vector3.UP*.9)
				query.motion = destination-from
				var sweep: PackedFloat32Array = g.world.get_world_3d().direct_space_state.cast_motion(query)
				if sweep[0] < 1.0: clear = false; break
				var steps := maxi(1,ceili(from.distance_to(destination)/.5))
				for step in range(1,steps):
					if not g.position_clear(from.lerp(destination,float(step)/steps)): clear = false; break
				if not clear: break
				from = destination
			if clear: reachable = true; break
		if not reachable: continue
		g.world.player.teleport(point)
		var entry: Dictionary = g.world.driving._entry_option(true)
		# Driving.car ainda nomeia o veículo controlado anterior até a entrada
		# começar de fato. Valida o candidato escolhido fisicamente em vez disso.
		if entry.get("car") == car and g.world.driving.interact(true):
			g.world.camera.target = car if place.is_empty() else g.anchor
			g.world.camera.locked = not place.is_empty()
			g.state.set_location(g.state.region_id,place)
			g.sync_location_presentation()
			# Solta só a trava da sessão enquanto a apresentação existente de corpo/porta
			# é dona da entrada. Senão o Driving vê a nossa trava como interrupção e aborta
			# a entrada no primeiro quadro.
			g.finish_transition(token)
			for frame in 180:
				if not g.world.driving.is_body_transition_active(): break
				await g.get_tree().physics_frame
				if not is_instance_valid(car) or car.health <= 0 or g.state.place_id != place or g.room != expected_room or g.world.gameplay.health <= 0:
					g.world.driving.cancel_transition("garage_restore_invalidated")
					g._restore_vehicle_transition_snapshot(snapshot,car if is_instance_valid(car) else null)
					return false
			if g.world.driving.is_body_transition_active():
				g.world.driving.cancel_transition("garage_restore_timeout")
				g._restore_vehicle_transition_snapshot(snapshot,car)
				return false
			if not g.world.driving.occupied or g.world.driving.car != car:
				g._restore_vehicle_transition_snapshot(snapshot,car)
				return false
			car.input_locked = bool(snapshot.car_locked)
			return true
		g.world.player.teleport(checkpoint)
	g.world.player.teleport(checkpoint)
	g.world.driving.car = previous_car
	g._restore_vehicle_transition_snapshot(snapshot,car)
	g.finish_transition(token)
	return false

func _garage_restore_spawn(place: String, preferred: Vector3, candidate_room: Node3D = null) -> Vector3:
	if place not in ["maciota","port_boss_garage"] or g.garage_rewards == null: return preferred
	if candidate_room == null: candidate_room = g.room
	if not is_instance_valid(candidate_room): return Vector3.INF
	var records: Dictionary = g.garage_rewards.data.get("vehicles",{})
	if records.is_empty(): return preferred
	var origin: Vector3 = candidate_room.to_global(candidate_room.interior_origin) if place == "maciota" else candidate_room.global_position
	var reservations: Array[Dictionary] = []
	for record in records.values():
		if record.get("place_id","") != place or record.get("region_id","") != g.state.region_id: continue
		var specification: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(str(record.archetype))
		if specification.is_empty(): continue
		var size: Array = specification.bounds_size
		var point := origin+Vector3(record.position[0],record.position[1],record.position[2])
		reservations.append({"point":point,"inverse":Basis(Vector3.UP,float(record.yaw)).inverse(),"half":Vector2(maxf(.65,size[0])*.5+.4,float(size[2])*.5+.4),"height":clampf(size[1],1.1,3.6)})
	if reservations.is_empty(): return preferred
	var candidates: Array[Vector3] = [preferred,candidate_room.exit_position]
	for center: Vector3 in [candidate_room.exit_position,preferred]:
		for radius in [1.2,2.4,3.6]:
			for offset in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]: candidates.append(center+offset*radius)
	var bounds: Rect2
	if place == "maciota":
		bounds = Rect2(candidate_room.room_bounds.position.x,candidate_room.room_bounds.position.z,candidate_room.room_bounds.size.x,candidate_room.room_bounds.size.z)
	else:
		var size: Vector2 = candidate_room.definition.size
		bounds = Rect2(-size*.5,size)
	for candidate in candidates:
		var local := candidate-origin
		if not bounds.grow(-.34).has_point(Vector2(local.x,local.z)): continue
		if not g.position_clear(candidate+Vector3.UP*.04): continue
		var reserved := false
		for reservation in reservations:
			var relative: Vector3 = reservation.inverse*(candidate-reservation.point)
			if absf(relative.x) <= reservation.half.x and absf(relative.z) <= reservation.half.y and relative.y < reservation.height and relative.y+1.8 > 0:
				reserved = true
				break
		if not reserved: return candidate
	return Vector3.INF
