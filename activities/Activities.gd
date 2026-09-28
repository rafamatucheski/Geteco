extends Node
const Definitions := preload("res://activities/ActivityDefinitions.gd")
const Motorsport := preload("res://activities/Motorsport.gd")
const Residence := preload("res://activities/Residence.gd")
const TowJobs := preload("res://data/catalogs/TowJobs.gd")
var session
var motorsport = Motorsport.new()
var residence = Residence.new()
var _data := {"version":1,"race_best":{},"drift_best":{},"races_finished":0,"race_records":0,
	"drift_finished":0,"tow_completed":0,"tow_serial":0,"tow_contract":{},"day":1,"day_clock":0.0,"tow_taken_today":0,"tow_delivered_today":0,"attempt":0}
var _driver: CharacterBody3D
var _region := ""
var _place := ""
var _clock := 0.0
var _visuals: Array[Node3D] = []
var _pickups: Dictionary = {}
var _gate: Node3D
var _status: Label
var _tow_recovered := false
var _tow_retry_clock := 0.0

func configure(owner_session) -> void:
	session = owner_session
	residence.session = session
	var saved: Variant = session.state.world_state.get("activities", {})
	if saved is Dictionary and not saved.is_empty() and not restore_snapshot(saved):
		session.controller.save_invalid = true
		session.show_message("Estado de atividades inválido; save original preservado.")
	_status = Label.new()
	_status.position = Vector2(430,82)
	_status.add_theme_font_size_override("font_size",20)
	_status.add_theme_color_override("font_shadow_color",Color.BLACK)
	session.world.hud.add_child(_status)
	_gate = _beacon(Vector3.ZERO,Color("74d9ff"),true)
	_gate.hide()
	if not session.world.gameplay.changed.is_connected(refresh_achievements):
		session.world.gameplay.changed.connect(refresh_achievements)
	refresh_achievements()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if session == null or not session.ready_for_play or get_tree().paused or session.modal: return
	var world = session.world
	if world.gameplay.health <= 0:
		motorsport.cancel()
		return
	if motorsport.mode != "":
		var mode: String = motorsport.mode
		var valid: bool = is_instance_valid(_driver) and world.driving.occupied and world.driving.car == _driver and _driver.health > 0 and session.state.place_id.is_empty() and session.state.region_id == _region
		motorsport.update(delta,_driver.position if valid else Vector3.ZERO,_driver.velocity if valid else Vector3.ZERO,-_driver.global_basis.z if valid else Vector3.FORWARD,valid)
		if motorsport.finished: _finish_motorsport(mode)
		elif motorsport.cancelled: session.show_message("Tentativa cancelada. Sem cobrança.")
		_gate.visible = motorsport.mode != ""
		if _gate.visible: _gate.position = motorsport.target_position()+Vector3.UP*.05
		_status.text = ("Largada em %d"%ceili(motorsport.countdown)) if motorsport.countdown > 0 else ("%.1f s · Portão %d/%d"%[motorsport.elapsed,motorsport.gate+1,motorsport.points.size()] if mode == "race" else "Drift · %d pts · %.0f s"%[int(motorsport.score),maxf(0,25-motorsport.elapsed)])
	else: _status.text = ""
	_tick_tow(delta)
	_clock += delta
	if _clock < .25: return
	_clock = 0
	if _region != session.state.region_id or _place != session.state.place_id:
		_region = session.state.region_id
		_place = session.state.place_id
		_rebuild()
	for visual in _visuals:
		if is_instance_valid(visual): visual.visible = visual.position.distance_to(world.player.position) < 100
	for area in _pickups.values():
		if not is_instance_valid(area): continue
		var near: bool = area.position.distance_to(world.player.position) < 55
		if near and not area.has_meta("grounded"):
			var source: Vector3 = area.get_meta("source_point")
			var ray := PhysicsRayQueryParameters3D.create(source+Vector3.UP*12,source-Vector3.UP*3,1)
			var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty(): near = false
			else:
				area.position.y = float(hit.position.y)+.35
				area.set_meta("grounded",true)
		area.visible = near
		area.set_deferred("monitoring",near)
	residence.restore_deployed()

