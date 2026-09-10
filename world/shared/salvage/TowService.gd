extends Node
## Mantém veículo, carga e encomenda no mesmo mundo e no save da campanha.
const JOBS := preload("res://world/shared/salvage/TowJobs.gd")
const FACTORY := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
var yard: Node2D
var truck: Node2D
var cargo: Node2D
var payload: Node3D
var hint: Label
var _restored := false
var _cargo_layers := Vector2i.ZERO
var _cargo_mode := Node.PROCESS_MODE_INHERIT
var _cargo_physics := false
var _cargo_idle := false
var _previous_health := 0
var _load_tween: Tween
var _offer: Node2D

func _ready() -> void:
	yard = get_parent()
	add_to_group("salvage_tow_service")
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-270,-115)
	hint.size = Vector2(540,60)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size",18)
	hint.add_theme_constant_override("outline_size",6)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	yard._hud.add_child(hint)
	hint.hide()

func _process(_delta: float) -> void:
	hint.hide()
	if not yard._active_world() or not is_instance_valid(yard._player): return
	if not _restored:
		_restore()
	if not is_instance_valid(truck): return
	if is_instance_valid(cargo):
		# A carga cabe no casco do caminhão: a física do guincho resolve as colisões.
		cargo.global_position = truck.global_position
		cargo.global_rotation = truck.global_rotation
		if truck.health < _previous_health:
			cargo.health = maxi(0, int(cargo.health) - (_previous_health-int(truck.health)))
		_previous_health = int(truck.health)
		if truck.health <= 0 or cargo.health <= 0 or yard._player.is_dead or yard._player.is_arrested:
			yard.ledger().fail_contract("interrupted")
			if not unload(): _discard_cargo()
		if is_instance_valid(payload) and is_instance_valid(_load_tween) and _load_tween.is_running():
			truck.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if truck.is_driven_by_player and not yard._player.is_in_dialogue:
		var key: String = get_node("/root/GameInput").hint("interact").get_slice(" / ",0)
		hint.show()
		if is_instance_valid(cargo):
			hint.text = yard._text("%s • Parar e descarregar | Leve à baia do Neco", "%s • Stop and unload | Return to Neco's bay") % key
		else:
			hint.text = yard._text("%s • Guinchar | Pare com a traseira perto de um carro vazio", "%s • Winch | Stop with the rear near an empty car") % key
	snapshot()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo(): return
	if not yard._active_world() or not is_instance_valid(truck) or not truck.is_driven_by_player: return
	if truck.has_meta("vehicle_boarding"): return
	if yard._player.is_dead or yard._player.is_in_dialogue: return
	get_viewport().set_input_as_handled()
	if truck.velocity.length() > 8:
		_notice("Pare o guincho primeiro.", "Stop the tow truck first.")
	elif is_instance_valid(cargo):
		if not unload(): _notice("Sem espaço para descarregar. Alinhe a traseira com a baia ou uma área livre.", "No unloading space. Align the rear with the bay or a clear area.")
	else:
		var target := nearby_car()
		if target == null or not attach(target):
			_notice("Aproxime a traseira de um carro vazio e parado.", "Move the rear closer to an empty, stationary car.")

