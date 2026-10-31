extends Node3D
## O serviço de entrar dirigindo cuida do acesso e da câmera temporária, nunca da identidade do veículo.
const PLACE := "desert_digo"
const KEY := "digo_workshop_drive"
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const PROGRESS := preload("res://systems/campaign/DigoProgress.gd")
const PERF := preload("res://data/catalogs/VehiclePerformance.gd")
var session
var _busy := false
var _camera: Camera3D
var _previous_camera: Camera3D
var _car: CharacterBody3D
var _yaw := .65
var _accepted_yaw := .65
var _zoom := 1.0
var _rotate := false
var _orbit_direction := 1.0
var _rear_inspection := false
var _tail_inspection := false
var _focus := Vector3(0,.65,0)
var _access_poll := 0.0
var _cooldown := 0.0
var _last_notice := ""
var restore_diagnostic: Dictionary = {}
var _service_walls: Array[Dictionary] = []
var _service_shutter: Node3D

func configure(owner_session) -> void:
	session = owner_session
	name = "DigoWorkshopDrive"
	set_process(false)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0,_cooldown-delta)
	_access_poll += delta
	if _access_poll < .1: return
	_access_poll = 0.0
	if session == null or _busy or _cooldown > 0 or not session.ready_for_play or session.modal or session.is_transition_blocked(): return
	if session.state.region_id != "desert" or not session.world.driving.occupied or session.desert.busy(): return
	var car := candidate_car()
	if not is_instance_valid(car) or session.world.gameplay.health <= 0 or absf(car.speed) > 2.2: return
	var pedal: Vector2 = GameInput.vehicle_input()
	var intended_z: float = -car.global_basis.z.z*pedal.y
	# The authored doorway faces south. A crossing, never proximity alone, owns admission.
	var entering: bool = session.state.place_id.is_empty()
	var definition := PLACES.get_definition(PLACE)
	var width_extent: float = absf(cos(car.rotation.y))*car.half_width+absf(sin(car.rotation.y))*car.half_length
	var length_extent: float = absf(cos(car.rotation.y))*car.half_length+absf(sin(car.rotation.y))*car.half_width
	var sideways_margin: float = 2.7-width_extent-.2
	if sideways_margin < 0.0: return
	if entering:
		var front_z: float = definition.exterior_position.z+definition.size.y*.5
		var threshold_z: float = front_z+length_extent+.15
		if absf(car.global_position.x-definition.exterior_position.x) > sideways_margin or absf(car.global_position.z-threshold_z) > .3 or (car.horizontal_velocity.z >= -.02 and intended_z >= -.05): return
	else:
		if session.state.place_id != PLACE or not is_instance_valid(session.room): return
		var local: Vector3 = session.room.to_local(car.global_position)
		var threshold_z: float = definition.size.y*.5-length_extent-.25
		if absf(local.x) > sideways_margin or absf(local.z-threshold_z) > .3 or (car.horizontal_velocity.z <= .02 and intended_z <= .05): return
	if absf(sin(car.rotation.y)) > .25: return
	if entering and session.world.gameplay.stars > 0:
		_access_notice("Perca a polícia antes de entrar.")
		return
	if entering and not PROGRESS.workshop_unlocked(session.state.world_state):
		_access_notice("Complete a corrida com Digo para liberar a oficina.")
		return
	_last_notice = ""
	_busy = true
	_transfer.call_deferred(car,entering)

func _access_notice(message: String) -> void:
	if _last_notice == message: return
	_last_notice = message
	session.show_message(message)

func candidate_car() -> CharacterBody3D:
	if session == null: return null
	var car: CharacterBody3D = session.world.driving.car
	if not is_instance_valid(car) or car.health <= 0 or car.engine_disabled or car.external_input: return null
	if not PERF.eligible(str(car.archetype)) or car.half_width > 1.45 or car.half_length > 3.1: return null
	# Estes carros têm outro dono de história/residência e não podem ser realocados pelo serviço.
	if car.get_meta("residence_vehicle",false) or car.vehicle_id in ["story_tow_vehicle","neco_tow_truck","jessica_jetta_gli"]: return null
	return car

