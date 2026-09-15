extends RefCounted
const Layout = preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd")

static func build(mountain: Node2D) -> Node2D:
	var village := preload("res://world/mountain_pass/transit/MountainTransitVillage.gd").new()
	village.name = "MountainTransitVillage"
	mountain.add_child(village)
	var passengers := preload("res://world/mountain_pass/transit/MountainTransitPassengers.gd").new()
	passengers.name = "TransitPassengers"
	village.add_child(passengers)
	_register_door(mountain, village, Layout.SHOP_DOOR, "Casacos da Vila", &"mountain_outfitters", true)
	for i in Layout.CABIN_DOORS.size():
		_register_door(mountain, village, Layout.CABIN_DOORS[i], "Chalé %02d" % (i + 1), &"mountain_cabin", false)
	return village

static func _register_door(mountain: Node2D, village: Node2D, point: Vector2, title: String, room: StringName, shop: bool) -> void:
	var door := preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate() as BuildingEntrance
	door.name = "WinterShopEntrance" if shop else "ChaletEntrance%d" % village.get_child_count()
	door.position = point - Layout.ORIGIN
	door.display_name = title
	door.destination_id = room
	if shop: door.add_to_group("clothing_shop")
	village.add_child(door)
	door.get_node("Facade").hide()
	mountain.interior_manager.register_exterior_entrance(door, room, door.global_position + Vector2(0, 24))
