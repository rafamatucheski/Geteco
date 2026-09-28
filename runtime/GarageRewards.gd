extends Node
const STOCK := preload("res://world/places/PortBossStock.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const EXTRA := preload("res://runtime/GarageRewardFleet.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const PORT_ID := "port_garage_stock_2"
const IRONBACK := "cobra_boss_ironback"
var session
var data := {"version":1,"port_status":"parked","alarm_remaining":-1.0,"police_called":false,"vehicles":{}}
var cars: Dictionary = {}
var _clock := 0.0
var _place := ""
var _transition := false
var guards
var press_delivery
## Carro comum em prensagem pelo botão do Neco (o Porto Rosso tem fluxo próprio).
var _scrap_car
var _scrap_layer := 0
## Distância do botão para apertar, a pé.
const BUTTON_REACH := 1.9
## Carro "embaixo" = parado na baia sob o gancho (mesma tolerância da entrega do Porto Rosso).
const BAY_REACH := 52.0/16.0
## Veículos que o Neco não prensa: de história, da casa, de trabalho e de serviço.
const PROTECTED_META := ["garage_reward","residence_vehicle","port_work_vehicle","secret_discovery_vehicle","dispatch_unit"]
const PROTECTED_IDS := ["story_tow_vehicle","neco_tow_truck"]

func configure(owner_session) -> void:
	session=owner_session
	process_mode=Node.PROCESS_MODE_PAUSABLE
	press_delivery=preload("res://runtime/NecoPressDelivery.gd").new()
	add_child(press_delivery)
	press_delivery.finished.connect(_press_finished)
	guards=preload("res://runtime/garage_guards/Guards.gd").new()
	add_child(guards)
	guards.configure(self)
	guards.restore(data.get("guards",[]))
	on_location_changed()

func raise_alarm() -> void:
	if data.police_called or data.alarm_remaining>=0: return
	data.alarm_remaining=15.0
	session.show_message("Segurança alertada · polícia em 15s.")

func can_enter(id: String) -> bool:
	if id!="port_boss_garage": return true
	var hour: float = float(session.state.world_state.get("time",.32))*24.0
	return is_open(hour)
static func is_open(hour: float) -> bool:
	return is_finite(hour) and hour>=1 and hour<5

func _authorized() -> bool:
	var campaign: Dictionary=session.state.campaign.snapshot()
	return session.state.campaign.cobra_status().get("defeated",false) and campaign.completed.has("cobra_finale")

func _physics_process(delta: float) -> void:
	if session==null or not session.ready_for_play or _transition: return
	if not is_finite(delta) or delta<=0: return
	if data.alarm_remaining>0 and not data.police_called:
		data.alarm_remaining=maxf(0,float(data.alarm_remaining)-delta)
		if data.alarm_remaining<=0:
			data.police_called=true
			var gameplay=session.world.gameplay
			gameplay.register_crime(maxi(60,int(gameplay.STAR_THRESHOLDS[3])-int(gameplay.crime_points)),PLACES.get_definition("port_boss_garage").vehicle_return)
			gameplay.dispatch_timer=0
			session.save_game()
	if session.state.place_id!=_place: on_location_changed()
	var driving=session.world.driving
	if driving.occupied and is_instance_valid(driving.car) and driving.car.vehicle_id==PORT_ID and data.port_status=="parked":
		data.port_status="stolen"
		raise_alarm()
		session.save_game()
	if cars.has(PORT_ID) and is_instance_valid(cars[PORT_ID]) and cars[PORT_ID].health<=0 and data.port_status in ["parked","stolen"]:
		data.port_status="destroyed"
		session.save_game()
	if _drive_through_port_exit(driving): return
	_clock+=delta
	if _clock<.5: return
	_clock=0
	_sync()

func _drive_through_port_exit(driving) -> bool:
	if session.state.place_id != "port_boss_garage" or not driving.occupied: return false
	if not session.has_method("transfer_garage_vehicle"): return false
	if session.is_transition_blocked() or session.modal or not is_instance_valid(session.room): return false
	var car = driving.car
	if not is_instance_valid(car) or car.health <= 0 or car.input_locked: return false
	var local: Vector3 = session.room.to_local(car.global_position)
	var outward: Vector3 = session.room.global_basis.inverse() * car.horizontal_velocity
	# Catch the nose before the rear wheels can leave the finite access ramp.
	# Stop first: the existing transfer owns clearance checks and rollback.
	var extent: float = absf(car.global_basis.z.z) * car.half_length + absf(car.global_basis.x.z) * car.half_width
	if absf(local.x) > 3.0 or local.z + extent < 7.65 or outward.z <= .1: return false
	car.speed = 0.0
	car.horizontal_velocity = Vector3.ZERO
	car.velocity = Vector3.ZERO
	_transfer("port_boss_garage",false)
	return true

func on_location_changed() -> void:
	if session==null or _transition or not session.ready_for_play: return
	_capture_all()
	_place=session.state.place_id
	_sync()

func _origin(place: String) -> Vector3:
	if place=="maciota": return session.world.maciota_place.to_global(session.world.maciota_place.interior_origin)
	if place=="port_boss_garage" and is_instance_valid(session.room) and session.state.place_id==place: return session.room.global_position
	return Vector3(0,0,-2400) if not place.is_empty() else Vector3.ZERO

func _initial_record(archetype: String, point: Vector3, yaw: float, place: String) -> Dictionary:
	var spec := _spec(archetype)
	var palette: Array=spec.get("colors",["e01824ff"])
	var paint: String=str(palette.pick_random()) if not palette.is_empty() else "e01824ff"
	return {"archetype":archetype,"region_id":"harbor","place_id":place,"position":[point.x,point.y,point.z],"yaw":yaw,"health":float(spec.get("durability",100)),"paint":paint,"was_driven":false}

func _sync() -> void:
	if session==null or not session.ready_for_play: return
	if session.state.place_id=="port_boss_garage" and not is_instance_valid(session.room): return
	if is_instance_valid(guards): guards.sync()
	if session.state.place_id=="port_boss_garage":
		for source in STOCK.definitions():
			if source.vehicle_id==PORT_ID and data.port_status in ["delivered","destroyed"]: continue
			if not data.vehicles.has(source.vehicle_id): data.vehicles[source.vehicle_id]=_initial_record(source.archetype,source.local_position,source.yaw,"port_boss_garage")
	if _authorized() and not data.vehicles.has(IRONBACK): data.vehicles[IRONBACK]=_initial_record(IRONBACK,Vector3(0,.04,0),-PI,"maciota")
	for id in data.vehicles:
		if id==IRONBACK and not _authorized(): continue
		if id==PORT_ID and data.port_status=="delivered": continue
		var record: Dictionary=data.vehicles[id]
		if _residence_owns(id):
			_bind_existing(id)
			continue
		if record.place_id!=session.state.place_id or record.region_id!=session.state.region_id:
			if cars.has(id) and is_instance_valid(cars[id]): _suspend(cars[id])
			continue
		var point := Vector3(record.position[0],record.position[1],record.position[2])+_origin(record.place_id)
		if record.place_id.is_empty() and point.distance_to(session.world.player.position)>120: continue
		_bind_existing(id)
		var car = cars.get(id)
		if not is_instance_valid(car):
			car=session.controller.spawn_vehicle(record.archetype,point,float(record.yaw),float(record.get("heavy_crush_ratio",1.0)))
			if not is_instance_valid(car): continue
			car.vehicle_id=id
			if id=="personal_monaliza": car.add_to_group("personal_vehicle")
			_restore_damage(car,record)
			car.paint_color=Color.html(record.paint)
			car.set_meta("garage_reward",true)
			car.set_meta("garage_place",record.place_id)
			car.set_meta("garage_origin",_origin(record.place_id))
			car.set_meta("region_id",record.region_id)
			cars[id]=car
			if record.was_driven and session.has_method("restore_garage_driver"):
				_restore_driver(car,record)
		elif car.get_meta("garage_suspended",false):
			if not session.controller.vehicle_position_clear(car,point,float(record.yaw)): continue
			car.place(point,float(record.yaw))
			car.show()
			car.collision_layer=4
			car.collision_mask=7
			car.set_physics_process(true)
			car.remove_meta("garage_suspended")
			car.add_to_group("drivable")
			if not session.controller.vehicles.has(car): session.controller.vehicles.append(car)

func _restore_damage(car: CharacterBody3D, record: Dictionary) -> void:
	car.health=float(record.health)
	var ratio := float(record.get("heavy_crush_ratio",1.0))
	if ratio >= 1.0: return
	preload("res://gameplay/street_physics/HeavyVehicleCrush.gd").apply_saved(car,ratio)
	if car.health <= 0: car.set_meta("heavy_crush_exploded",true)
	car.restore_health(car.health)

func _bind_existing(id: String) -> void:
	for car in session.controller.vehicles:
		if is_instance_valid(car) and car.vehicle_id==id:
			cars[id]=car
			car.set_meta("garage_reward",true)
			if id=="personal_monaliza": car.add_to_group("personal_vehicle")
			return

func _restore_driver(car, record: Dictionary) -> void:
	car.set_meta("garage_driver_pending",true)
	var success: bool=await session.restore_garage_driver(car)
	record.was_driven=false
	if is_instance_valid(car): car.remove_meta("garage_driver_pending")
	if not success: session.show_message("Veículo preservado. A saída está ocupada; você continua a pé.")

func _residence_owns(id: String) -> bool:
	if session.activities==null: return false
	return session.activities.residence.owns_garage_vehicle(id)

func _suspend(car) -> void:
	if session.world.driving.occupied and session.world.driving.car==car: return
	car.hide()
	car.set_physics_process(false)
	car.collision_layer=0
	car.collision_mask=0
	car.remove_from_group("drivable")
	car.set_meta("garage_suspended",true)
	session.controller.vehicles.erase(car)

func _capture_all() -> void:
	if session==null: return
	for id in cars:
		var car=cars[id]
		if not is_instance_valid(car) or car.get_meta("garage_suspended",false) or car.get_meta("garage_stored",false): continue
		if car.get_meta("garage_driver_pending",false): continue
		var place: String=car.get_meta("garage_place","")
		var origin: Vector3=car.get_meta("garage_origin",Vector3.ZERO)
		var point: Vector3=car.global_position-origin
		data.vehicles[id]={"archetype":car.archetype,"region_id":car.get_meta("region_id","harbor"),"place_id":place,"position":[point.x,point.y,point.z],"yaw":car.rotation.y,"health":maxf(0,car.health),"paint":car.paint_color.to_html(true),"was_driven":session.world.driving.occupied and session.world.driving.car==car}
		data.vehicles[id]["heavy_crush_ratio"]=float(car.get_meta("heavy_crush_ratio",1.0))

func nearest_action() -> Dictionary:
	if session==null or _transition: return {}
	var driving=session.world.driving
	if driving.occupied:
		var car=driving.car
		if not is_instance_valid(car) or absf(car.speed)>.5: return {}
		if not _can_register(car): return {}
		if session.state.place_id in ["port_boss_garage","maciota"]:
			var exit: Vector3=_origin("maciota")+Vector3(0,.04,4) if session.state.place_id=="maciota" else session.room.to_global(session.room.definition.vehicle_exit)
			if car.position.distance_to(exit)<4.5: return _action("garage_vehicle_exit","Sair com veículo",exit)
		elif session.state.place_id.is_empty() and session.state.region_id=="harbor":
			for id in ["port_boss_garage","maciota"]:
				var entry: Vector3=session.world.maciota_place.entry_position if id=="maciota" else PLACES.get_definition(id).vehicle_return
				if car.position.distance_to(entry)<6 and can_enter(id): return _action("garage_vehicle_enter:"+id,"Entrar com veículo",entry)
		return {}
	if session.state.place_id=="maciota" and _authorized() and session.world.gameplay.stars==0 and session.state.campaign.active_id.is_empty():
		var bay := _origin("maciota")+Vector3(0,.04,0)
		if session.world.player.position.distance_to(bay)<180.0/16.0:
			var car=cars.get(IRONBACK)
			if is_instance_valid(car) and not car.controlled and car.position.distance_to(bay)<45.0/16.0 and car.health<car.max_health: return _action("ironback_repair","Reparar Ironback",bay)
			if not _residence_owns(IRONBACK): return _action("ironback_recover","Recolher Ironback à baia",bay)
	if _porto_deliverable(): return _action("porto_deliver","Entregar Porto Rosso · R$ 50.000",cars[PORT_ID].position)
	var yard := _neco_yard()
	if yard != null and session.world.player.global_position.distance_to(yard.button_point()) < BUTTON_REACH:
		var car = _car_on_bay(yard)
		var label := "Acionar prensa"
		if car != null and _scrappable(car): label = "Acionar prensa · R$ %d" % scrap_value(car)
		return _action("neco_press",label,yard.button_point())
	return {}

## Pátio do Neco carregado (o chunk pode estar fora do streaming).
func _neco_yard() -> Node3D:
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty() or session.world.driving.occupied: return null
	for button in get_tree().get_nodes_in_group("neco_press_button"):
		var yard := (button as Node).get_parent() as Node3D
		if yard != null and yard.has_method("button_point"): return yard
	return null

## Carro parado na baia, sob o gancho do guindaste.
func _car_on_bay(yard: Node3D):
	var best = null
	var best_distance := BAY_REACH
	for body in get_tree().get_nodes_in_group("drivable"):
		if not is_instance_valid(body) or body.is_queued_for_deletion() or not body.visible: continue
		var distance: float = Vector2(body.global_position.x-yard.dock_point().x,body.global_position.z-yard.dock_point().z).length()
		if distance < best_distance:
			best = body
			best_distance = distance
	return best

func _scrappable(car) -> bool:
	if car.vehicle_id == PORT_ID or car.vehicle_id in PROTECTED_IDS: return false
	for key in PROTECTED_META:
		if car.get_meta(key,false): return false
	return car.health > 0 and not car.controlled and absf(car.speed) <= .5

## V1 ChopShopZone._reward: 450 + 3 por pixel de comprimento (16 px por metro).
static func scrap_value(car) -> int:
	return 450 + roundi(float(car.half_length) * 2.0 * 16.0 * 3.0)

func _press_scrap(yard: Node3D) -> bool:
	yard.press_button()
	var car = _car_on_bay(yard)
	if car == null:
		session.show_message("Pare um carro na baia, embaixo do gancho, e aperte o botão.")
		return true
	if car.vehicle_id == PORT_ID:
		if _porto_deliverable(): return _deliver_porto()
		session.show_message("Esse carro é encomenda do chefe do porto; fale com o Neco.")
		return true
	if not _scrappable(car):
		session.show_message("O Neco não prensa esse veículo." if car.health > 0 else "Carcaça queimada não vale sucata.")
		return true
	if session.world.gameplay.stars > 0:
		session.show_message("Com a polícia atrás de você, o Neco não liga a prensa.")
		return true
	if session.activities == null or session.activities.salvage_available() <= 0:
		session.show_message("A prensa já trabalhou demais hoje. Volte amanhã.")
		return true
	# A prensa só começa com a área de admissão livre de corpos; o carro sai da física
	# durante a apresentação (ela esconde o casco e usa uma cópia das malhas).
	_scrap_car = car
	_scrap_layer = car.collision_layer
	_transition = true
	if not press_delivery.begin(car):
		_transition = false
		_scrap_car = null
		session.show_message("Libere a área da prensa e tente de novo.")
		return true
	car.collision_layer = 0
	return true

func _action(id: String,label: String,point: Vector3) -> Dictionary:
	return {"id":"garage_reward","target":id,"label":label,"position":point}

func perform(id: String) -> bool:
	if id.is_empty() or nearest_action().get("target","")!=id: return false
	if id.begins_with("garage_vehicle_enter:"):
		_transfer(id.trim_prefix("garage_vehicle_enter:"),true)
		return true
	if id=="garage_vehicle_exit": _transfer(session.state.place_id,false); return true
	if id=="porto_deliver": return _deliver_porto()
	if id=="neco_press":
		var yard := _neco_yard()
		return _press_scrap(yard) if yard != null else false
	if id=="ironback_recover": return _recover_ironback()
	if id=="ironback_repair":
		cars[IRONBACK].repair()
		session.save_game()
		return true
	return false

func _transfer(place: String, entering: bool) -> void:
	if not session.has_method("transfer_garage_vehicle"): session.show_message("Acesso de veículos indisponível."); return
	var car=session.world.driving.car
	_transition=true
	var success: bool=await session.transfer_garage_vehicle(place,car,entering)
	if success and is_instance_valid(car):
		car.set_meta("garage_place",session.state.place_id)
		car.set_meta("garage_origin",_origin(session.state.place_id))
		car.set_meta("region_id",session.state.region_id)
		register_guest(car)
	_transition=false
	on_location_changed()
	if success: session.save_game()

func _can_register(car) -> bool:
	if not is_instance_valid(car): return false
	if cars.get(car.vehicle_id)==car and data.vehicles.has(car.vehicle_id): return true
	if car.get_meta("residence_vehicle",false) or car.has_meta("story_tow_authorized") or car.is_in_group("personal_vehicle") or car.vehicle_id in ["story_tow_vehicle","neco_tow_truck"]: return false
	if _spec(car.archetype).is_empty() or car.archetype==IRONBACK: return false
	var count := 0
	for id in data.vehicles:
		if is_guest_id(id): count+=1
	return count<64

func register_guest(car) -> bool:
	if not _can_register(car): return false
	if cars.get(car.vehicle_id)==car and data.vehicles.has(car.vehicle_id): return true
	var serial := 1
	for id in data.vehicles:
		if is_guest_id(id): serial=maxi(serial,int(str(id).trim_prefix("garage_guest_"))+1)
	var id := "garage_guest_%d"%serial
	car.vehicle_id=id
	cars[id]=car
	data.vehicles[id]=_initial_record(car.archetype,car.position,car.rotation.y,session.state.place_id)
	car.set_meta("garage_place",session.state.place_id)
	car.set_meta("garage_origin",_origin(session.state.place_id))
	car.set_meta("region_id",session.state.region_id)
	car.set_meta("garage_reward",true)
	_capture_all()
	session.state.world_state.vehicles=[]
	return true

static func is_guest_id(id: Variant) -> bool:
	if not id is String or not id.begins_with("garage_guest_"): return false
	var suffix: String=id.trim_prefix("garage_guest_")
	return suffix.is_valid_int() and int(suffix)>0 and int(suffix)<1000000000 and str(int(suffix))==suffix

func _porto_deliverable() -> bool:
	if data.port_status!="stolen" or session.state.region_id!="harbor" or not session.state.place_id.is_empty() or session.world.driving.occupied or session.world.gameplay.stars>0: return false
	var car=cars.get(PORT_ID)
	if not is_instance_valid(car) or car.health<=0 or car.controlled or absf(car.speed)>.5 or car.get_meta("garage_stored",false): return false
	if session.activities==null or session.activities.salvage_available()<=0: return false
	var bay: Vector3=session.mission_world.targets.neco_bay
	return car.position.distance_to(bay)<52.0/16.0 and session.world.player.position.distance_to(car.position)<90.0/16.0

func _deliver_porto() -> bool:
	if _transition or not _porto_deliverable(): return false
	_transition=true
	if not press_delivery.begin(cars[PORT_ID]):
		_transition=false
		session.show_message("Libere a área da prensa para entregar o veículo.")
		return false
	return true

func cancel_press_delivery() -> void:
	if is_instance_valid(press_delivery): press_delivery.cancel()

func _press_finished(completed: bool) -> void:
	_transition=false
	if _scrap_car != null:
		_finish_scrap(completed)
		return
	if completed:
		if _porto_deliverable(): _commit_porto_delivery()
		elif data.port_status=="stolen": session.show_message("Entrega interrompida. O veículo foi preservado na baia.")

func _finish_scrap(completed: bool) -> void:
	var car = _scrap_car
	_scrap_car = null
	if not is_instance_valid(car): return
	if not completed:
		car.collision_layer = _scrap_layer
		session.show_message("Prensa interrompida. O carro ficou na baia.")
		return
	var reward := scrap_value(car)
	var wallet: Dictionary = session.state.economy.snapshot()
	if not session.state.economy.grant_reward(session.activities.salvage_receipt("neco_scrap"),reward) or not session.activities.record_external_delivery():
		session.state.economy.restore_snapshot(wallet)
		car.collision_layer = _scrap_layer
		session.show_message("O Neco não conseguiu pagar agora. O carro ficou na baia.")
		return
	# Remoção deliberada: se era o último carro dirigido, Driving/ProductionWorld
	# soltam a referência e o snapshot do veículo do jogador.
	car.queue_free()
	session.show_message("Neco pagou R$ %d pela sucata." % reward)
	session.save_game()

func _commit_porto_delivery() -> bool:
	if data.port_status!="stolen": return false
	var wallet: Dictionary=session.state.economy.snapshot()
	if not session.state.economy.grant_reward("port_boss_porto_rosso",50000): return false
	if not session.activities.record_external_delivery(): session.state.economy.restore_snapshot(wallet); return false
	data.port_status="delivered"
	session.activities.residence.release_garage_vehicle(PORT_ID)
	var car=cars[PORT_ID]
	_retain_delivered_body(car)
	data.vehicles.erase(PORT_ID)
	cars.erase(PORT_ID)
	session.show_message("Neco pagou R$ 50.000.")
	session.save_game()
	return true

func _retain_delivered_body(car) -> void:
	_suspend(car)
	car.vehicle_id="delivered_porto_rosso"
	car.set_meta("garage_stored",true)

func _recover_ironback() -> bool:
	if not _authorized() or _residence_owns(IRONBACK): return false
	var record: Dictionary=data.vehicles.get(IRONBACK,{})
	if record.is_empty(): return false
	var car=cars.get(IRONBACK)
	if is_instance_valid(car) and car.controlled: return false
	var bay := _origin("maciota")+Vector3(0,.04,0)
	if not is_instance_valid(car):
		car=session.controller.spawn_vehicle(IRONBACK,bay,-PI,float(record.get("heavy_crush_ratio",1.0)))
		if not is_instance_valid(car): return false
		car.vehicle_id=IRONBACK
		_restore_damage(car,record)
		car.paint_color=Color.html(record.paint)
		car.set_meta("garage_reward",true)
		cars[IRONBACK]=car
	elif not session.controller.vehicle_position_clear(car,bay,-PI): return false
	car.place(bay,-PI)
	car.set_meta("garage_place","maciota")
	car.set_meta("garage_origin",_origin("maciota"))
	car.set_meta("region_id","harbor")
	car.remove_meta("garage_suspended")
	car.show()
	car.set_physics_process(true)
	car.collision_layer=4
	car.collision_mask=7
	car.add_to_group("drivable")
	if not session.controller.vehicles.has(car): session.controller.vehicles.append(car)
	_capture_all()
	session.save_game()
	return true

func snapshot() -> Dictionary:
	_capture_all()
	if is_instance_valid(guards): data.guards=guards.snapshot()
	return data.duplicate(true)
func restore_snapshot(saved: Dictionary) -> bool:
	if not validate_snapshot(saved): return false
	cancel_press_delivery()
	data=saved.duplicate(true)
	if is_instance_valid(guards): guards.restore(data.get("guards",[]))
	return true
static func _spec(id: String) -> Dictionary:
	return EXTRA.spec(id) if id==IRONBACK else FLEET.spec(id)
static func validate_snapshot(saved: Dictionary) -> bool:
	if not preload("res://runtime/garage_guards/Guards.gd").validate(saved.get("guards",[])): return false
	if saved.get("version")!=1 or saved.get("port_status") not in ["parked","stolen","delivered","destroyed"] or not saved.get("police_called") is bool or not saved.get("vehicles") is Dictionary: return false
	var timer: Variant=saved.get("alarm_remaining")
	if typeof(timer) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(timer)) or timer < -1 or timer > 15: return false
	if saved.police_called and timer!=0: return false
	var known := {IRONBACK:IRONBACK,"personal_monaliza":"monaliza"}
	for stock in STOCK.definitions(): known[stock.vehicle_id]=stock.archetype
	var guests := 0
	var drivers := 0
	for id in saved.vehicles:
		var record: Variant=saved.vehicles[id]
		if is_guest_id(id):
			guests+=1
			if guests>64 or not record is Dictionary or not record.get("archetype") is String or not FLEET.all().has(record.archetype): return false
			known[id]=record.archetype
		if not known.has(id): return false
		if not record is Dictionary or record.get("archetype")!=known[id] or record.get("region_id") not in ["harbor","mountain"] or record.get("place_id") not in ["","maciota","port_boss_garage"]: return false
		if not record.place_id.is_empty() and record.region_id!="harbor": return false
		if not record.get("was_driven") is bool or not record.get("paint") is String or not Color.html_is_valid(record.paint): return false
		if record.was_driven:
			drivers+=1
			if drivers>1: return false
		if not record.get("position") is Array or record.position.size()!=3: return false
		for value in record.position:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value))>10000: return false
		for key in ["yaw","health"]:
			if typeof(record.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(record[key])): return false
		if record.health<0 or record.health>float(_spec(record.archetype).get("durability",100)): return false
		if record.has("heavy_crush_ratio"):
			var ratio: Variant=record.heavy_crush_ratio
			if typeof(ratio) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(ratio)): return false
			if float(ratio)!=1.0 and (float(ratio)<0.18 or float(ratio)>0.55): return false
	if saved.port_status=="delivered" and saved.vehicles.has(PORT_ID): return false
	return true
