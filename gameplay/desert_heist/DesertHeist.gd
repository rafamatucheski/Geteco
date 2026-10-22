extends Node3D
## Duas cargas por madrugada. Só um caminhão físico e dois guardas por vez.
const STATE := preload("res://gameplay/desert_heist/DesertHeistState.gd")
const TRUCK := preload("res://gameplay/desert_heist/DesertHeistTruck.gd")
const GUARD := preload("res://gameplay/desert_heist/DesertHeistGuard.gd")
const ART := preload("res://gameplay/desert_heist/DesertCargoTruckVisual.gd")
const STALL := preload("res://runtime/StallWorkTrace.gd")
const SPEED := 12.0 * preload("res://data/catalogs/VehicleSpeedBalance.gd").FACTOR
var session
var data: Dictionary = {}
var truck: CharacterBody3D
var guards: Array = [null,null]
var _tick := 0.0
var _admission := 0.0
var _road: Curve3D
var _guard_anchor := Vector3.ZERO
var _door_follow_time := 0.0

func configure(owner_session) -> void:
	session=owner_session
	name="DesertCargoHeist"
	# Antes do deserto no quadro, para o enfeite ceder a vez no quadro em que o caminhão entra.
	process_priority=-1
	set_physics_process(false)
	if OS.get_environment("GETECO_DESERT_CARGO_HEIST")=="0": set_process(false); return
	var began := STALL.begin()
	ART.prewarm()
	STALL.finish_slow("desert_cargo.prewarm",began,2000)
	_read_saved()
	_road=Curve3D.new()
	_road.add_point(STATE.START)
	_road.add_point(STATE.END)
	_road.set_meta("traffic_open",true)
	_road.set_meta("traffic_endpoint",STATE.END)
	_road.set_meta("lane_index",0)
	session.world.gameplay.weapon_fired.connect(_gunfire)
	session.world.gameplay.explosion_occurred.connect(_explosion)

func _read_saved() -> void:
	var saved: Variant=session.state.world_state.get(STATE.KEY,{})
	data=saved.duplicate(true) if STATE.valid(saved) else {}

func _process(delta: float) -> void:
	if session==null or not session.ready_for_play: return
	_tick+=delta
	if _tick<.25: return
	var elapsed:=_tick
	_tick=0
	_admission=maxf(0,_admission-elapsed)
	if session.has_position_transition() or session.modal: return
	if not is_instance_valid(truck) and not data.is_empty():
		var restored: CharacterBody3D=session.world.driving.car
		if is_instance_valid(restored) and restored.vehicle_id=="desert_cargo_%d_%d"%[int(data.day),int(data.slot)]:
			truck=restored
			_bind_truck()
			_set_open(data.phase in ["opened","looted"],data.phase=="looted")
	var outdoors: bool=session.state.region_id=="desert" and session.state.place_id.is_empty()
	if not outdoors or session.world.gameplay.health<=0:
		write_snapshot()
		# O caminhão roubado continua sendo do motorista ao cruzar regiões.
		if is_instance_valid(truck) and session.world.driving.car==truck:
			_release_guards()
		else: _release()
		return
	if data.is_empty() or data.phase in ["looted","destroyed","departed"]:
		if is_instance_valid(truck):
			if session.world.driving.car==truck or truck.global_position.distance_to(session.world.player.global_position)<130: return
			_release()
		if not STATE.is_departure_time(session.weather.time_of_day): return
		var day: int=session.weather.moon_day()
		var slot:=0
		if not data.is_empty() and int(data.day)==day:
			slot=int(data.slot)+1
			if slot>1: return
		data=STATE.initial(day,slot)
		_store()
	var point:=_point(data.position)
	if is_instance_valid(truck):
		if truck.health<=0: data.phase="destroyed"
		elif truck.controlled:
			if data.phase=="driving": intercept()
			if data.phase=="intercepted": data.phase="stolen"
			truck.player_damage_attribution=true
		elif data.phase=="driving" and truck.blocked_time>2 and truck.global_position.distance_to(session.world.player.global_position)<30: intercept()
		if data.phase=="driving" and truck.global_position.x>=STATE.END.x-8: data.phase="departed"; truck.traffic=false
		if data.phase in ["intercepted","stolen"]: _admit_guard()
		write_snapshot()
		if session.world.driving.car!=truck and truck.global_position.distance_to(session.world.player.global_position)>130:
			_release()
	else:
		if data.phase=="driving":
			if not STATE.is_departure_time(session.weather.time_of_day): data.phase="departed"; _store(); return
			data.distance=minf(STATE.START.distance_to(STATE.END),float(data.distance)+elapsed*SPEED)
			point=STATE.START+Vector3.RIGHT*float(data.distance)
			data.position=[point.x,point.y,point.z]
			if point.x>=STATE.END.x-8: data.phase="departed"; _store(); return
		if data.get("region","desert")!="desert": return
		if point.distance_to(session.world.player.global_position)<100 and _admission<=0:
			_admission=1.0
			_admit_truck(point)
		_store()

