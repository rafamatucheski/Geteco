extends Node
const COURSE := preload("res://world/mountain_jeep/MountainJeepCourse.gd")
const RUN := preload("res://activities/mountain_jeep/MountainJeepRun.gd")
const PROGRESS := preload("res://systems/campaign/MountainJeepProgress.gd")
const FLEET_STATE := preload("res://runtime/FleetState.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var session
var progress := PROGRESS.new()
var run := RUN.new()
var driver: CharacterBody3D
var loan: CharacterBody3D
var _status: Label
var _loan_clock := 0.0
var _hud_clock := 0.0
var active: bool:
	get: return run.active

func configure(owner_session) -> void:
	session=owner_session
	var saved: Variant=session.state.world_state.get("mountain_jeep",{})
	if not saved is Dictionary or (not saved.is_empty() and (not progress.restore_snapshot(saved) or not PROGRESS.validate_wallet(saved,session.state.economy.snapshot()))):
		session.controller.save_invalid=true
		session.show_message("Dados da trilha inválidos; save original preservado.")
	_status=Label.new()
	_status.position=Vector2(24,184)
	_status.add_theme_font_size_override("font_size",20)
	_status.add_theme_color_override("font_outline_color",Color("101820"))
	_status.add_theme_constant_override("outline_size",5)
	session.world.hud.add_child(_status)
	process_physics_priority=25

func snapshot() -> Dictionary:
	_capture_loan()
	return progress.snapshot()

func save_block_reason() -> String:
	return "Encerre a trilha de jipe para salvar." if run.active else ""

func objective() -> String:
	if not run.active:
		return "Trilha dos Pinheiros · leve um jipe 4x4 à largada."
	if run.countdown>0.0: return String(TranslationServer.translate("Mantenha o jipe parado · %d")) % ceili(run.countdown)
	return String(TranslationServer.translate("Trilha dos Pinheiros · checkpoint %d/%d · %.1f s")) % [run.gate+1,run.gates.size(),maxf(0.0,COURSE.TIME_LIMIT-run.elapsed)]

func target_position() -> Vector3:
	return run.target_position() if run.active else COURSE.start()

func _outside() -> bool:
	return session.state.region_id=="mountain" and session.state.place_id.is_empty() and session.world.gameplay.health>0

func _can_start() -> bool:
	if not _outside() or session.controller.save_invalid or not session.state.campaign.active_id.is_empty(): return false
	if session.blocks_driving_change() or session.world.player.input_locked: return false
	var coordinator := get_tree().get_first_node_in_group("mountain_activities")
	if coordinator!=null and coordinator.has_method("can_start") and not coordinator.can_start(self): return false
	return true

func nearest_action() -> Dictionary:
	if session==null or not session.ready_for_play or session.modal: return {}
	if run.active: return {"id":"mountain_jeep","target":"cancel","label":"Cancelar trilha"}
	if not _can_start(): return {}
	var driving=session.world.driving
	var point: Vector3=driving.car.global_position if driving.occupied and is_instance_valid(driving.car) else session.world.player.global_position
	if point.distance_to(COURSE.start())>4.0: return {}
	if not driving.occupied:
		return {"id":"mountain_jeep","target":"prepare","label":"Retirar jipe da trilha","position":COURSE.start()}
	return {"id":"mountain_jeep","target":"start","label":String(TranslationServer.translate("Trilha dos Pinheiros · %d s")) % int(COURSE.TIME_LIMIT),"position":COURSE.start()}

func perform(target: Variant) -> bool:
	var action := str(target.get("target","")) if target is Dictionary else str(target)
	if nearest_action().get("target","")!=action: return false
	if action=="cancel": cancel_attempt(); session.show_message("Trilha cancelada."); return true
	if action=="prepare":
		_ensure_loan()
		if is_instance_valid(loan):
			session.show_message("Entre no jipe e alinhe na largada." if loan.health>0 else "O jipe está danificado. Repare-o ou traga outro jipe 4x4.")
		elif not progress.data.vehicle.is_empty():
			session.show_message("O jipe da trilha permanece onde foi estacionado. Você também pode usar outro jipe 4x4.")
		else: session.show_message("Libere o espaço ao lado da largada para retirar o jipe.")
		return true
	if action!="start": return false
	var car: CharacterBody3D=session.world.driving.car
	if car.archetype!=COURSE.VEHICLE:
		session.show_message("Use um jipe 4x4 na Trilha dos Pinheiros."); return true
	if car.health<=0 or absf(car.speed)>.8:
		session.show_message("Pare o jipe junto à largada."); return true
	if not session.save_game(true): return false
	if not run.begin(car.get_instance_id(),car.archetype,car.global_position): return false
	driver=car
	_status.text=objective()
	return true

func cancel_attempt() -> void:
	run.cancel()
	driver=null
	if is_instance_valid(_status): _status.text=""
	# The physical jeep remains parked or under the existing driver's control.
	_capture_loan()

func _physics_process(delta: float) -> void:
	if session==null or get_tree().paused: return
	if run.active:
		var valid: bool=_outside() and session.ready_for_play and not session.blocks_driving_change() and is_instance_valid(driver)
		valid=valid and session.world.driving.occupied and session.world.driving.car==driver
		if valid: valid=driver.health>0 and driver.archetype==COURSE.VEHICLE and not driver.is_queued_for_deletion()
		if not valid:
			cancel_attempt()
			return
		if not session.modal:
			run.tick(delta,driver.global_position,driver.get_instance_id(),true)
			if run.finished:
				var result := progress.settle(run,session.state.economy)
				if result.is_empty():
					session.show_message("Prova concluída; não foi possível registrar o prêmio.")
				else:
					session.state.world_state.mountain_jeep=snapshot()
					var suffix := " · R$ %d" % result.paid if result.paid>0 else " · novo recorde" if result.record else ""
					session.show_message(String(TranslationServer.translate("Trilha concluída · %.2f s%s")) % [result.time,suffix])
					session.save_game(true)
				driver=null
				_status.text=""
			elif not run.active:
				var message := "Tempo esgotado." if run.failure=="timeout" else "Largada queimada." if run.failure=="false_start" else "Trilha interrompida. Volte à largada."
				session.show_message(message)
				driver=null
				_status.text=""
		_hud_clock+=delta
		if _hud_clock>=.1 and run.active:
			_hud_clock=0.0
			_status.text=objective()
	if not session.ready_for_play or session.modal or session.controller.save_invalid: return
	_loan_clock+=delta
	if _loan_clock<.5: return
	_loan_clock=0.0
	_ensure_loan()

func _capture_loan() -> void:
	if not is_instance_valid(loan) or not loan.is_inside_tree(): return
	progress.data.vehicle=FLEET_STATE.capture(loan,str(loan.get_meta("region_id","mountain")))
	if is_instance_valid(session): session.state.world_state.mountain_jeep=progress.snapshot()

func _bind_loan(car: CharacterBody3D) -> void:
	loan=car
	car.set_meta("race_owned",true)
	car.set_meta("mountain_jeep_loan",true)
	if not car.tree_exiting.is_connected(_capture_loan): car.tree_exiting.connect(_capture_loan)

func _ensure_loan() -> void:
	if is_instance_valid(loan): return
	# ProductionWorld may already have restored the player's last driven jeep.
	for existing in session.controller.vehicles:
		if is_instance_valid(existing) and not existing.is_queued_for_deletion() and existing.vehicle_id==COURSE.LOAN_ID:
			if existing.archetype!=COURSE.VEHICLE:
				session.controller.save_invalid=true
				session.show_message("Identidade do jipe inválida; save original preservado.")
				return
			_bind_loan(existing)
			return
	if not session.state.place_id.is_empty() or session.blocks_driving_change(): return
	var selected: Dictionary=session.controller.starting_vehicle()
	var saved: Dictionary=progress.vehicle_for_restore(selected)
	var region_id := str(saved.get("region","mountain"))
	if session.state.region_id!=region_id: return
	var point := COURSE.parking()
	if not saved.is_empty(): point=Vector3(saved.position[0],saved.position[1],saved.position[2])
	if session.world.player.global_position.distance_to(point)>42.0: return
	var car: CharacterBody3D=VEHICLE.new()
	car.archetype=COURSE.VEHICLE
	car.vehicle_id=COURSE.LOAN_ID
	car.position=point
	car.rotation.y=float(saved.get("yaw",COURSE.parking_yaw()))
	car.set_meta("region_id",region_id)
	car.paint_color=Color.html(saved.paint) if saved.has("paint") else Color("c4a369")
	car.equipment_state=saved.get("equipment",{}).duplicate(true)
	session.world.add_child(car)
	if not session.controller.vehicle_position_clear(car,point,car.rotation.y):
		car.queue_free()
		return
	if saved.has("health"): car.restore_health(float(saved.health))
	car.restore_body_dents(saved.get("body_dents",[]),saved.get("breakaway_parts",{}))
	if int(saved.get("punctured_tires",0))>0:
		preload("res://gameplay/police_response/ground/TirePuncture.gd").puncture(car,int(saved.punctured_tires))
	if float(saved.get("heavy_crush_ratio",1.0))<1.0:
		preload("res://gameplay/street_physics/HeavyVehicleCrush.gd").apply_saved(car,float(saved.heavy_crush_ratio))
	car.destroyed.connect(func():
		if is_instance_valid(session.world.gameplay):
			session.world.gameplay.explode(car.global_position+Vector3.UP*.4,5.0,35.0,car,false))
	session.controller.vehicles.append(car)
	_bind_loan(car)
	_capture_loan()

func _exit_tree() -> void:
	_capture_loan()
	if is_instance_valid(_status): _status.queue_free()
