extends RefCounted
## Exterior markers are the source of truth; isolated interior rooms are excluded.
const PLACES := {
	"District/Garage/Entrance/OutsideReturn":"Garagem Westgate",
	"District/Police/Entrance/OutsideReturn":"Delegacia do Porto",
	"District/Clinic/Entrance/OutsideReturn":"Hospital Bay Medical",
	"NorthDistrict/MotorWorkshop/Entrance/OutsideReturn":"Oficina Northgate",
	"NorthDistrict/NorthFireStation/Entrance0/OutsideReturn":"Quartel dos Bombeiros",
	"PayNSpray":"Pay 'n' Spray",
	"Cemetery":"Cemitério",
	"ChopShopZone":"Ferro-velho"
}
const ROLES := {"ammunation":"Ammu-Nation","morgue":"Necrotério","bank":"Banco do Porto","fuel":"Posto de combustível","clothing":"Union — Loja de roupas"}
static func collect(world: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for path in PLACES:
		var place := world.get_node_or_null(path) as Node2D
		if place != null: result.append({"id":path,"label":PLACES[path],"position":place.global_position})
	for door in world.get_tree().get_nodes_in_group("harbor_entrance"):
		if not world.is_ancestor_of(door) or not ROLES.has(door.get("role")): continue
		var marker := door.get_node_or_null("OutsideReturn") as Node2D
		if marker != null:
			result.append({"id":str(door.get_path()),"label":ROLES[door.role],"position":marker.global_position})
	for stop in world.get_tree().get_nodes_in_group("urban_bus_stop"):
		result.append({"id":str(stop.get_path()),"label":("Terminal urbano: " if stop.terminal else "Estação: ")+stop.stop_name,"position":stop.global_position})
	return result
