extends SceneTree

## Marco 1: valida a composição de autoria independente em coordenadas reais.
## Layout/landmarks continuam donos de seus arquivos; este teste pertence à
## integração e só verifica os contratos públicos deles.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://legacy/district/bairro1_v2/Bairro1V2.tscn") as PackedScene
	assert(scene != null, "Bairro1V2 must load")
	var district := scene.instantiate()
	root.add_child(district)
	for _frame in range(20):
		await process_frame

	var layout := district.get_node_or_null("LayoutV2") as Node2D
	var landmarks := district.get_node_or_null("LandmarksV2") as Node2D
	var port := district.get_node_or_null("PortMarkedCarSet") as Node2D
	assert(layout != null, "LayoutV2 must be integrated")
	assert(landmarks != null, "LandmarksV2 must be integrated")
	assert(port != null, "Preserved port must be integrated")

	var port_approach := district.call("get_marker", &"PortApproach") as Marker2D
	assert(port_approach != null, "PortApproach marker must exist")
	var expected_port_access := Vector2(3340, 2470)
	assert(port_approach.global_position.distance_to(expected_port_access) < 0.1, "Layout port approach must meet the port west access")

	for marker_name in [&"PlayerSpawn", &"MarketEntrance", &"TerminalStop", &"ParkEntrance", &"GarageEntrance", &"WarehouseEntrance", &"RailUnderpass", &"ExitDistrict2", &"ExitDistrict3"]:
		assert(district.call("get_marker", marker_name) != null, "Required marker missing: %s" % marker_name)

	assert(landmarks.call("get_all_landmarks").size() >= 8, "Landmarks must build from integrated markers")
	assert(landmarks.call("get_all_alleys").size() == 3, "Three authored alleys must be integrated")
	print("Bairro1V2 Marco 1 integration passed")
	quit(0)