func nearest_action() -> Dictionary:
	if session == null or _busy or not session.ready_for_play or session.modal or session.is_transition_blocked(): return {}
	if session.state.region_id != "desert" or session.world.gameplay.health <= 0 or not session.world.driving.occupied: return {}
	if session.desert.busy(): return {}
	var car: CharacterBody3D = session.world.driving.car
	if not is_instance_valid(car) or car.health <= 0 or absf(car.speed) > .5: return {}
	var definition := PLACES.get_definition(PLACE)
	if session.state.place_id == PLACE and is_instance_valid(session.room):
		var exit: Vector3 = session.room.to_global(definition.vehicle_exit)
		if car.global_position.distance_to(exit) < 2.3: return _action("digo_drive_exit","Sair da oficina",exit)
		return _action("digo_drive_service","Preparar carro",car.global_position)
	if not session.state.place_id.is_empty(): return {}
	var entry: Vector3 = definition.vehicle_return
	if car.global_position.distance_to(entry) > 5.0: return {}
	return _action("digo_drive_enter","Entrar na oficina",entry)

func _action(target: String, label: String, point: Vector3) -> Dictionary:
	return {"id":"desert","target":target,"label":label,"position":point}

func perform(target: String) -> bool:
	if nearest_action().get("target","") != target: return false
	if target == "digo_drive_service":
		_open_service()
		return true
	if target not in ["digo_drive_enter","digo_drive_exit"]: return false
	var entering := target == "digo_drive_enter"
	if entering and session.world.gameplay.stars > 0:
		session.show_message("Perca a polícia antes de entrar.")
		return false
	if entering and not PROGRESS.workshop_unlocked(session.state.world_state):
		session.show_message("Complete a corrida com Digo para liberar a oficina.")
		return false
	var car := candidate_car()
	if not is_instance_valid(car):
		var selected: CharacterBody3D = session.world.driving.car
		var reason := "Este veículo não cabe na baia ou não tem preparação disponível."
		if is_instance_valid(selected):
			if selected.get_meta("residence_vehicle",false): reason = "Este carro está vinculado à residência. Estacione e fale com Digo a pé."
			elif selected.vehicle_id == "jessica_jetta_gli": reason = "Estacione o carro da Jessica e fale com Digo a pé."
			elif selected.external_input or selected.vehicle_id in ["story_tow_vehicle","neco_tow_truck"]: reason = "Termine a atividade deste veículo antes de usar a oficina."
		session.show_message(reason)
		return false
	_busy = true
	_transfer.call_deferred(car,entering)
	return true

func _transfer(car: CharacterBody3D, entering: bool) -> void:
	close_service_view()
	# Reaproveita a cortina existente; nenhum carro, controlador ou câmera é clonado para a admissão.
	var success: bool = await session.transfer_garage_vehicle(PLACE,car,entering)
	session._set_digo_vehicle_gate(false)
	if success:
		car.set_meta("garage_origin",session.room.global_position if entering else Vector3.ZERO)
		# O GarageRewards continua o único dono dos veículos de garagem conquistados.
		if car.get_meta("garage_reward",false):
			session.garage_rewards._capture_all()
			session.garage_rewards.on_location_changed()
		write_snapshot()
	_cooldown = 1.2
	await session.door_transition.fade_to(0.0,.24)
	_busy = false
	if success:
		session.save_game()
		if entering: _open_service()

func _open_service() -> void:
	var car := candidate_car()
	if not is_instance_valid(car) or session.state.place_id != PLACE: return
	session.desert._workshop_site = "town"
	session.desert.tuning_car = car
	session._menu("Digo")
	session.desert._open_tuning()

func write_snapshot() -> void:
	if session == null: return
	var car: CharacterBody3D = session.world.driving.car
	if session.state.place_id != PLACE or not is_instance_valid(car) or car.get_meta("garage_place","") != PLACE:
		session.state.world_state.erase(KEY)
		return
	# Só os metadados de acesso vivem aqui; o corpo fica com o dono existente.
	session.state.world_state[KEY] = {"version":1,"vehicle_id":car.vehicle_id,"garage_owned":bool(car.get_meta("garage_reward",false)),"was_driven":session.world.driving.occupied}