func nearest_action() -> Dictionary:
	if session == null or session.modal or not session.state.place_id.is_empty(): return {}
	var world = session.world
	var point: Vector3 = world.driving.car.position if world.driving.occupied else world.player.position
	var options: Array = []
	if motorsport.mode != "": return {"id":"activity_cancel","target":"activity_cancel","label":"Cancelar tentativa","position":point}
	if session.state.campaign.active_id != "": return {}
	if world.driving.occupied:
		for id in Definitions.races(session.state.region_id):
			var row: Dictionary = Definitions.races(session.state.region_id)[id]
			options.append(_action("race:"+id,"Correr · "+str(row.name),Definitions.at(row.start)))
		for id in Definitions.drifts(session.state.region_id):
			var row: Dictionary = Definitions.drifts(session.state.region_id)[id]
			options.append(_action("drift:"+id,"Drift · "+str(row.name),Definitions.at(row.pos)))
		if residence.data.active_home != "" and session.state.region_id == "harbor":
			var slot: String = residence.vehicle_slot(world.driving.car.archetype)
			options.append(_action("home_store","Guardar moto" if slot == "motorcycle" else "Guardar carro",residence.parking(residence.data.active_home,slot),4.5))
	else:
		if session.state.region_id == "harbor":
			for id in Definitions.HOMES.PROPERTIES:
				if not residence.can_enter(id): options.append(_action("home_buy:"+id,"Comprar casa · R$ %d"%int(residence.quote(id).get("due",0)),residence.entry(id),4.5))
			if residence.data.active_home != "":
				for slot in ["car","motorcycle"]:
					if residence._record(slot).get("status", "") == "stored":
						options.append(_action("home_retrieve:"+slot,"Retirar moto" if slot == "motorcycle" else "Retirar carro",residence.parking(residence.data.active_home,slot),5.5))
			options.append(_action("tow_accept" if _data.tow_contract.is_empty() else "tow_deliver","Serviço de guincho" if _data.tow_contract.is_empty() else "Entregar reboque",_tow_service_position(),4.5))
	var closest := {}
	var distance := INF
	for action in options:
		var separation: float = point.distance_to(action.position)
		if separation <= float(action.get("range",3.75)) and separation < distance:
			distance = separation
			closest = action
	return closest

func perform(target: Variant) -> bool:
	var id: String = str(target.get("target", "")) if target is Dictionary else str(target)
	var action := nearest_action()
	if action.get("target", "") != id: return false
	if id == "activity_cancel": motorsport.cancel(); _gate.hide(); return true
	if id.begins_with("race:") or id.begins_with("drift:"):
		return _start_motorsport(id)
	if id.begins_with("home_buy:"):
		var home := id.trim_prefix("home_buy:")
		var quote := residence.quote(home)
		session._menu("Comprar casa · R$ %d"%int(quote.get("due",0)))
		session._button("Confirmar compra",func():
			session.close_menu()
			if residence.buy(home): _commit(); session.show_message("Casa adquirida.")
			else: session.show_message("Compra indisponível ou saldo insuficiente."))
		return true
	if id == "home_store":
		_store_home_vehicle()
		return true
	if id.begins_with("home_retrieve:"):
		var success: bool = residence.retrieve_vehicle(id.trim_prefix("home_retrieve:"))
		if success: _commit()
		session.show_message("Veículo retirado." if success else "Mantenha a vaga e a saída livres.")
		return true
	if id == "tow_accept": return _accept_tow()
	if id == "tow_deliver": return _deliver_tow()
	return false

func can_enter_home(id: String) -> bool:
	return not Definitions.HOMES.PROPERTIES.has(id) or residence.can_enter(id)

func _store_home_vehicle() -> void:
	var success: bool = await residence.store_vehicle()
	if success: _commit()
	session.show_message("Veículo guardado." if success else "Pare na garagem; é permitido um carro e uma moto. Mantenha a saída livre.")

func salvage_available() -> int:
	return maxi(0,6-int(_data.tow_delivered_today))

## Recibo único da próxima entrega na prensa (o Economy recusa recibo repetido).
func salvage_receipt(kind: String) -> String:
	return "%s:day%d:%d" % [kind, int(_data.day), int(_data.tow_delivered_today) + 1]

func record_external_delivery() -> bool:
	if salvage_available()<=0: return false
	_data.tow_delivered_today+=1
	return true

