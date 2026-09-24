extends RefCounted
const Definitions := preload("res://activities/ActivityDefinitions.gd")
const Rules := preload("res://systems/economy/ResidenceRules.gd")
const Fleet := preload("res://runtime/FleetCatalog.gd")
var session
var data: Dictionary = Rules.default_state()
var deployed: CharacterBody3D
var hidden: CharacterBody3D

func can_enter(id: String) -> bool:
	return str(data.active_home) == id

func entry(id: String) -> Vector3:
	var source: Dictionary = Definitions.HOMES.PROPERTIES[id]
	return Definitions.at(source.position+source.entrance_offset)

func parking(id: String) -> Vector3:
	var source: Dictionary = Definitions.HOMES.PROPERTIES[id]
	return Definitions.at(source.position+source.extra_vehicle_offset)

func quote(id: String) -> Dictionary:
	return Rules.purchase_quote(Definitions.HOMES.PROPERTIES,data.active_home,id,session.state.economy.balance)

func buy(id: String) -> bool:
	if session.state.region_id != "harbor" or session.world.driving.occupied or session.world.player.position.distance_to(entry(id)) > 4.5: return false
	var offer := quote(id)
	if not offer.get("valid", false) or not offer.get("affordable", false): return false
	var receipt := "residence:%d:%s" % [int(data.purchases)+1,id]
	if not session.state.economy.spend(int(offer.due),receipt): return false
	data = Rules.apply_purchase(data,offer)
	session.state.checkpoint_id = id
	return true

func store_vehicle() -> bool:
	var world = session.world
	if data.active_home == "" or not world.driving.occupied or session.state.region_id != "harbor": return false
	var car = world.driving.car
	if absf(car.speed) > .5 or car.health <= 0 or car.position.distance_to(parking(data.active_home)) > 5.5: return false
	if car.vehicle_id == "story_tow_vehicle" or car.is_in_group("personal_vehicle") or car.has_meta("story_tow_authorized"): return false
	if not data.stored_vehicle.is_empty() and car != deployed: return false
	if Fleet.spec(car.archetype).is_empty(): return false
	if not world.driving.leave(): return false
	data.stored_vehicle = {"archetype_id":car.archetype,"health":car.health,"color":car.paint_color.to_html(),"status":"stored"}
	if car.get_meta("garage_reward",false):
		data.stored_vehicle["garage_id"]=car.vehicle_id
		car.set_meta("garage_stored",true)
	deployed = null
	session.controller.vehicles.erase(car)
	# Keep Driving's current reference valid until it selects another car.
	car.set_physics_process(false)
	car.collision_layer = 0
	car.collision_mask = 0
	car.hide()
	car.remove_from_group("drivable")
	car.position = Vector3(0,-1000,0)
	hidden = car
	return true

func retrieve_vehicle() -> bool:
	if data.active_home == "" or data.stored_vehicle.get("status", "") != "stored" or session.state.region_id != "harbor": return false
	if session.world.driving.occupied or session.world.player.position.distance_to(parking(data.active_home)) > 5.5: return false
	var point := parking(data.active_home)+Vector3.UP*.12
	var id: String = data.stored_vehicle.archetype_id
	if not _clear(id,point): return false
	var car = session.controller.spawn_vehicle(id,point,0.0)
	if not is_instance_valid(car): return false
	car.vehicle_id = "residence_extra"
	_restore_garage_identity(car)
	car.set_meta("residence_vehicle",true)
	car.health = minf(car.max_health,float(data.stored_vehicle.health))
	car.paint_color = Color(data.stored_vehicle.color)
	deployed = car
	data.stored_vehicle.status = "deployed"
	if is_instance_valid(hidden):
		if session.world.driving.car == hidden: session.world.driving.car = car
		hidden.queue_free()
		hidden = null
	return true

func _clear(id: String, point: Vector3, yaw: float = 0.0) -> bool:
	var definition := Fleet.spec(id)
	if definition.is_empty(): return false
	var dimensions: Array = definition.bounds_size
	var size := Vector3(maxf(.65,float(dimensions[0])),clampf(float(dimensions[1]),1.1,3.6),float(dimensions[2]))
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = size + Vector3(.1,0,.1)
	query.shape = box
	query.transform.origin = point+Vector3.UP*size.y*.5
	query.transform.basis = Basis(Vector3.UP,yaw)
	query.collision_mask = 7
	var space = session.world.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty(): return false
	for x in [-1,1]:
		for z in [-1,1]:
			var support := point+Basis(Vector3.UP,yaw)*Vector3(x*size.x*.4,0,z*size.z*.4)
			var ray := PhysicsRayQueryParameters3D.create(support+Vector3.UP*.3,support-Vector3.UP*.4,1)
			if space.intersect_ray(ray).is_empty(): return false
	return true