static func valid(value: Variant) -> bool:
	return value is Dictionary and value.get("version") == 1 and value.get("vehicle_id") is String and not value.vehicle_id.is_empty() and value.vehicle_id.length() <= 128 and value.get("garage_owned") is bool and value.get("was_driven") is bool

static func valid_world(world: Dictionary) -> bool:
	if not world.has(KEY): return true
	var value: Variant = world[KEY]
	if not valid(value): return false
	if value.garage_owned:
		var rewards: Variant = world.get("garage_rewards",{})
		if not rewards is Dictionary or not rewards.get("vehicles",{}) is Dictionary: return false
		var record: Variant = rewards.vehicles.get(value.vehicle_id,{})
		return record is Dictionary and record.get("region_id","") == "desert" and record.get("place_id","") == PLACE and record.get("was_driven") == value.was_driven
	var records: Variant = world.get("vehicles",[])
	if not records is Array: return false
	for record in records:
		if not record is Dictionary or record.get("vehicle_id","") != value.vehicle_id: continue
		if not preload("res://runtime/FleetState.gd").validate(record): return false
		if record.get("region","") != "desert" or record.get("was_driven") != value.was_driven: return false
		# Os interiores nativos são instanciados em z=-2400; registros de rua sem relação
		# nunca podem ser interpretados como a posição de um motorista no interior.
		return absf(float(record.position[0])) <= 11.0 and absf(float(record.position[2])+2400.0) <= 8.0
	return false

func restore_saved_driver() -> bool:
	if session.state.place_id != PLACE: return true
	restore_diagnostic = {"stage":"requested","place":session.state.place_id}
	var saved: Dictionary = session.state.world_state.get(KEY,{})
	if saved.is_empty(): return true
	if not valid(saved): restore_diagnostic["stage"] = "invalid_metadata"; return false
	if saved.garage_owned:
		# O on_location_changed normal dele restaura este dono depois de ready_for_play.
		return session.garage_rewards.data.vehicles.has(saved.vehicle_id)
	var record: Dictionary = session.controller.starting_vehicle()
	var car: CharacterBody3D = session.world.driving.car
	if record.get("vehicle_id","") != saved.vehicle_id or not is_instance_valid(car) or car.vehicle_id != saved.vehicle_id:
		restore_diagnostic["stage"] = "identity_mismatch"
		return false
	var point := Vector3(record.position[0],record.position[1],record.position[2])
	restore_diagnostic.merge({"stage":"physics_admission","point":str(point),"yaw":float(record.yaw),"vehicle_id":car.vehicle_id},true)
	for frame in 3: await get_tree().physics_frame
	if not is_instance_valid(session.room): restore_diagnostic["stage"] = "room_missing"; return false
	if not session.controller.vehicle_position_clear(car,point,float(record.yaw)):
		restore_diagnostic["stage"] = "hull_or_support_rejected"
		return false
	car.place(point,float(record.yaw))
	car.set_meta("garage_place",PLACE)
	car.set_meta("garage_origin",session.room.global_position)
	car.remove_meta("awaiting_ground")
	car.show()
	car.set_physics_process(true)
	var tuning: Dictionary = preload("res://runtime/desert/DesertGarageState.gd").vehicle(session.state.world_state,car.vehicle_id,car.archetype)
	preload("res://gameplay/desert_cars/DesertCarAdapter.gd").attach(car,tuning.parts)
	if not saved.was_driven: return true
	session._restoring_saved_driver = true
	restore_diagnostic["stage"] = "driver_boarding"
	var restored: bool = await session.restore_garage_driver(car)
	session._restoring_saved_driver = false
	restore_diagnostic.merge({"stage":"driver_result","restored":restored,"occupied":session.world.driving.occupied,"player_position":str(session.world.player.global_position),"car_position":str(car.global_position)},true)
	return restored