func _start_motorsport(action: String) -> bool:
	var car = session.world.driving.car
	if not session.world.driving.occupied or absf(car.speed) >= 25.0/16.0: session.show_message("Pare com o carro na marca."); return true
	_driver = car
	var id := action.get_slice(":",1)
	var started := false
	if action.begins_with("race:"):
		var time: float = float(session.state.world_state.get("time",.32))
		if is_instance_valid(session.weather): time = float(session.weather.time_of_day)
		if time <= .78 and time >= .28: session.show_message("Corridas disponíveis à noite."); return true
		var spec: Dictionary = Definitions.races(session.state.region_id)[id]
		var points := PackedVector3Array()
		for point in spec.checkpoints: points.append(Definitions.at(point))
		if not session.save_game(true): return false
		started = motorsport.begin_race(id,Definitions.at(spec.start),points,car.position)
	else:
		var spec: Dictionary = Definitions.drifts(session.state.region_id)[id]
		if not session.save_game(true): return false
		started = motorsport.begin_drift(id,Definitions.at(spec.pos),float(spec.radius)/16.0,car.position)
	if started:
		_data.attempt += 1
		_region = session.state.region_id
	return started

func _finish_motorsport(mode: String) -> void:
	var reward := 0
	if mode == "race":
		var spec: Dictionary = Definitions.races(_region)[motorsport.id]
		var record: bool = not _data.race_best.has(motorsport.id) or motorsport.elapsed < float(_data.race_best[motorsport.id])
		if record: _data.race_best[motorsport.id] = motorsport.elapsed; _data.race_records += 1
		_data.races_finished += 1
		reward = int(spec.reward) + (int(spec.best_time_bonus) if record else 0)
	else:
		var spec: Dictionary = Definitions.drifts(_region)[motorsport.id]
		var points := int(motorsport.score)
		_data.drift_best[motorsport.id] = maxi(points,int(_data.drift_best.get(motorsport.id,0)))
		if points > 0: _data.drift_finished += 1
		reward = int(points/1000.0*int(spec.reward_per_1000))
	session.state.economy.grant_reward("activity:%d:%s"%[int(_data.attempt),motorsport.id],reward)
	_achievements()
	_commit()
	session.show_message("Atividade concluída · +R$ %d"%reward)

func _rebuild() -> void:
	for visual in _visuals:
		if is_instance_valid(visual): visual.queue_free()
	for area in _pickups.values():
		if is_instance_valid(area): area.queue_free()
	_visuals.clear()
	_pickups.clear()
	if _place == "":
		for definition in Definitions.drifts(_region).values(): _visuals.append(_beacon(Definitions.at(definition.pos),Color("d7a958")))
		for definition in Definitions.races(_region).values(): _visuals.append(_beacon(Definitions.at(definition.start),Color("74d9ff")))
	var found: Array = session.state.economy.snapshot().collectibles
	for entry in Definitions.collectibles():
		if entry.region != _region or entry.place != _place or found.has(entry.id): continue
		var point: Vector3 = entry.point
		if _place != "":
			if not is_instance_valid(session.room): continue
			point = session.room.to_global(point)
		_create_pickup(entry.id,point)

func _create_pickup(id: String, point: Vector3) -> void:
	var area := Area3D.new()
	area.position = point+Vector3.UP*.4
	area.set_meta("source_point",point)
	area.monitoring = false
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = .8
	shape.shape = sphere
	area.add_child(shape)
	var mesh := MeshInstance3D.new()
	var item := BoxMesh.new()
	item.size = Vector3(.27,.1,.19) if id != "mountain_expedition_pack" else Vector3(.35,.4,.25)
	mesh.mesh = item
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b6a57d")
	mesh.material_override = material
	area.add_child(mesh)
	area.body_entered.connect(func(body):
		if body != session.world.player or session.world.driving.occupied or session.modal: return
		if session.state.economy.collect(id):
			area.set_deferred("monitoring",false)
			area.hide()
			_pickups.erase(id)
			area.queue_free()
			_achievements()
			var announcement := ""
			if session.mountain_progression != null: announcement = session.mountain_progression.on_collectible()
			if _commit(): session.show_message(announcement if not announcement.is_empty() else "Achado recolhido."))
	session.world.add_child(area)
	_pickups[id] = area

