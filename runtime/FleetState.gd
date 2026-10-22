extends RefCounted
const FLEET := preload("res://runtime/FleetCatalog.gd")
static func capture(car: CharacterBody3D, region: String) -> Dictionary:
	var result := {"archetype":car.archetype,"vehicle_id":car.vehicle_id,"was_driven":car.controlled and not car.external_input,"paint":car.paint_color.to_html(true),"position":[car.position.x,car.position.y,car.position.z],"yaw":car.rotation.y,"health":car.health,"region":str(car.get_meta("region_id",region)),"equipment":car.equipment.snapshot() if is_instance_valid(car.equipment) else car.equipment_state.duplicate(true),"punctured_tires":int(car.get_meta("punctured_tires",0)),"heavy_crush_ratio":float(car.get_meta("heavy_crush_ratio",1.0))}
	if car.has_method("fleet_snapshot_extras"): result.merge(car.fleet_snapshot_extras())
	result["body_dents"] = car.body_dents.snapshot() if is_instance_valid(car.body_dents) else []
	result["broken_glass"] = car.snapshot_glass() if car.has_method("snapshot_glass") else []
	result["breakaway_parts"] = car.breakaway_parts.snapshot() if is_instance_valid(car.breakaway_parts) else {}
	result["blood_stains"] = int(car.get_meta("blood_stains",0))
	return result
static func validate(data: Dictionary) -> bool:
	if not preload("res://gameplay/vehicle_effects/VehicleBlood.gd").valid(data.get("blood_stains",0)): return false
	if not preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").valid_records(data.get("body_dents",[])): return false
	if not preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").valid_records(data.get("broken_glass",[])): return false
	if not preload("res://gameplay/vehicle_effects/VehicleBreakawayParts.gd").valid_state(data.get("breakaway_parts",{})): return false
	if data.has("bus_work"):
		if data.get("archetype","")!="biarticulated_510" or not data.bus_work is Dictionary: return false
		for field in ["next_stop","stops","earned","laps"]:
			var value: Variant=data.bus_work.get(field)
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)!=floorf(float(value)) or float(value)<0 or float(value)>100000000: return false
	if data.has("articulation"):
		if data.get("archetype","")!="biarticulated_510" or not data.articulation is Array or data.articulation.size()!=2: return false
		var previous := 0.0
		for angle in data.articulation:
			if typeof(angle) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(angle)) or absf(float(angle))>PI or absf(angle_difference(previous,float(angle)))>deg_to_rad(55.1): return false
			previous=float(angle)
	if data.has("heavy_crush_ratio"):
		var ratio: Variant = data.heavy_crush_ratio
		if typeof(ratio) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(ratio)): return false
		if float(ratio) != 1.0 and (float(ratio) < 0.18 or float(ratio) > 0.55): return false
	if data.has("punctured_tires"):
		var tires: Variant = data.punctured_tires
		if typeof(tires) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(tires)) or float(tires) != floorf(float(tires)) or tires < 0 or tires > 4: return false
	if not data.get("archetype") is String or FLEET.spec(data.archetype).is_empty(): return false
	if data.get("region") not in ["harbor","mountain","desert"]: return false
	if data.has("paint") and (not data.paint is String or not Color.html_is_valid(data.paint)): return false
	if data.has("vehicle_id") and (not data.vehicle_id is String or data.vehicle_id.length()>128): return false
	if data.has("was_driven") and not data.was_driven is bool: return false
	if not data.get("position") is Array or data.position.size()!=3: return false
	for value in data.position:
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value))>10000: return false
	for key in ["yaw","health"]:
		if typeof(data.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data[key])): return false
	var equipment: Variant = data.get("equipment",{})
	if not equipment is Dictionary: return false
	if not equipment.is_empty():
		if not equipment.get("headlights") is bool or not equipment.get("siren") is bool: return false
		if equipment.siren and data.archetype not in ["police_cruiser","police_suv","police_transport","bike_police","medic_box","rescue_pumper"]: return false
	return data.health>=0 and data.health<=float(FLEET.spec(data.archetype).get("durability",180))