func service_admission_reason(car: CharacterBody3D) -> String:
	if not is_instance_valid(car) or not is_instance_valid(session.room): return "A baia da oficina está indisponível."
	var local: Vector3 = session.room.to_local(car.global_position)
	if Vector2(local.x,local.z).length() > 1.2 or absf(angle_difference(car.rotation.y,PI)) > .25:
		return "Alinhe o carro na baia, voltado para a saída."
	var query := PhysicsShapeQueryParameters3D.new()
	var volume := BoxShape3D.new()
	volume.size = Vector3(5.4,4.6,.2)
	query.shape = volume
	query.transform = session.room.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,2.3,8.9))
	query.collision_mask = 6
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
		return "Libere a passagem da garagem antes de preparar o carro."
	return ""

func open_service_view(car: CharacterBody3D) -> bool:
	var denied := service_admission_reason(car)
	if not denied.is_empty():
		session.show_message(denied)
		return false
	if is_instance_valid(_car) and _car != car: _set_tail_preview(_car,false)
	if not is_instance_valid(_camera):
		_previous_camera = get_viewport().get_camera_3d()
		_camera = Camera3D.new()
		_camera.name = "DigoServiceCamera"
		_camera.fov = 30.0
		_camera.near = .1
		_camera.far = 80.0
		add_child(_camera)
	_car = car
	_set_tail_preview(_car,_tail_inspection)
	_close_service_room()
	_camera.make_current()
	_update_camera()
	set_process(true)
	return true

func close_service_view() -> void:
	set_process(false)
	_open_service_room()
	_set_tail_preview(_car,false)
	_tail_inspection = false
	_car = null
	_rotate = false
	if is_instance_valid(_camera):
		if is_instance_valid(_previous_camera): _previous_camera.make_current()
		_camera.queue_free()
	_camera = null
	_previous_camera = null

func focus_slot(slot: String) -> void:
	_focus = Vector3(0,.65,0)
	_rear_inspection = slot in ["spoiler","taillights","diffuser"]
	_tail_inspection = slot == "taillights"
	_set_tail_preview(_car,_tail_inspection)
	match slot:
		"spoiler": _focus = Vector3(0,.8,0); _yaw = -.65
		"sunroof", "roof": _focus = Vector3(0,.65,0); _yaw = .65
		"headlights", "taillights", "lamp_color": _focus = Vector3(0,.65,0); _yaw = .35
		"wheels", "wheel_size", "wheel_model", "rims": _focus = Vector3(0,.65,0); _yaw = .95
		"skirts": _focus = Vector3(0,.45,0); _yaw = .95
		"front_lip": _focus = Vector3(0,.4,0); _yaw = .25
		"diffuser": _yaw = -.65
	if _rear_inspection: _focus.y = .1
	_update_camera()

func camera_action(action: String, value: float) -> void:
	match action:
		"rotate": _rotate = value > .5
		"zoom":
			var previous_zoom := _zoom
			_zoom = clampf(_zoom+value,.9,1.12)
			if not _update_camera(false): _zoom = previous_zoom
			return
		"reset": _yaw = .65; _zoom = 1.0; _focus = Vector3(0,.65,0); _rotate = false; _rear_inspection = false
	_update_camera()

func orbit_by(delta: Vector2) -> void:
	var previous_yaw := _yaw
	_yaw = clampf(_yaw-delta.x*PI,-.95,.95)
	_rotate = false
	if not _update_camera(false): _yaw = previous_yaw

func _process(delta: float) -> void:
	if not is_instance_valid(_car) or session.state.place_id != PLACE:
		close_service_view()
		return
	if _rotate:
		var previous_yaw := _yaw
		_yaw += delta*.18*_orbit_direction
		if _yaw >= .95: _yaw = .95; _orbit_direction = -1.0
		elif _yaw <= -.95: _yaw = -.95; _orbit_direction = 1.0
		var attempted_yaw := _yaw
		if not _update_camera(false):
			_yaw = previous_yaw
			_orbit_direction = -signf(attempted_yaw-previous_yaw) if not is_equal_approx(attempted_yaw,previous_yaw) else -_orbit_direction