func _beacon(point: Vector3, color: Color, gate: bool = false) -> Node3D:
	var root := Node3D.new()
	root.position = point+Vector3.UP*.04
	var mesh := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 2.9 if gate else .6
	ring.outer_radius = 3.0 if gate else .7
	ring.rings = 20
	ring.ring_segments = 6
	mesh.mesh = ring
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	session.world.add_child(root)
	return root

func _action(id: String, label: String, point: Vector3, distance: float = 3.75) -> Dictionary:
	return {"id":id,"target":id,"label":label,"position":point,"range":distance}

func _tow_service_position() -> Vector3:
	if is_instance_valid(session.mission_world) and session.mission_world.has_method("tow_snapshot"):
		var status: Dictionary = session.mission_world.tow_snapshot()
		if status.get("service_position") is Vector3: return status.service_position
	return Definitions.at(Vector2(-750,550))+Vector3(-6,0,8.7)

func _accept_tow() -> bool:
	if not _data.tow_contract.is_empty() or _data.tow_taken_today >= 3 or _data.tow_delivered_today >= 6: session.show_message("Serviços do dia encerrados."); return true
	var index: int = int(_data.tow_completed)%TowJobs.JOBS.size()
	var job: Dictionary = TowJobs.JOBS[index].duplicate(true)
	if not is_instance_valid(session.mission_world) or not session.mission_world.has_method("begin_tow_job"): return false
	job.token = "tow_%d"%(int(_data.tow_serial)+1)
	job.index = index
	if not session.save_game(true): return false
	if not session.mission_world.begin_tow_job(job): session.show_message("Guincho indisponível. Termine a recuperação atual."); return true
	_data.tow_serial += 1
	_data.tow_taken_today += 1
	job.remaining = float(job.duration)
	_data.tow_contract = job
	_tow_recovered = true
	_commit()
	session.show_message(str(job.title)+" · Use o guincho e entregue na baia.")
	return true

func _deliver_tow() -> bool:
	if _data.tow_contract.is_empty() or not is_instance_valid(session.mission_world): return false
	if not session.mission_world.can_finish_tow_job():
		session.show_message("Descarregue o carro inteiro e parado na baia.")
		return true
	var status: Dictionary = session.mission_world.tow_snapshot()
	if status.get("token") != _data.tow_contract.token or status.get("alive") != true or status.get("unloaded_at_bay") != true or status.get("loaded") == true or session.world.gameplay.stars > 0:
		session.show_message("Descarregue o carro inteiro na baia e despiste a polícia.")
		return true
	var job: Dictionary = _data.tow_contract
	var wallet_before: Dictionary = session.state.economy.snapshot()
	if not session.state.economy.grant_reward("tow:"+str(job.token),int(job.reward)): return false
	if not session.mission_world.finish_tow_job():
		session.state.economy.restore_snapshot(wallet_before)
		return false
	_data.tow_completed += 1
	_data.tow_delivered_today += 1
	_data.tow_contract = {}
	_commit()
	session.show_message("Reboque entregue · +R$ %d"%int(job.reward))
	return true

func _tick_tow(delta: float) -> void:
	_data.day_clock += delta
	if float(_data.day_clock) >= 600.0:
		_data.day_clock = fmod(float(_data.day_clock),600.0)
		_data.day += 1
		_data.tow_taken_today = 0
		_data.tow_delivered_today = 0
	if _data.tow_contract.is_empty(): return
	_data.tow_contract.remaining = maxf(0,float(_data.tow_contract.remaining)-delta)
	_tow_retry_clock -= delta
	if not _tow_recovered and _tow_retry_clock <= 0 and is_instance_valid(session.mission_world) and session.mission_world.has_method("begin_tow_job"):
		_tow_retry_clock = 1.0
		_tow_recovered = session.mission_world.begin_tow_job(_data.tow_contract)
	if float(_data.tow_contract.remaining) <= 0:
		if _tow_retry_clock > 0:
			_data.tow_contract.remaining = .01
			return
		_tow_retry_clock = 1.0
		if is_instance_valid(session.mission_world) and session.mission_world.has_method("cancel_tow_job"):
			if not session.mission_world.cancel_tow_job():
				_data.tow_contract.remaining = .01
				return
		_data.tow_contract = {}
		_commit()
		session.show_message("Prazo do reboque encerrado.")