func _admit_truck(point: Vector3) -> void:
	var region: Node3D=session.controller.regions.get("desert")
	# Espera só o chão do deserto, não o enfeite fatiado (DesertRegion.surfaces_idle): com
	# is_streaming_idle(), a 60 fps (padrão) o caminhão podia esperar ~27 s perto da arrancada (e1fad702).
	if not is_instance_valid(region) or not region.surfaces_idle(): return
	region.yield_dressing_this_frame()
	if not region.prepare_collision_at(point): return
	var began := STALL.begin()
	var car:=TRUCK.new()
	car.vehicle_id="desert_cargo_%d_%d"%[int(data.day),int(data.slot)]
	car.position=point
	car.rotation.y=float(data.yaw)
	car.set_meta("region_id","desert")
	car.set_meta("desert_cargo_heist",true)
	car.set_meta("vehicle_theft_handler",Callable(self,"_theft"))
	car.hide()
	session.world.add_child(car)
	STALL.finish_slow("desert_cargo.admit_truck",began,2000)
	if not session.controller.vehicle_position_clear(car,point,float(data.yaw)):
		car.queue_free()
		return
	truck=car
	session.controller.vehicles.append(car)
	car.restore_health(float(data.health))
	car.route=_road
	car.route_distance=float(data.distance)
	car.max_forward_speed=SPEED
	car.traffic=data.phase=="driving"
	_bind_truck()
	_set_open(data.phase=="opened" or data.phase=="looted",data.phase=="looted")
	car.show()
	_guard_anchor=point

func _bind_truck() -> void:
	var hull := truck.shape.shape as BoxShape3D
	if hull != null:
		hull.size.y=3.8
		truck.shape.position.y=1.9
		truck.rotation_shape.size.y=3.65
		truck.body_height=3.8
	truck.set_meta("desert_cargo_heist",true)
	truck.set_meta("vehicle_theft_handler",Callable(self,"_theft"))
	if not truck.damaged.is_connected(_damaged): truck.damaged.connect(_damaged)
	if not truck.destroyed.is_connected(_destroyed): truck.destroyed.connect(_destroyed)

func _door_point() -> Vector3:
	return truck.to_global(Vector3(0,0,truck.half_length+1.1))

func _set_open(opened: bool, empty: bool) -> void:
	ART.set_cargo_open(truck.visual,opened)
	ART.set_loot_visible(truck.visual,opened and not empty)
	# As folhas abertas ultrapassam o casco; os sólidos pertencem ao mesmo corpo.
	for side in [-1,1]:
		var id := "CargoLeafSolidLeft" if side<0 else "CargoLeafSolidRight"
		var solid := truck.get_node_or_null(id) as CollisionShape3D
		if solid==null:
			solid=CollisionShape3D.new()
			solid.name=id
			var box:=BoxShape3D.new()
			box.size=Vector3(1.18,2.34,.21)
			solid.shape=box
			truck.add_child(solid)
		solid.set_deferred("disabled",not opened)
	_door_follow_time=1.3
	set_physics_process(true)
	_sync_door_solids()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(truck): set_physics_process(false); return
	_sync_door_solids()
	_door_follow_time-=delta
	if _door_follow_time<=0: set_physics_process(false)