func _restore() -> void:
	_restored = true
	var saved: Dictionary = yard.ledger().data.get("tow_vehicle",{})
	for car in get_tree().get_nodes_in_group("vehicle"):
		if String(car.name) == "NecoTowTruck" and String(car.get("vehicle_id")) == "towmaster":
			truck = car
			break
	if not is_instance_valid(truck):
		var point: Vector2 = yard.to_global(Vector2(155,440))
		if saved.has("position") and bool(saved.get("legacy",false)) == yard.legacy:
			point = Vector2(saved.position[0],saved.position[1])
		truck = FACTORY.spawn_parked_vehicle(yard.get_parent(),"NecoTowTruck",yard.get_parent().to_local(point),float(saved.get("rotation",PI)),"towmaster",0)
		truck.health = int(saved.get("health",220))
	truck.add_to_group("mission_vehicle") # A ferramenta de trabalho nunca vai para a prensa.
	truck.has_theft_alarm = false
	truck.ensure_presentation()
	truck.body_viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	truck.body_viewport.get_camera_3d().rotation.x = -atan2(7.55,4.0)
	truck.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var carried: Dictionary = saved.get("cargo",{})
	if not carried.is_empty():
		yard._ensure_contract_target()
		var target: Node2D = yard._target
		if not is_instance_valid(target) or String(target.get_meta("salvage_token","")) != String(carried.get("token","")) or String(carried.get("token","")) == "":
			target = null
			var origin: Dictionary = carried.get("origin",{})
			if not origin.is_empty():
				for candidate in get_tree().get_nodes_in_group("modern_parked_vehicle"):
					if String(candidate.name)==String(origin.name) and candidate.global_position.distance_to(Vector2(origin.x,origin.y))<30 and can_tow(candidate):
						target = candidate
						break
			if not is_instance_valid(target): target = FACTORY.spawn_parked_vehicle(yard.get_parent(),"NecoRestoredCargo",truck.position,truck.rotation,String(carried.id),0,Color(String(carried.paint)))
		target.set_meta("tow_origin",carried.get("origin",{}))
		target.health = int(carried.health)
		_mount(target,false)

func can_tow(car: Node2D) -> bool:
	return yard.eligible(car) and car.get("_detached_from_lane") == true and float(car.target_length) <= 95 and car.get("is_moving_on_lane") != true and not car.has_meta("tow_carried")

func nearby_car() -> Node2D:
	var nearest: Node2D
	var best := 82.0
	var rear: Vector2 = truck.to_global(Vector2(-78,0))
	for car in get_tree().get_nodes_in_group("vehicle"):
		if not can_tow(car): continue
		var distance: float = car.global_position.distance_to(rear)
		if distance < best and truck.to_local(car.global_position).x < -35:
			best = distance
			nearest = car
	return nearest

func attach(car: Node2D) -> bool:
	if not is_instance_valid(truck) or is_instance_valid(cargo) or truck.health <= 0 or truck.velocity.length() > 8: return false
	if not can_tow(car) or car != nearby_car(): return false
	# Não puxe através de muro, cerca ou outro veículo até a plataforma.
	var ray := PhysicsRayQueryParameters2D.create(car.global_position,truck.global_position,3,[car.get_rid(),truck.get_rid()])
	if not truck.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): return false
	var sweep := PhysicsShapeQueryParameters2D.new()
	sweep.shape = car.collision.shape
	sweep.transform = car.global_transform
	sweep.motion = truck.global_position-car.global_position
	sweep.collision_mask = 3
	sweep.exclude = [car.get_rid(),truck.get_rid()]
	if truck.get_world_2d().direct_space_state.cast_motion(sweep)[0] < .99: return false
	_mount(car,true)
	return true

func _mount(car: Node2D, report: bool) -> void:
	cargo = car
	car.ensure_presentation()
	if not report and car.is_police_vehicle: car.was_stolen_from_police = true
	if not car.has_meta("tow_origin"):
		car.set_meta("tow_origin",{"name":String(car.name),"x":car.global_position.x,"y":car.global_position.y})
	_cargo_layers = Vector2i(car.collision_layer,car.collision_mask)
	_cargo_mode = car.process_mode
	_cargo_physics = car.is_physics_processing()
	_cargo_idle = car.is_processing()
	car.set_meta("tow_carried",true)
	car.hide()
	car.collision_layer = 0
	car.collision_mask = 0
	car.process_mode = Node.PROCESS_MODE_DISABLED
	_previous_health = int(truck.health)
	truck.ensure_presentation()
	truck.body_viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var spec: Dictionary = VehicleCatalog.get_vehicle_spec(String(car.vehicle_id))
	payload = load(String(spec.model_class)).new()
	truck.body_model.add_child(payload)
	payload.position = Vector3(0,.96,1.0)
	payload.scale = Vector3.ONE * .82
	if "paint" in payload and is_instance_valid(payload.paint) and is_instance_valid(car.body_model):
		payload.paint.albedo_color = car.body_model.paint.albedo_color
	if report:
		var motor := AudioStreamPlayer2D.new()
		motor.stream = preload("res://world/shared/salvage/SalvageAudio.gd").hydraulics()
		motor.bus = &"SFX"
		motor.volume_db = -16
		truck.add_child(motor)
		motor.play()
		get_tree().create_timer(1.5).timeout.connect(motor.queue_free)
		payload.position = Vector3(0,.1,4.7)
		_load_tween = create_tween()
		_load_tween.tween_property(payload,"position",Vector3(0,.96,1.0),1.4).set_trans(Tween.TRANS_SINE)
		if car.is_police_vehicle and not car.was_stolen_from_police:
			car.was_stolen_from_police = true
			var level := 1 if night_now() else 3
			get_node("/root/WantedManager").ensure_minimum_wanted_level(level)
			_notice("Viatura guinchada! Despiste a polícia antes da entrega.", "Cruiser loaded! Lose the police before delivery.")
		elif car.has_theft_alarm:
			get_node("/root/WantedManager").report_crime(8)
		var contract: Dictionary = yard.ledger().data.contract
		if not contract.is_empty() and String(car.get_meta("salvage_token","")) == String(contract.token):
			contract["tow_loaded"] = true
	truck.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	snapshot()

