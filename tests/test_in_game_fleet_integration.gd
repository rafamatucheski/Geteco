@tool
extends SceneTree

const TRAFFIC_VEHICLE := preload("res://city_demo/scripts/TrafficVehicle.gd")
const HARBOR_LIFE := preload("res://district/harbor_preview/HarborLife.gd")
const PREVIEW_PATH := "res://district/harbor_preview/HarborPreview.tscn"

var failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("  [FALHA] " + message)
	else:
		print("  [OK] " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("\n=======================================================")
	print("=== TESTE DE INTEGRAÇÃO IN-GAME DA FROTA 3D & DANTE ===")
	print("=======================================================\n")

	# --- 1. PROPORÇÃO & ESCALA ANATÔMICA DO DANTE ---
	print("--- 1. Proporção e Escala do Dante ---")
	var player_script = load("res://Player.gd")
	var player = CharacterBody2D.new()
	player.set_script(player_script)
	var cam = Camera2D.new()
	cam.name = "Camera"
	player.add_child(cam)
	root.add_child(player)
	await process_frame

	_check(player.sprite_3d_display != null, "Dante deve possuir sprite_3d_display")
	if player.sprite_3d_display:
		var s: Vector2 = player.sprite_3d_display.scale
		_check(is_equal_approx(s.x, 0.24) and is_equal_approx(s.y, 0.24),
			"Escala do sprite do Dante deve ser 0.24 (obtido: %s)" % str(s))

		# Com viewport 128x128 e escala 0.24, tamanho total na tela é ~30.7px
		var visual_h: float = 128.0 * s.y
		_check(visual_h >= 28.0 and visual_h <= 34.0,
			"Altura visual do Dante deve estar entre 28px e 34px para casar com 74px do carro (obtido: %.1fpx)" % visual_h)

	# --- 2. TRAFFICVEHICLE COM SUPORTE A MODELOS 3D PROCEDURAIS ---
	print("\n--- 2. TrafficVehicle com Suporte a Modelos 3D ---")
	var tv_3d = TRAFFIC_VEHICLE.new()
	root.add_child(tv_3d)
	tv_3d.apply_archetype("union_sedan", Color("#34495e"))

	_check(tv_3d.is_3d_vehicle, "Veículo de tráfego com union_sedan deve ser is_3d_vehicle")
	_check(tv_3d.body_viewport != null, "Veículo 3D deve possuir body_viewport instanciado")
	_check(tv_3d.body_model != null, "Veículo 3D deve possuir body_model instanciado")
	_check(tv_3d.visual.texture == tv_3d.body_viewport.get_texture(), "Visual deve usar textura do SubViewport")
	_check(tv_3d.spinners.size() >= 4, "Veículo 3D deve possuir spinners de roda configurados")

	# Teste de retrocompatibilidade com veículo 2D clássico (sedan_classic)
	var tv_2d = TRAFFIC_VEHICLE.new()
	root.add_child(tv_2d)
	tv_2d.apply_archetype("sedan_classic")
	_check(not tv_2d.is_3d_vehicle, "sedan_classic deve manter is_3d_vehicle == false para retrocompatibilidade 2D")

	# --- 3. AMBIENT TRAFFIC EM HARBORLIFE ---
	print("\n--- 3. Tráfego Circulante em HarborLife ---")
	_check(HARBOR_LIFE.CAR_TYPES.has("union_sedan"), "HarborLife deve incluir union_sedan no tráfego")
	_check(HARBOR_LIFE.CAR_TYPES.has("metro_hatch"), "HarborLife deve incluir metro_hatch no tráfego")
	_check(HARBOR_LIFE.CAR_TYPES.has("courier_van"), "HarborLife deve incluir courier_van no tráfego")
	_check(HARBOR_LIFE.CAR_TYPES.has("route_city"), "HarborLife deve incluir route_city no tráfego")

	# --- 4. ESTACIONAMENTOS TEMÁTICOS EM HARBORPREVIEW ---
	print("\n--- 4. Estacionamentos Temáticos em HarborPreview ---")
	var packed := load(PREVIEW_PATH) as PackedScene
	var scene := packed.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene

	for _f in 6:
		await physics_frame

	var manager = scene.get_node_or_null("Interiors")
	var fire_station = manager.get("fire_station_interior") if manager else null
	_check(fire_station != null, "fire_station_interior deve existir")
	if fire_station:
		var bay_truck = fire_station.bay_trucks[0]
		_check(bay_truck != null and bay_truck.get("is_3d_vehicle") == true,
			"Caminhão do corpo de bombeiros deve ser 3D (rescue_pumper)")
		_check(bay_truck.get("active_archetype_id") == "rescue_pumper",
			"Caminhão dos bombeiros deve usar arquétipo rescue_pumper")

	var thematic_fleet = scene.get_node_or_null("ThematicFleet")
	_check(thematic_fleet != null, "ThematicFleet deve existir em HarborPreview")
	if thematic_fleet:
		var clinic_amb = thematic_fleet.get_node_or_null("ClinicAmbulance")
		_check(clinic_amb != null and clinic_amb.get("active_archetype_id") == "medic_box",
			"Ambulância medic_box deve estar estacionada na clínica")

		var tow_truck = thematic_fleet.get_node_or_null("WorkshopTowTruck")
		_check(tow_truck != null and tow_truck.get("active_archetype_id") == "towmaster",
			"Guincho towmaster deve estar estacionado na oficina")

		var courier = thematic_fleet.get_node_or_null("FreightCourierVan")
		_check(courier != null and courier.get("active_archetype_id") == "courier_van",
			"Furgão courier_van deve estar estacionado no depósito de cargas")

		var ranch = thematic_fleet.get_node_or_null("PortRanchPickup")
		_check(ranch != null and ranch.get("active_archetype_id") == "ranch_single",
			"Pickup ranch_single deve estar estacionada nas docas")

	scene.queue_free()

	# --- 5. VALIDAÇÃO DIRETA NA CENA HARBORGAME.TSCN ---
	print("\n--- 5. Validação Direta da Cena Principal HarborGame.tscn ---")
	var game_packed := load("res://district/harbor_preview/HarborGame.tscn") as PackedScene
	var game_scene := game_packed.instantiate() as Node2D
	root.add_child(game_scene)
	current_scene = game_scene

	for _f in 6:
		await physics_frame

	var game_player = game_scene.get_node_or_null("Player")
	_check(game_player != null, "HarborGame deve conter o Player")
	if game_player and game_player.sprite_3d_display:
		var s: Vector2 = game_player.sprite_3d_display.scale
		_check(is_equal_approx(s.x, 0.24), "Player em HarborGame deve ter escala proporcional 0.24")

	var game_fleet = game_scene.get_node_or_null("ThematicFleet")
	_check(game_fleet != null, "HarborGame deve herdar ThematicFleet com todos os veículos temáticos")
	if game_fleet:
		_check(game_fleet.has_node("ClinicAmbulance"), "HarborGame deve conter ClinicAmbulance (medic_box)")
		_check(game_fleet.has_node("WorkshopTowTruck"), "HarborGame deve conter WorkshopTowTruck (towmaster)")
		_check(game_fleet.has_node("FreightCourierVan"), "HarborGame deve conter FreightCourierVan (courier_van)")
		_check(game_fleet.has_node("PortRanchPickup"), "HarborGame deve conter PortRanchPickup (ranch_single)")

	var game_interiors = game_scene.get_node_or_null("Interiors")
	var game_fire = game_interiors.get("fire_station_interior") if game_interiors else null
	_check(game_fire != null and game_fire.bay_trucks[0].get("is_3d_vehicle") == true,
		"HarborGame deve conter caminhões de bombeiro 3D rescue_pumper no batalhão")

	# Limpeza
	player.queue_free()
	tv_3d.queue_free()
	tv_2d.queue_free()
	game_scene.queue_free()

	print("\n-------------------------------------------------------")
	if failures.is_empty():
		print(">>> SUCESSO TOTAL: TODOS OS SISTEMAS VALIDADOS COM 100% DE ÊXITO! <<<")
		quit(0)
	else:
		printerr(">>> FALHAS DETECTADAS (%d): %s <<<" % [failures.size(), str(failures)])
		quit(1)
