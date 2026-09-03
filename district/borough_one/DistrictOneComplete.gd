@tool
class_name DistrictOneComplete
extends Node2D

## Composition root for the finished first borough.  Keeping the expansion in
## one scene gives Bairro 2 a single stable hand-off and lets modules be toggled
## independently during visual testing.

const WORLD_BOUNDS := Rect2(0, 0, 2400, 3500)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("district_one_complete")
	call_deferred("_validate_composition")


func _validate_composition() -> void:
	assert(get_node_or_null("Bairro1Expansion") != null, "Bairro 1 layout is missing")
	assert(get_node_or_null("DistrictRailLine") != null, "Bairro 1 railway is missing")
	assert(get_node_or_null("District1HighwayExit") != null, "Bairro 1 viaduct is missing")
	assert(get_node_or_null("Bairro1ProgressionConnections") != null, "Bairro 1 progression exits are missing")
	assert(get_node_or_null("Bairro1CivicServices") != null, "Bairro 1 civic services are missing")
	assert(get_node_or_null("DistrictOnePopulation") != null, "Bairro 1 population is missing")
	var district_exits := _get_bairro_one_exits()
	assert(district_exits.size() == 2, "Bairro 1 must have exactly two future district exits")
	assert(district_exits.has(2) and district_exits.has(3), "Bairro 1 exits must lead to Bairro 2 and Bairro 3")
	print("DISTRICT_ONE_COMPLETE: Bairro 1 complete with exactly two prepared exits (Bairro 2 and Bairro 3)")


func get_district_two_connection() -> Marker2D:
	for node in get_tree().get_nodes_in_group("district_connection"):
		if node is Marker2D and int(node.get_meta("from_district", -1)) == 1:
			return node as Marker2D
	return null


func get_district_three_connection() -> Marker2D:
	for node in get_tree().get_nodes_in_group("district_connection"):
		if node is Marker2D and int(node.get_meta("from_district", -1)) == 1 and int(node.get_meta("to_district", -1)) == 3:
			return node as Marker2D
	return null


func _get_bairro_one_exits() -> Array[int]:
	var destinations: Array[int] = []
	for node in get_tree().get_nodes_in_group("district_connection"):
		if node is Marker2D and int(node.get_meta("from_district", -1)) == 1:
			destinations.append(int(node.get_meta("to_district", -1)))
	return destinations
