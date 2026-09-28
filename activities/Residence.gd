extends RefCounted
const Definitions := preload("res://activities/ActivityDefinitions.gd")
const Rules := preload("res://systems/economy/ResidenceRules.gd")
const Fleet := preload("res://runtime/FleetCatalog.gd")
var session
var data: Dictionary = Rules.default_state()
var deployed: CharacterBody3D
var hidden: CharacterBody3D
var deployed_motorcycle: CharacterBody3D
var hidden_motorcycle: CharacterBody3D
const PARKING := preload("res://world/places/ResidenceParking.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const STORAGE := preload("res://runtime/ResidenceStorage.gd")
var _definitions: Dictionary = {}
var _storing := false

func _definition(id: String) -> Dictionary:
	if not _definitions.has(id): _definitions[id] = PLACES.get_definition(id)
	return _definitions[id]

func _record(slot: String) -> Dictionary:
	return data.stored_motorcycle if slot == "motorcycle" else data.stored_vehicle

func _deployed(slot: String) -> CharacterBody3D:
	return deployed_motorcycle if slot == "motorcycle" else deployed

func vehicle_slot(archetype: String) -> String:
	return "motorcycle" if Fleet.spec(archetype).get("vehicle_kind","") == "motorcycle" else "car"

func can_enter(id: String) -> bool:
	return str(data.active_home) == id

func entry(id: String) -> Vector3:
	return _definition(id).get("entry_position",Vector3.INF)

func parking(id: String, slot := "car") -> Vector3:
	var definition := _definition(id)
	return definition.exterior_position + PARKING.offset(slot,int(definition.variant)).rotated(Vector3.UP,float(definition.get("editor_rotation",0)))

func parking_yaw() -> float:
	return float(_definition(data.active_home).get("editor_rotation",0))

func quote(id: String) -> Dictionary:
	return Rules.purchase_quote(Definitions.HOMES.PROPERTIES,data.active_home,id,session.state.economy.balance)

func buy(id: String) -> bool:
	if not Definitions.HOMES.PROPERTIES.has(id) or session.world.gameplay.health <= 0: return false
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
	if _storing or world.driving.is_body_transition_active(): return false
	if data.active_home == "" or not world.driving.occupied or session.state.region_id != "harbor": return false
	var car = world.driving.car
	if not is_instance_valid(car) or world.gameplay.health <= 0 or not session.state.place_id.is_empty(): return false
	var slot := vehicle_slot(car.archetype)
	var record := _record(slot)
	if absf(car.speed) > .5 or car.health <= 0 or car.position.distance_to(parking(data.active_home,slot)) > 4.5: return false
	if car.vehicle_id == "story_tow_vehicle" or car.is_in_group("personal_vehicle") or car.has_meta("story_tow_authorized"): return false
	if not record.is_empty() and car != _deployed(slot): return false
	if Fleet.spec(car.archetype).is_empty(): return false
	var bounds: Array = Fleet.spec(car.archetype).bounds_size
	if float(bounds[0]) > 2.7 or float(bounds[1]) > 2.65 or float(bounds[2]) > 6.8: return false
	if not world.driving.leave(): return false
	_storing = true
	# Leave() starts the real door/body animation; do not move its vehicle anchor.
	while is_instance_valid(car) and world.driving.is_body_transition_active():
		await world.get_tree().physics_frame
	_storing = false
	if not is_instance_valid(car) or world.driving.occupied or world.gameplay.health <= 0: return false
	record.clear()
	record.merge({"archetype_id":car.archetype,"health":car.health,"color":car.paint_color.to_html(),"status":"stored"})
	if car.get_meta("garage_reward",false):
		record["garage_id"]=car.vehicle_id
		car.set_meta("garage_stored",true)
	if slot == "motorcycle": deployed_motorcycle = null
	else: deployed = null
	car.set_meta("residence_vehicle",true)
	# Retire this car's exterior snapshot so loading cannot duplicate a stored car.
	var saved_vehicles: Array = session.state.world_state.get("vehicles",[])
	session.state.world_state.vehicles = saved_vehicles.filter(func(saved): return saved.get("vehicle_id","") != car.vehicle_id)
	session.controller.vehicles.erase(car)
	# Keep Driving's current reference valid until it selects another car.
	car.set_physics_process(false)
	car.collision_layer = 0
	car.collision_mask = 0
	car.hide()
	car.remove_from_group("drivable")
	car.position = Vector3(0,-1000,0)
	if slot == "motorcycle": hidden_motorcycle = car
	else: hidden = car
	return true

func retrieve_vehicle(slot := "car") -> bool:
	if slot not in ["car","motorcycle"]: return false
	var record := _record(slot)
	if data.active_home == "" or record.get("status", "") != "stored" or session.state.region_id != "harbor": return false
	if not session.state.place_id.is_empty() or session.world.gameplay.health <= 0: return false
	if session.world.driving.occupied or session.world.player.position.distance_to(parking(data.active_home,slot)) > 5.5: return false
	var point := parking(data.active_home,slot)+Vector3.UP*.12
	var id: String = record.archetype_id
	var yaw := parking_yaw()
	if not _clear(id,point,yaw): return false
	var car = session.controller.spawn_vehicle(id,point,yaw)
	if not is_instance_valid(car): return false
	car.vehicle_id = "residence_motorcycle" if slot == "motorcycle" else "residence_extra"
	_restore_garage_identity(car,record)
	car.set_meta("residence_vehicle",true)
	car.health = minf(car.max_health,float(record.health))
	car.paint_color = Color(record.color)
	if slot == "motorcycle": deployed_motorcycle = car
	else: deployed = car
	record.status = "deployed"
	var parked: CharacterBody3D = hidden_motorcycle if slot == "motorcycle" else hidden
	if is_instance_valid(parked):
		if session.world.driving.car == parked: session.world.driving.car = car
		parked.queue_free()
	if slot == "motorcycle": hidden_motorcycle = null
	else: hidden = null
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
	for slot in ["car","motorcycle"]:
		var car := _deployed(slot)
		var record := _record(slot)
		if is_instance_valid(car) and not record.is_empty():
			record.health = maxf(0,car.health)
			record.position = [car.position.x,car.position.y,car.position.z]
			record.rotation = car.rotation.y
	return data.duplicate(true)

func restore_snapshot(saved: Dictionary) -> bool:
	if not validate_snapshot(saved): return false
	data = saved.duplicate(true)
	if not data.has("stored_motorcycle"): data.stored_motorcycle = {}
	if not data.has("chest"): data.chest = {}
	# V1/V2 originally had one unrestricted slot, which could contain a bike.
	if not data.stored_vehicle.is_empty() and vehicle_slot(data.stored_vehicle.archetype_id) == "motorcycle" and data.stored_motorcycle.is_empty():
		data.stored_motorcycle = data.stored_vehicle
		data.stored_vehicle = {}
	data.schema_version = 1
	data.purchases = int(data.purchases)
	return true

static func validate_snapshot(saved: Dictionary) -> bool:
	if not saved.get("active_home") is String or (saved.active_home != "" and not Definitions.HOMES.PROPERTIES.has(saved.active_home)): return false
	if typeof(saved.get("schema_version")) not in [TYPE_INT,TYPE_FLOAT] or float(saved.schema_version) != 1.0: return false
	if typeof(saved.get("purchases")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(saved.purchases)) or float(saved.purchases) < 0 or float(saved.purchases) != floorf(float(saved.purchases)): return false
	if not STORAGE.validate_chest(saved.get("chest",{})): return false
	if not _validate_vehicle(saved.get("stored_vehicle"),saved.active_home): return false
	if not _validate_vehicle(saved.get("stored_motorcycle",{}),saved.active_home): return false
	var bike: Dictionary = saved.get("stored_motorcycle",{})
	if not bike.is_empty() and Fleet.spec(bike.archetype_id).get("vehicle_kind","") != "motorcycle": return false
	if not bike.is_empty() and not saved.stored_vehicle.is_empty() and Fleet.spec(saved.stored_vehicle.archetype_id).get("vehicle_kind","") == "motorcycle": return false
	return true

static func _validate_vehicle(saved_vehicle: Variant, active_home: String) -> bool:
	if not saved_vehicle is Dictionary: return false
	var car: Dictionary = saved_vehicle
	if car.is_empty(): return true
	if active_home == "" or not car.get("archetype_id") is String or Fleet.spec(car.archetype_id).is_empty(): return false
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
	for slot in ["car","motorcycle"]: _restore_slot(slot)

func _restore_slot(slot: String) -> void:
	var record := _record(slot)
	if is_instance_valid(_deployed(slot)) or record.get("status", "") != "deployed" or session.state.region_id != "harbor": return
	var vehicle_id: String = record.get("garage_id","residence_motorcycle" if slot == "motorcycle" else "residence_extra")
	for candidate in session.controller.vehicles:
		if is_instance_valid(candidate) and candidate.vehicle_id == vehicle_id:
			if slot == "motorcycle": deployed_motorcycle = candidate
			else: deployed = candidate
			return
	var source: Array = record.get("position", [])
	var point := Vector3(float(source[0]),float(source[1]),float(source[2])) if source.size() == 3 else parking(data.active_home,slot)+Vector3.UP*.12
	if point.distance_to(session.world.player.position) > 80: return
	var yaw: float = float(record.get("rotation",parking_yaw()))
	if not _clear(record.archetype_id,point,yaw): return
	var car = session.controller.spawn_vehicle(record.archetype_id,point,yaw)
	if not is_instance_valid(car): return
	car.vehicle_id = vehicle_id
	_restore_garage_identity(car,record)
	car.set_meta("residence_vehicle",true)
	car.health = minf(car.max_health,float(record.health))
	if slot == "motorcycle": deployed_motorcycle = car
	else: deployed = car
	car.paint_color = Color.html(record.color)

func _restore_garage_identity(car, record: Dictionary) -> void:
	var id: String=record.get("garage_id","")
	if id.is_empty(): return
	car.vehicle_id=id
	car.set_meta("garage_reward",true)
	car.set_meta("garage_place","")
	car.set_meta("garage_origin",Vector3.ZERO)
	car.set_meta("garage_stored",false)

func release_garage_vehicle(id: String) -> void:
	for slot in ["car","motorcycle"]:
		if _record(slot).get("garage_id","") == id:
			_record(slot).clear()
			if slot == "motorcycle": deployed_motorcycle = null
			else: deployed = null

func owns_garage_vehicle(id: String) -> bool:
	return not id.is_empty() and (data.stored_vehicle.get("garage_id","") == id or data.stored_motorcycle.get("garage_id","") == id)
