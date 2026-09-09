extends SceneTree

## Teste headless + captura limpa do LayoutV2 (planta V3), isolado (sem
## Bairro1V2/landmarks/gameplay -- este script só toca district/bairro1_v2/layout/).
## Uso: godot --headless --path <projeto> --script res://legacy/district/bairro1_v2/layout/capture_layout_v3.gd
## Sai com código 0 em sucesso, != 0 se algum contrato falhar.

const REQUIRED_MARKERS := [
	"PlayerSpawn", "TerminalStop", "PortApproach", "MarketEntrance", "ParkEntrance",
	"GarageEntrance", "PaintSprayEntrance", "CobraEntrance", "CemeteryIMLEntrance",
	"RailUnderpass", "ExitDistrict2", "WarehouseEntrance", "ExitDistrict3",
]

var _exit_code := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== LayoutV2 (V3) -- teste headless + captura limpa ===")
	var scene: PackedScene = load("res://legacy/district/bairro1_v2/layout/LayoutV2.tscn")
	if scene == null:
		printerr("FALHA: não carregou LayoutV2.tscn")
		quit(1)
		return
	var layout: Node2D = scene.instantiate() as Node2D
	root.add_child(layout)
	# window_set_size não muda o tamanho real de captura em modo headless;
	# o que importa é o tamanho do próprio Viewport raiz.
	root.size = Vector2i(1920, 1080)

	for f in range(15):
		await process_frame

	# [1] flag de debug desligada por padrão
	var debug_flag: bool = layout.get("debug_show_route_guides")
	print("[1] debug_show_route_guides (deve ser false): ", debug_flag)
	if debug_flag:
		_fail("debug_show_route_guides não está desligada por padrão")

	# [2] marcadores obrigatórios presentes
	var markers_holder: Node2D = layout.get_node_or_null("Markers") as Node2D
	if markers_holder == null:
		_fail("nó Markers ausente")
	else:
		for marker_name in REQUIRED_MARKERS:
			var marker: Marker2D = markers_holder.get_node_or_null(marker_name) as Marker2D
			if marker == null:
				_fail("marcador ausente: " + marker_name)
	print("[2] marcadores publicados: ", markers_holder.get_child_count() if markers_holder else 0, " / ", REQUIRED_MARKERS.size(), " obrigatórios")

	# [3] rede de ruas sem avisos de endpoint desconectado
	var road_network: Node2D = layout.get_node_or_null("RoadNetwork") as Node2D
	if road_network == null:
		_fail("nó RoadNetwork ausente")
	else:
		var errors: Array = []
		if road_network.has_method("get_validation_errors"):
			errors = road_network.call("get_validation_errors")
		else:
			var raw = road_network.get("_validation_errors")
			if raw != null:
				errors = raw
		print("[3] avisos de validação da malha viária: ", errors.size())
		for e in errors:
			print("    - ", e)
		if errors.size() > 0:
			_fail("malha viária com endpoints desconectados não sinalizados")

	# [4] lotes construíveis e becos publicados
	var lots: Array = layout.call("get_buildable_lots")
	var alleys: Dictionary = layout.call("get_alley_definitions")
	print("[4] lotes construíveis: ", lots.size(), " | becos pedestres: ", alleys.size())
	if alleys.size() != 5:
		_fail("esperado 5 becos pedestres, encontrado %d" % alleys.size())

	# [5] captura limpa (sem overlays de debug), aguardando frames de composição
	for f in range(20):
		await process_frame

	var camera := Camera2D.new()
	camera.name = "QACamera"
	camera.position = Vector2(1200, 800)
	# Em stretch mode "canvas_items" a área visível é calculada sobre a
	# resolução de design do projeto (1280x720, não root.size), dividida
	# pelo zoom. Para caber o distrito inteiro (2400x1600) com folga: 0.40.
	camera.zoom = Vector2(0.30, 0.30)
	root.add_child(camera)
	camera.make_current()

	for f in range(10):
		await process_frame

	var image := root.get_texture().get_image()
	var out_path := "res://../artifacts/layout_v3_clean_capture.png"
	var err := image.save_png(out_path)
	if err != OK:
		_fail("falha ao salvar captura: erro %d" % err)
	else:
		print("VISUAL_QA_IMAGE: ", out_path)

	if _exit_code == 0:
		print("=== SUCESSO: contrato do LayoutV2 (V3) validado ===")
	else:
		print("=== FALHA: ver mensagens acima ===")
	quit(_exit_code)

func _fail(message: String) -> void:
	printerr("FALHA: ", message)
	_exit_code = 1
