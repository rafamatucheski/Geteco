@tool
class_name DistrictOneComplete
extends Node2D

## Composition root for the finished first borough.  Keeping the expansion in
## one scene gives Bairro 2 a single stable hand-off and lets modules be toggled
## independently during visual testing.

const WORLD_BOUNDS := Rect2(0, 0, 4960, 3700)

const PORT_SCENE := preload("res://missions/district_one/PortMarkedCarSet.tscn")
const PORT_POSITION := Vector2(3340, 2150)


func _ready() -> void:
	# O porto (PortMarkedCarSet.tscn) já tem @tool e já trata
	# Engine.is_editor_hint() por dentro (chão, água, cercas, armazéns,
	# contêineres, guindaste, guarita etc. -- tudo desenhado/preparado pra
	# aparecer no editor). O problema era que essa chamada só rodava DEPOIS
	# do "return" abaixo, ou seja, o nó do porto nunca chegava a ser criado
	# fora do Play: por isso ele nunca aparecia nem no DistrictOneComplete
	# nem no Main abertos no editor. _ensure_port() não cria duplicata (já
	# verifica get_node_or_null antes), então é seguro chamar tanto no
	# editor quanto em jogo.
	_ensure_port()
	if Engine.is_editor_hint():
		return
	add_to_group("district_one_complete")
	call_deferred("_validate_composition")


func _ensure_port() -> void:
	var port = get_node_or_null("PortMarkedCarSet")
	if port == null and PORT_SCENE != null:
		port = PORT_SCENE.instantiate()
		port.name = "PortMarkedCarSet"
		port.position = PORT_POSITION
		add_child(port)


func _validate_composition() -> void:
	assert(get_node_or_null("Bairro1Expansion") != null, "Bairro 1 layout is missing")
	assert(get_node_or_null("DistrictRailLine") != null, "Bairro 1 railway is missing")
	assert(get_node_or_null("District1HighwayExit") != null, "Bairro 1 viaduct is missing")
	assert(get_node_or_null("UnifiedRoadNetwork") != null, "Bairro 1 canonical road graph is missing")
	assert(get_node_or_null("JunctionTrafficController") != null, "Bairro 1 junction controller is missing")
	assert(get_node_or_null("DistrictRoadSafetySystem") != null, "Bairro 1 road safety system is missing")
	assert(get_node_or_null("Bairro1ProgressionConnections") != null, "Bairro 1 progression exits are missing")
	assert(get_node_or_null("Bairro1CivicServices") != null, "Bairro 1 civic services are missing")
	assert(get_node_or_null("PortMarkedCarSet") != null, "Bairro 1 port is missing")
	assert(get_node_or_null("DistrictOnePopulation") != null, "Bairro 1 population is missing")
	var district_exits := _get_bairro_one_exits()
	assert(district_exits.size() == 2, "Bairro 1 must have exactly two future district exits")
	assert(district_exits.has(2) and district_exits.has(3), "Bairro 1 exits must lead to Bairro 2 and Bairro 3")
	assert(_get_rail_handoffs().size() == 1, "Bairro 1 must expose exactly one rail handoff")
	print("DISTRICT_ONE_COMPLETE: Bairro 1 complete with exactly two prepared exits (Bairro 2 and Bairro 3) and PortMarkedCarSet")


func get_district_two_connection() -> Marker2D:
	for node in get_tree().get_nodes_in_group("district_connection"):
		if _is_road_connection(node) and int(node.get_meta("to_district", -1)) == 2:
			return node as Marker2D
	return null


func get_district_three_connection() -> Marker2D:
	for node in get_tree().get_nodes_in_group("district_connection"):
		if _is_road_connection(node) and int(node.get_meta("to_district", -1)) == 3:
			return node as Marker2D
	return null


func _get_bairro_one_exits() -> Array[int]:
	var destinations: Array[int] = []
	for node in get_tree().get_nodes_in_group("district_connection"):
		if _is_road_connection(node):
			destinations.append(int(node.get_meta("to_district", -1)))
	return destinations


func _get_rail_handoffs() -> Array[Marker2D]:
	var handoffs: Array[Marker2D] = []
	for node in get_tree().get_nodes_in_group("rail_district_connection"):
		if node is Marker2D and int(node.get_meta("from_district", -1)) == 1:
			handoffs.append(node as Marker2D)
	return handoffs


func _is_road_connection(node: Node) -> bool:
	if not node is Marker2D or int(node.get_meta("from_district", -1)) != 1:
		return false
	return String(node.get_meta("transport_mode", "road")) != "rail" \
		and String(node.get_meta("connection_type", "road")) != "rail"