func cancel_attempt() -> void:
	motorsport.cancel()
	_driver = null
	if is_instance_valid(_gate): _gate.hide()
	if is_instance_valid(_status): _status.text = ""

func can_rest() -> bool:
	return motorsport.mode.is_empty() and _data.tow_contract.is_empty()

func advance_time(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0 or not can_rest(): return
	var total: float = float(_data.day_clock)+seconds
	var days := int(floor(total/600.0))
	_data.day_clock = fmod(total,600.0)
	if days > 0:
		_data.day += days
		_data.tow_taken_today = 0
		_data.tow_delivered_today = 0

func _achievements() -> void:
	refresh_achievements()

func refresh_achievements() -> void:
	if session == null or not session.ready_for_play or session.controller.save_invalid: return
	var best := 0
	for score in _data.drift_best.values(): best = maxi(best,int(score))
	var stats: Dictionary = session.state.economy.achievement_stats()
	stats.merge({"races":_data.races_finished,"bests":_data.race_records,
		"best_drift_score":best,"armor":session.world.gameplay.armor,"wanted_stars":session.world.gameplay.stars})
	if session.mountain_progression != null: stats.merge(session.mountain_progression.stats(),true)
	session.state.economy.evaluate_achievements(stats)

func _commit() -> bool:
	session.state.world_state.activities = snapshot()
	return session.save_game()

func snapshot() -> Dictionary:
	var result := _data.duplicate(true)
	result.home = residence.snapshot()
	return result

func restore_snapshot(saved: Dictionary) -> bool:
	if not validate_snapshot(saved): return false
	_data = saved.duplicate(true)
	_data.erase("home")
	residence.restore_snapshot(saved.home)
	for key in ["version","races_finished","race_records","drift_finished","tow_completed","tow_serial","day","tow_taken_today","tow_delivered_today","attempt"]: _data[key] = int(_data[key])
	motorsport.cancel()
	_tow_recovered = false
	return true

static func validate_snapshot(saved: Dictionary) -> bool:
	for key in ["version","race_best","drift_best","races_finished","race_records","drift_finished","tow_completed","tow_serial","tow_contract","day","day_clock","tow_taken_today","tow_delivered_today","attempt","home"]:
		if not saved.has(key): return false
	for key in ["version","races_finished","race_records","drift_finished","tow_completed","tow_serial","day","tow_taken_today","tow_delivered_today","attempt"]:
		var value: Variant = saved[key]
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)<0 or float(value)>10000000 or float(value)!=floorf(float(value)): return false
	if int(saved.version)!=1 or int(saved.day)<1 or int(saved.tow_taken_today)>3 or int(saved.tow_delivered_today)>6: return false
	if typeof(saved.day_clock) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(saved.day_clock)) or float(saved.day_clock)<0 or float(saved.day_clock)>=600: return false
	if not saved.race_best is Dictionary or not saved.drift_best is Dictionary or not saved.tow_contract is Dictionary or not saved.home is Dictionary: return false
	if not Residence.validate_snapshot(saved.home): return false
	for key in ["race_best","drift_best"]:
		for id in saved[key]:
			var valid: bool = (Definitions.RACES.RACES.has(id) or Definitions.races("harbor").has(id)) if key == "race_best" else Definitions.DRIFT.ZONES.has(id) or Definitions.drifts("harbor").has(id)
			var value: Variant = saved[key][id]
			if not valid or typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)<0: return false
	if not saved.tow_contract.is_empty():
		var job: Dictionary = saved.tow_contract
		if typeof(job.get("index")) not in [TYPE_INT,TYPE_FLOAT] or float(job.index)!=floorf(float(job.index)) or int(job.index)<0 or int(job.index)>=TowJobs.JOBS.size(): return false
		var source: Dictionary = TowJobs.JOBS[int(job.index)]
		if job.get("reward") != source.reward or job.get("duration") != source.duration or job.get("kind") != source.kind or not job.get("token") is String: return false
		if typeof(job.get("remaining")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(job.remaining)) or float(job.remaining)<=0 or float(job.remaining)>float(source.duration): return false
	return true