func _sync_door_solids() -> void:
	for side in [-1,1]:
		var hinge := truck.visual.get_node("CargoDoorLeft" if side<0 else "CargoDoorRight") as Node3D
		var solid := truck.get_node("CargoLeafSolidLeft" if side<0 else "CargoLeafSolidRight") as CollisionShape3D
		solid.transform=truck.visual.transform*hinge.transform*Transform3D(Basis.IDENTITY,Vector3(-side*.60,0,.045))

func intercept() -> void:
	if data.is_empty() or data.phase!="driving" or not is_instance_valid(truck): return
	data.phase="intercepted"
	truck.traffic=false
	truck.brake_input=true
	truck.throttle_input=0
	_guard_anchor=truck.global_position
	# As posições de desembarque só são escolhidas depois da frenagem.
	# Guardas restaurados mantêm sua posição persistida depois de sair da cabine.
	session.show_message("Escolta armada! Tome o caminhão e leve a carga à desova.")
	_store()

func _theft(_car: CharacterBody3D) -> bool:
	if data.phase=="driving": intercept(); return false
	# A primeira tentativa expulsa a dupla; a próxima usa o embarque normal.
	if data.phase=="intercepted":
		for index in 2:
			if not data.guards[index].dead and not is_instance_valid(guards[index]): return false
	return data.phase in ["intercepted","stolen","opened","looted"]

func _damaged(_amount: float) -> void:
	intercept()

func _destroyed() -> void:
	if data.is_empty(): return
	data.phase="destroyed"
	write_snapshot()

func _gunfire(_weapon: String, origin: Vector3) -> void:
	if is_instance_valid(truck) and truck.global_position.distance_to(origin)<22: intercept()

func _explosion(origin: Vector3, radius: float, _source: Node) -> void:
	if is_instance_valid(truck) and truck.global_position.distance_to(origin)<radius+8: intercept()

func _admit_guard() -> void:
	if not is_instance_valid(truck) or absf(truck.speed)>.8: return
	for index in 2:
		if is_instance_valid(guards[index]) or bool(data.guards[index].dead): continue
		var side:= -1 if index==0 else 1
		var point: Vector3=truck.driver_door_anchor(side)+truck.global_basis.x*float(side)*.85
		if data.guards[index].has("position"): point=_point(data.guards[index].position)
		if point.distance_to(session.world.player.global_position)>120: continue
		if not session.controller.region.prepare_collision_at(point): continue
		if not session.position_clear(point): continue
		if point.distance_to(session.world.player.global_position)<1.0: continue
		var guard:=GUARD.new()
		guard.configure(session.world.gameplay,1)
		guard.health=float(data.guards[index].health)
		guard.armor=float(data.guards[index].armor)
		guard.position=point
		guard.alerted=true
		session.world.add_child(guard)
		guard.last_known=session.world.player.global_position
		guards[index]=guard
		truck.animate_driver_door(side,true)
		get_tree().create_timer(.9).timeout.connect(_close_guard_door.bind(truck,side))
		return

func _close_guard_door(car: CharacterBody3D, side: int) -> void:
	if is_instance_valid(car) and not car.controlled and not session.world.driving.is_body_transition_active():
		car.animate_driver_door(side,false)

func nearest_action() -> Dictionary:
	if not _can_open(): return {}
	return {"id":"desert","target":"cargo_heist:collect" if data.phase=="opened" else "cargo_heist:open","label":"Recolher carga" if data.phase=="opened" else "Abrir contêiner"}