func _clear_at(point: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = cargo.collision.shape
	query.transform = Transform2D(truck.global_rotation,point)
	query.collision_mask = 3
	query.exclude = [cargo.get_rid()]
	return truck.get_world_2d().direct_space_state.intersect_shape(query).is_empty()

func unload() -> bool:
	if not is_instance_valid(cargo) or not is_instance_valid(truck) or truck.velocity.length() > 8: return false
	var point: Vector2 = truck.to_global(Vector2(-112,0))
	var bay: Vector2 = yard.to_global(yard.dock)
	if point.distance_to(bay) < 100: point = bay
	if not _clear_at(point): return false
	var ray := PhysicsRayQueryParameters2D.create(truck.global_position,point,1,[truck.get_rid()])
	if not truck.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): return false
	if is_instance_valid(_load_tween): _load_tween.kill()
	cargo.global_position = point
	cargo.global_rotation = truck.global_rotation
	cargo.collision_layer = _cargo_layers.x
	cargo.collision_mask = _cargo_layers.y
	cargo.process_mode = _cargo_mode
	cargo.set_physics_process(_cargo_physics)
	cargo.set_process(_cargo_idle)
	cargo.remove_meta("tow_carried")
	cargo.show()
	cargo = null
	_remove_payload()
	snapshot()
	return true

func _remove_payload() -> void:
	if is_instance_valid(payload): payload.queue_free()
	payload = null
	if is_instance_valid(truck) and is_instance_valid(truck.body_viewport): truck.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _discard_cargo() -> void:
	if is_instance_valid(cargo): cargo.queue_free()
	cargo = null
	_remove_payload()
	snapshot()

func snapshot() -> void:
	if not is_instance_valid(truck): return
	var saved := {"position":[truck.global_position.x,truck.global_position.y],"rotation":truck.global_rotation,"health":truck.health,"legacy":yard.legacy,"cargo":{}}
	if is_instance_valid(cargo):
		var paint := Color.WHITE
		if is_instance_valid(cargo.body_model): paint = cargo.body_model.paint.albedo_color
		saved.cargo = {"id":cargo.vehicle_id,"health":cargo.health,"paint":paint.to_html(),"token":String(cargo.get_meta("salvage_token","")),"origin":cargo.get_meta("tow_origin",{})}
	yard.ledger().data["tow_vehicle"] = saved

func night_now() -> bool:
	var clock := get_tree().get_first_node_in_group("day_night_manager")
	return clock != null and JOBS.is_night(float(clock.time_of_day))

