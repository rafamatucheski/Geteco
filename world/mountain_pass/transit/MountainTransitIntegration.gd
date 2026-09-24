extends RefCounted
const Layout = preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd")

static func build(mountain: Node2D) -> Node2D:
	var village := preload("res://world/mountain_pass/transit/MountainTransitVillage.gd").new()
	village.name = "MountainTransitVillage"
	mountain.add_child(village)
	var passengers := preload("res://world/mountain_pass/transit/MountainTransitPassengers.gd").new()
	passengers.name = "TransitPassengers"
	village.add_child(passengers)
	_register_door(mountain, village, Layout.SHOP_DOOR, "Casacos da Vila", &"mountain_village_outfitters", true)
	for i in Layout.CABIN_DOORS.size():
		_register_door(mountain, village, Layout.CABIN_DOORS[i], "Chalé %02d" % (i + 1), StringName("mountain_cabin_village_%d" % (i + 1)), false)
	return village

static func _register_door(mountain: Node2D, village: Node2D, point: Vector2, title: String, room: StringName, shop: bool) -> void:
	var door := preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate() as BuildingEntrance
	door.name = "WinterShopEntrance" if shop else "ChaletEntrance%d" % village.get_child_count()
	door.position = point - Layout.ORIGIN
	door.display_name = title
	door.destination_id = room
	if shop: door.add_to_group("clothing_shop")
	door.handle_input_locally = false
	door.show_entrance_marker = false
	door.show_interaction_prompt = false
	village.add_child(door)
	door.get_node("Facade").hide()
	var link := preload("res://world/mountain_pass/transit/MountainVillageInlineDoor.gd").new()
	link.name = "WinterShopInlineDoor" if shop else "ChaletInlineDoor%d" % village.get_child_count()
	link.position = (point - Vector2(0, 46 if shop else 44)) - Layout.ORIGIN
	link.mountain = mountain
	link.village = village
	link.entrance = door
	link.interior_id = room
	village.add_child(link)