func _update_camera(allow_fallback := true) -> bool:
	if not is_instance_valid(_camera) or not is_instance_valid(_car): return false
	var accepted_transform := _camera.global_transform
	var accepted_fov := _camera.fov
	var accepted_h_offset := _camera.h_offset
	var accepted_v_offset := _camera.v_offset
	var distance: float = clampf(8.6/_zoom,8.0,9.2)
	var target: Vector3 = _car.global_position+Vector3(0,_focus.y,0)
	# Estacionar de frente para o sul mantém o elevador atrás do carro inteiro e a parede
	# norte atrás do objeto. A órbita fica na metade fisicamente livre da baia.
	var candidates: Array[float] = [clampf(_yaw,-.95,.95)]
	if allow_fallback: candidates.append_array([.45,-.45,0.0])
	for angle in candidates:
		var desired: Vector3 = _car.global_position+Vector3(sin(angle)*distance,4.1,cos(angle)*distance)
		if _rear_inspection:
			# As colunas do elevador ficam em x=+-2.1,z=-3.5. A inspeção traseira fica
			# dentro do corredor central delas; o cone de visão inteiro é checado abaixo.
			desired = _car.global_position+Vector3(sin(angle)*.6,3.0,-clampf(6.8/_zoom,6.2,7.4))
		if is_instance_valid(session.room):
			var local: Vector3 = session.room.to_local(desired)
			local.x = clampf(local.x,-1.25,1.25) if _rear_inspection else clampf(local.x,-9.0,9.0)
			local.z = clampf(local.z,-7.5,-5.5) if _rear_inspection else clampf(local.z,2.5,7.5)
			desired = session.room.to_global(local)
		if not _camera_corridor_clear(target,desired) or not _car_visible_from(desired): continue
		_camera.global_position = desired
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		_camera.fov = 42.0 if _rear_inspection else 30.0
		_camera.look_at(target,Vector3.UP)
		# A composição desloca o ponto de mira, nunca a câmera física depois da colisão.
		var composition_offset: float = 1.3 if _rear_inspection else 1.8
		var composition: Vector3 = target-_camera.global_basis.x*composition_offset
		_camera.look_at(composition,Vector3.UP)
		if not _fit_car_in_preview(42.0 if _rear_inspection else 30.0): continue
		_yaw = angle
		_accepted_yaw = angle
		return true
	# Candidatos recusados nunca viram a vista apresentada. Em particular, o
	# recurso final de ângulo zero não pode vazar a pose falha de 50 graus.
	_camera.global_transform = accepted_transform
	_camera.fov = accepted_fov
	_camera.h_offset = accepted_h_offset
	_camera.v_offset = accepted_v_offset
	_yaw = _accepted_yaw
	return false

func _fit_car_in_preview(minimum_fov: float) -> bool:
	# A câmera da cena serve uma prévia ao lado de uma barra lateral e acima de um rodapé.
	# Encaixa o volume inteiro em toda pose de órbita em vez de confiar no raio central.
	# A vista traseira fica presa entre as colunas do elevador: perua e minivan (~5,5 m) só
	# cabem abrindo até 60°; sem isso a câmera ficava na frente ao olhar aerofólio/difusor.
	for angle in range(int(minimum_fov),61 if _rear_inspection else 51,2):
		_camera.fov = float(angle)
		if car_fits_preview(): return true
	return false

func car_fits_preview() -> bool:
	if not is_instance_valid(_camera) or not is_instance_valid(_car): return false
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var scale_y: float = viewport_size.y/720.0
	var allowed := Rect2(Vector2(viewport_size.x*.28+10.0,76.0*scale_y),Vector2(viewport_size.x*.72-22.0,viewport_size.y-186.0*scale_y))
	for x in [-1.0,1.0]:
		for z in [-1.0,1.0]:
			for height in [-.04,float(_car.body_height)+.25]:
				var point: Vector3 = _car.global_position+_car.global_basis*Vector3(x*(_car.half_width+.08),height,z*(_car.half_length+.12))
				if _camera.is_position_behind(point) or not allowed.has_point(_camera.unproject_position(point)): return false
	return true