func add_offer(content: VBoxContainer) -> void:
	var data: Dictionary = yard.ledger().data
	if not is_instance_valid(truck) or ((truck.health <= 0 or truck.global_position.distance_to(yard.global_position)>700) and not truck.is_driven_by_player and not is_instance_valid(cargo)):
		yard._button(content,yard._text("Recuperar guincho no pátio", "Recover truck at the yard"),recover_truck)
	if not data.contract.is_empty(): return
	var job := JOBS.next_job(data)
	_offer = choose_target(job)
	var copy := Label.new()
	copy.custom_minimum_size.x = 520
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var title: String = yard._text(job.title,job.en)
	copy.text = yard._text("GUINCHO DO NECO • %d/5: %s\n$%d • %d min. Pegue o caminhão amarelo junto ao acesso. Pare de ré perto do alvo e use a interação para carregar; devolva na baia e entregue à prensa.", "NECO'S TOW JOBS • %d/5: %s\n$%d • %d min. Take the yellow truck by the access road. Stop with its rear near the target and interact to load; unload at the bay and deliver to the press.") % [job.stage,title,job.reward,int(job.duration)/60]
	if job.kind == "police":
		copy.text += "\n" + yard._text("Viatura: buscar entre 20h e 6h reduz o alerta de 3 para 1 estrela. Despiste antes de entregar.", "Cruiser: collect between 8 PM and 6 AM to reduce the alert from 3 stars to 1. Lose the cops before delivery.")
	content.add_child(copy)
	var button: Button = yard._button(content,yard._text("Aceitar serviço de guincho", "Accept tow job"),accept_job)
	button.disabled = _offer == null or yard.ledger().available() == 0 or int(data.jobs_taken) >= 3
	if int(data.jobs_taken) >= 3: copy.text += "\n" + yard._text("Novos serviços amanhã.", "More jobs tomorrow.")

func choose_target(job: Dictionary) -> Node2D:
	var candidates: Array[Node2D] = []
	for car in get_tree().get_nodes_in_group("modern_parked_vehicle"):
		if not can_tow(car) or car.has_meta("salvage_token") or car.global_position.distance_to(yard.global_position)<900: continue
		if job.kind == "police" and not car.is_police_vehicle: continue
		if job.kind != "police" and car.is_police_vehicle: continue
		candidates.append(car)
	candidates.sort_custom(func(a: Node2D,b: Node2D): return a.global_position.distance_squared_to(yard.global_position)<b.global_position.distance_squared_to(yard.global_position))
	# Depois de entregar as viaturas fixas, Neco marca outra vaga distante.
	# Assim a série não fica presa quando a frota do estacionamento acaba.
	if candidates.is_empty():
		return choose_target({"kind":"rare"}) if job.kind == "police" else null
	return candidates[0] if job.kind == "local" else candidates[-1]

func accept_job() -> void:
	var book: RefCounted = yard.ledger()
	var job := JOBS.next_job(book.data)
	if not is_instance_valid(_offer) or not can_tow(_offer): yard._close_panel(); return
	var spec := {"vehicle_id":String(_offer.vehicle_id),"label":yard._text(job.title,job.en),"position":[_offer.global_position.x,_offer.global_position.y],"rotation":_offer.global_rotation,"reward":job.reward,"duration":job.duration,"legacy":yard.legacy,"tow_required":true,"tow_loaded":false}
	if book.accept(spec):
		book.data.contract["source_name"] = String(_offer.name)
		book.data.contract["source_position"] = [_offer.global_position.x,_offer.global_position.y]
		yard._target = _offer
		yard._last_token = String(book.data.contract.token)
		_offer.set_meta("salvage_token",yard._last_token)
		if job.kind in ["special","rare"] or (job.kind == "police" and not _offer.is_police_vehicle):
			var id := "police_cruiser" if job.kind == "police" else ("sport_coupe" if job.kind == "special" else "cobra_v8")
			_offer.apply_archetype(id,Color.WHITE if job.kind == "police" else Color("983f43"))
			book.data.contract.vehicle_id = String(_offer.vehicle_id)
		yard._mark_target()
	yard._close_panel()

func recover_truck() -> void:
	if is_instance_valid(truck) and truck.is_driven_by_player: return
	if is_instance_valid(cargo): return
	if not is_instance_valid(truck):
		yard.ledger().data["tow_vehicle"]={}
		_restore()
	truck.global_position = yard.to_global(Vector2(155,440))
	truck.global_rotation = PI
	truck.repair_vehicle()
	truck.configure_as_parked()
	snapshot()
	yard._close_panel()

func _notice(pt: String, en: String) -> void:
	if is_instance_valid(yard._player): yard._player._show_weapon_notice(yard._text(pt,en))
