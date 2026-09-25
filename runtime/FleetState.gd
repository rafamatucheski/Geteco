extends RefCounted
const FLEET := preload("res://runtime/FleetCatalog.gd")
static func capture(car: CharacterBody3D, region: String) -> Dictionary:
	return {"archetype":car.archetype,"vehicle_id":car.vehicle_id,"was_driven":car.controlled and not car.external_input,"paint":car.paint_color.to_html(true),"position":[car.position.x,car.position.y,car.position.z],"yaw":car.rotation.y,"health":car.health,"region":str(car.get_meta("region_id",region)),"equipment":car.equipment.snapshot() if is_instance_valid(car.equipment) else car.equipment_state.duplicate(true)}
static func validate(data: Dictionary) -> bool:
	if not data.get("archetype") is String or FLEET.spec(data.archetype).is_empty(): return false
	if data.get("region") not in ["harbor","mountain"]: return false
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
		if equipment.siren and data.archetype not in ["police_cruiser","police_suv","police_transport","medic_box","rescue_pumper"]: return false
	return data.health>=0 and data.health<=float(FLEET.spec(data.archetype).get("durability",180))