func _camera_corridor_clear(target: Vector3, desired: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = .22
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY,target)
	query.motion = desired-target
	query.collision_mask = 1
	query.exclude = [_car.get_rid()]
	var sweep: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	return sweep.size() == 2 and is_equal_approx(sweep[0],1.0)

func _car_visible_from(origin: Vector3) -> bool:
	for x in [-1.0,1.0]:
		for z in [-1.0,1.0]:
			for height in [.12,float(_car.body_height)]:
				var point: Vector3 = _car.global_position+_car.global_basis*Vector3(x*_car.half_width,height,z*_car.half_length)
				var query := PhysicsRayQueryParameters3D.create(origin,point,1)
				query.exclude = [_car.get_rid()]
				if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return false
	return true

func _close_service_room() -> void:
	if not is_instance_valid(session.room) or is_instance_valid(_service_shutter): return
	# O NativePlace corta as paredes da frente já sólidas para a vista normal de
	# cima. Uma câmera de serviço baixa vê a altura total escrita delas enquanto é dona da entrada.
	for mesh in session.room.model.find_children("FrontWall*","MeshInstance3D",true,false):
		if not mesh.mesh is BoxMesh: continue
		_service_walls.append({"node":weakref(mesh),"mesh":mesh.mesh,"position":mesh.position})
		var restored: BoxMesh = mesh.mesh.duplicate()
		restored.size.y = 4.6
		mesh.mesh = restored
		mesh.position.y = 2.3
	_service_shutter = Node3D.new()
	_service_shutter.name = "DigoServiceShutter"
	_service_shutter.position = Vector3(0,2.3,8.9)
	session.room.add_child(_service_shutter)
	var steel: Material = preload("res://world/desert/DigoWorkshopMaterials.gd").material("steel")
	var panel := MeshInstance3D.new()
	panel.name = "RollingShutter"
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(5.4,4.6,.16)
	panel.mesh = panel_mesh
	panel.material_override = steel
	_service_shutter.add_child(panel)
	var ribs := MultiMeshInstance3D.new()
	var rib_mesh := BoxMesh.new()
	rib_mesh.size = Vector3(5.32,.035,.045)
	rib_mesh.material = steel
	var repeated := MultiMesh.new()
	repeated.transform_format = MultiMesh.TRANSFORM_3D
	repeated.mesh = rib_mesh
	repeated.instance_count = 14
	for index in 14: repeated.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(0,-2.1+float(index)*.32,-.105)))
	ribs.multimesh = repeated
	_service_shutter.add_child(ribs)
	var barrier := StaticBody3D.new()
	barrier.name = "Collision"
	barrier.collision_layer = 1
	barrier.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = panel_mesh.size
	shape.shape = box
	barrier.add_child(shape)
	_service_shutter.add_child(barrier)

func _open_service_room() -> void:
	# Solta a abertura física na hora, antes de close_menu devolver o controle.
	if is_instance_valid(_service_shutter):
		var barrier := _service_shutter.get_node_or_null("Collision") as StaticBody3D
		if is_instance_valid(barrier): barrier.collision_layer = 0
		_service_shutter.hide()
		_service_shutter.queue_free()
	_service_shutter = null
	for saved in _service_walls:
		var node: MeshInstance3D = saved.node.get_ref()
		if is_instance_valid(node):
			node.mesh = saved.mesh
			node.position = saved.position
	_service_walls.clear()

func _set_tail_preview(car: CharacterBody3D, enabled: bool) -> void:
	if not is_instance_valid(car) or not is_instance_valid(car.equipment): return
	if car.equipment.has_method("set_tail_lens_preview"): car.equipment.set_tail_lens_preview(enabled)

func _exit_tree() -> void:
	close_service_view()
	if session is Node and is_instance_valid(session) and session.is_inside_tree() and is_instance_valid(session.world):
		session._set_digo_vehicle_gate(false)
