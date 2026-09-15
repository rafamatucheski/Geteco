extends "res://world/mountain_pass/WinterResidentModel.gd"
var winter_outfit := false

func _ready() -> void:
	coat_color = Color("577995") if role=="bus_driver" else Color("ac6737")
	if winter_outfit: coat_color = coat_color.darkened(.15)
	preload("res://characters/pedestrians/WinterWardrobe.gd").build(self,winter_outfit)

static func role_for(vehicle: Node2D) -> String:
	var id := String(vehicle.get("vehicle_id"))
	if id=="route_city" or "bus" in id: return "bus_driver"
	if "truck" in id or id in ["boxrunner","towmaster"]: return "truck_driver"
	return ""

static func is_winter(vehicle: Node2D) -> bool:
	if VehicleCatalog.get_vehicle_spec(String(vehicle.get("vehicle_id"))).get("district","")=="winter": return true
	var ancestor: Node = vehicle
	while ancestor:
		if ancestor.get_meta("mountain_traffic",false) or ancestor is MountainPass: return true
		ancestor=ancestor.get_parent()
	return false
