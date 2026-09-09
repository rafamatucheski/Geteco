extends SceneTree

## Gate de integração do Codex para a entrega V3 do Claude. Mantido fora da
## pasta do dono do layout para não alterar sua implementação durante a QA.

const REQUIRED_MARKERS := [
	"PlayerSpawn", "TerminalStop", "PortApproach", "MarketEntrance", "ParkEntrance",
	"GarageEntrance", "PaintSprayEntrance", "CobraEntrance", "CemeteryIMLEntrance",
	"RailUnderpass", "ExitDistrict2", "WarehouseEntrance", "ExitDistrict3",
]

var _exit_code := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://legacy/district/bairro1_v2/layout/LayoutV2.tscn") as PackedScene
	if scene == null:
		_fail("LayoutV2.tscn não carregou")
		quit(_exit_code)
		return
	var layout: Node2D = scene.instantiate() as Node2D
	root.add_child(layout)
	for _frame in range(20):
		await process_frame

	assert(layout.get("debug_show_route_guides") == false, "Guias técnicos devem iniciar ocultos")
	var markers_holder: Node2D = layout.get_node_or_null("Markers") as Node2D
	if markers_holder == null:
		_fail("Nó Markers ausente")
	else:
		for marker_name: String in REQUIRED_MARKERS:
			var marker: Marker2D = markers_holder.get_node_or_null(marker_name) as Marker2D
			if marker == null:
				_fail("Marcador ausente: %s" % marker_name)

	var road_network: Node2D = layout.get_node_or_null("RoadNetwork") as Node2D
	if road_network == null:
		print("INFO: Blockout V5 intentionally has no traffic network yet")
	else:
		var errors: Array = []
		if road_network.has_method("get_validation_errors"):
			errors = road_network.call("get_validation_errors") as Array
		else:
			var raw_errors: Variant = road_network.get("_validation_errors")
			if raw_errors is Array:
				errors = raw_errors as Array
		if not errors.is_empty():
			_fail("Malha viária possui avisos: %s" % errors)

	var lots: Array = layout.call("get_buildable_lots") as Array
	var alleys: Dictionary = layout.call("get_alley_definitions") as Dictionary
	if lots.size() != 12:
		_fail("Esperados 12 lotes construíveis; encontrados %d" % lots.size())
	if alleys.size() != 5:
		_fail("Esperados 5 becos; encontrados %d" % alleys.size())

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1067)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview_scene: Node2D = scene.instantiate() as Node2D
	viewport.add_child(preview_scene)
	var camera := Camera2D.new()
	camera.position = Vector2(1200, 800)
	camera.zoom = Vector2(0.62, 0.62)
	viewport.add_child(camera)
	camera.make_current()
	for _frame in range(10):
		await process_frame
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Driver headless não forneceu imagem; validar captura no renderer do editor")
	else:
		var save_error := image.save_png("res://../artifacts/layout_v3_clean_capture.png")
		if save_error != OK:
			_fail("Falha ao salvar captura: %d" % save_error)

	if _exit_code == 0:
		print("LAYOUT_V3_GATE_PASSED: artifacts/layout_v3_clean_capture.png")
	else:
		print("LAYOUT_V3_GATE_FAILED")
	quit(_exit_code)


func _fail(message: String) -> void:
	printerr("FALHA: ", message)
	_exit_code = 1