func _can_open() -> bool:
	if data.is_empty() or data.phase not in ["stolen","opened"] or not is_instance_valid(truck): return false
	if get_tree().paused or session.world.player.input_locked or session.has_position_transition(): return false
	if session.state.region_id!="desert" or not session.state.place_id.is_empty() or session.world.driving.occupied or session.modal or session.world.gameplay.health<=0: return false
	if truck.health<=0 or absf(truck.speed)>.25 or truck.global_position.distance_to(STATE.DROP_POINT)>14: return false
	if session.world.player.global_position.distance_to(_door_point())>2.2: return false
	for saved_guard in data.guards:
		if not saved_guard.dead and saved_guard.has("position") and _point(saved_guard.position).distance_to(truck.global_position)<40: return false
	for guard in guards:
		if is_instance_valid(guard) and not guard.dead and guard.global_position.distance_to(truck.global_position)<40: return false
	return true

func perform(action: Dictionary) -> bool:
	if not _can_open(): return false
	if action.get("target","")=="cargo_heist:open" and data.phase=="stolen":
		data.phase="opened"
		_set_open(true,false)
		write_snapshot()
		return true
	if action.get("target","")!="cargo_heist:collect" or data.phase!="opened": return false
	var receipt:=STATE.receipt(data)
	if not session.state.economy.has_reward_receipt(receipt) and not session.state.economy.grant_reward(receipt,STATE.reward(data)):
		session.show_message("Libere espaço na carteira para recolher a carga.")
		return false
	data.phase="looted"
	_set_open(true,true)
	write_snapshot()
	session.show_message("Carga recuperada: R$ %d"%STATE.reward(data))
	session.save_game()
	return true

func objective() -> String:
	if data.is_empty(): return ""
	if data.phase=="intercepted": return "Tome o caminhão da escolta."
	if data.phase=="opened": return "Recolha o dinheiro e os valores no contêiner."
	if data.phase=="stolen":
		return "Estacione na desova, despiste a escolta e abra o contêiner pela traseira."
	return ""

func target_position() -> Vector3:
	if not data.is_empty() and data.phase in ["stolen","opened"]: return STATE.DROP_POINT
	return truck.global_position if is_instance_valid(truck) else Vector3.INF

func save_block_reason() -> String:
	# Abandonar a estrada encerra o risco imediato sem prender o salvamento global.
	if data.is_empty() or data.phase!="intercepted" or not is_instance_valid(truck): return ""
	if session.state.region_id!="desert" or not session.state.place_id.is_empty(): return ""
	if truck.global_position.distance_to(session.world.player.global_position)>80: return ""
	for guard in data.guards:
		if not guard.dead: return "Afaste-se da escolta antes de salvar."
	return ""

func write_snapshot() -> void:
	if data.is_empty(): return
	if is_instance_valid(truck):
		var point:=truck.global_position
		if session.world.driving.car==truck and session.world.driving.occupied:
			data.region=session.state.region_id
			truck.set_meta("region_id",session.state.region_id)
		data.position=[point.x,point.y,point.z]
		data.yaw=truck.rotation.y
		data.health=truck.health
		data.distance=clampf(point.x-STATE.START.x,0,STATE.START.distance_to(STATE.END))
	for index in 2:
		var guard=guards[index]
		if is_instance_valid(guard):
			var point: Vector3=guard.global_position
			data.guards[index]={"health":guard.health,"armor":guard.armor,"dead":guard.dead,"position":[point.x,point.y,point.z]}
	_store()

func _store() -> void:
	session.state.world_state[STATE.KEY]=data.duplicate(true)

func cancel_attempt() -> void:
	# Morte/prisão podem ocorrer entre dois ticks; preserve a última baixa.
	# load_game recarrega a cena inteira e não troca state antes deste callback.
	write_snapshot()
	_release()
	_read_saved()
	_admission=.5

func _release_guards() -> void:
	for index in 2:
		if is_instance_valid(guards[index]): guards[index].queue_free()
		guards[index]=null

func _release() -> void:
	_release_guards()
	if is_instance_valid(truck):
		session.controller.vehicles.erase(truck)
		truck.queue_free()
	truck=null

func _exit_tree() -> void:
	_release()

static func _point(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))