func snapshot() -> Dictionary:
	if is_instance_valid(deployed) and not data.stored_vehicle.is_empty():
		data.stored_vehicle.health = maxf(0,deployed.health)
		data.stored_vehicle.position = [deployed.position.x,deployed.position.y,deployed.position.z]
		data.stored_vehicle.rotation = deployed.rotation.y
	return data.duplicate(true)

func restore_snapshot(saved: Dictionary) -> bool:
	if not validate_snapshot(saved): return false
	data = saved.duplicate(true)
	data.schema_version = 1
	data.purchases = int(data.purchases)
	return true

static func validate_snapshot(saved: Dictionary) -> bool:
	if not saved.get("active_home") is String or (saved.active_home != "" and not Definitions.HOMES.PROPERTIES.has(saved.active_home)): return false
	if typeof(saved.get("schema_version")) not in [TYPE_INT,TYPE_FLOAT] or float(saved.schema_version) != 1.0: return false
	if typeof(saved.get("purchases")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(saved.purchases)) or float(saved.purchases) < 0 or float(saved.purchases) != floorf(float(saved.purchases)): return false
	if not saved.get("stored_vehicle") is Dictionary: return false
	var car: Dictionary = saved.stored_vehicle
	if car.is_empty(): return true
	if saved.active_home == "" or not car.get("archetype_id") is String or Fleet.spec(car.archetype_id).is_empty(): return false
	if car.get("status") not in ["stored","deployed"] or not car.get("color") is String or not Color.html_is_valid(car.color): return false
	if typeof(car.get("health")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(car.health)) or float(car.health) < 0 or float(car.health) > float(Fleet.spec(car.archetype_id).get("durability",180)): return false
	if car.has("position"):
		if not car.position is Array or car.position.size() != 3: return false
		for value in car.position:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value)) > 100000: return false
	if car.has("rotation") and (typeof(car.rotation) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(car.rotation))): return false
	if car.has("garage_id"):
		var known := {"cobra_boss_ironback":"cobra_boss_ironback"}
		for stock in preload("res://world/places/PortBossStock.gd").definitions(): known[stock.vehicle_id]=stock.archetype
		var guest := false
		if car.garage_id is String and car.garage_id.begins_with("garage_guest_"):
			var suffix: String=car.garage_id.trim_prefix("garage_guest_")
			guest=suffix.is_valid_int() and int(suffix)>0 and int(suffix)<1000000000 and str(int(suffix))==suffix and Fleet.all().has(car.archetype_id)
		if not guest and (not car.garage_id is String or not known.has(car.garage_id) or known[car.garage_id]!=car.archetype_id): return false
	return true

func restore_deployed() -> void:
	if is_instance_valid(deployed) or data.stored_vehicle.get("status", "") != "deployed" or session.state.region_id != "harbor": return
	for candidate in session.controller.vehicles:
		if is_instance_valid(candidate) and candidate.vehicle_id == data.stored_vehicle.get("garage_id","residence_extra"):
			deployed = candidate
			return
	var source: Array = data.stored_vehicle.get("position", [])
	var point := Vector3(float(source[0]),float(source[1]),float(source[2])) if source.size() == 3 else parking(data.active_home)+Vector3.UP*.12
	if point.distance_to(session.world.player.position) > 80: return
	var yaw: float = float(data.stored_vehicle.get("rotation",0.0))
	if not _clear(data.stored_vehicle.archetype_id,point,yaw): return
	var car = session.controller.spawn_vehicle(data.stored_vehicle.archetype_id,point,yaw)
	if not is_instance_valid(car): return
	car.vehicle_id = "residence_extra"
	_restore_garage_identity(car)
	car.set_meta("residence_vehicle",true)
	car.health = minf(car.max_health,float(data.stored_vehicle.health))
	deployed = car
	car.paint_color = Color.html(data.stored_vehicle.color)

func _restore_garage_identity(car) -> void:
	var id: String=data.stored_vehicle.get("garage_id","")
	if id.is_empty(): return
	car.vehicle_id=id
	car.set_meta("garage_reward",true)
	car.set_meta("garage_place","")
	car.set_meta("garage_origin",Vector3.ZERO)
	car.set_meta("garage_stored",false)

func release_garage_vehicle(id: String) -> void:
	if data.stored_vehicle.get("garage_id","")==id:
		data.stored_vehicle={}
		deployed=null
