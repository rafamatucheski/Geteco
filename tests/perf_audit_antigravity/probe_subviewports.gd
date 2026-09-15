extends SceneTree
## GETECO-PERF-01-ANTIGRAVITY: Diagnóstico isolado de SubViewports
## Analisa a cena real de HarborGame:
## - Mapeia todos os SubViewports por categoria/proprietário
## - Resolução declarada vs escala final do Sprite2D
## - Modo de atualização configurado (DISABLED, ONCE, WHEN_VISIBLE, ALWAYS)
## - Mundos 3D (own_world_3d), câmeras, luzes, WorldEnvironment, MSAA
## - Mede requisições reais de renderização durante frames ativos

const HARBOR := "res://world/harbor/HarborGame.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requer renderização real")
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	
	# Isola saves
	var saves = root.get_node_or_null("SaveManager")
	if saves:
		saves.set("_save_dir", "res://tests/perf_audit_antigravity/temp_saves/")
		saves.set("_save_directory_ready", false)
		saves.clear_pending_save()

	var campaign = root.get_node_or_null("CampaignState")
	if campaign:
		campaign.reset_campaign()
		for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
			campaign.set_campaign_flag(StringName(flag), true)

	var world = load(HARBOR).instantiate()
	root.add_child(world)
	current_scene = world

	# Aguarda gameplay pronta
	var deadline := Time.get_ticks_msec() + 60000
	while (not world.get("gameplay_ready") or not world.get("world_build_ready")) and Time.get_ticks_msec() < deadline:
		await process_frame

	for i in 60:
		await process_frame

	print("=== INVENTÁRIO DE SUBVIEWPORTS (HARBOR GAME) ===")
	
	var all_vps := root.find_children("*", "SubViewport", true, false)
	print("Total de SubViewports encontrados na árvore: %d" % all_vps.size())

	var categories := {}
	var update_modes := {
		SubViewport.UPDATE_DISABLED: 0,
		SubViewport.UPDATE_ONCE: 0,
		SubViewport.UPDATE_WHEN_VISIBLE: 0,
		SubViewport.UPDATE_ALWAYS: 0
	}
	var own_world_count := 0
	var directional_lights := 0
	var cameras := 0
	var world_envs := 0
	var msaa_count := 0

	for vp in all_vps:
		var s_vp := vp as SubViewport
		var parent = s_vp.get_parent()
		var category := "Desconhecido"

		if parent:
			var p_name : String = parent.name
			var p_script = parent.get_script()
			var s_path : String = p_script.resource_path if p_script else ""

			if s_path.contains("AnimatedPedestrian") or p_name.begins_with("HarborResident") or p_name.begins_with("Walker"):
				category = "Pedestre (AnimatedPedestrian3D)"
			elif s_path.contains("TrafficVehicle") or p_name.begins_with("HarborTraffic") or p_name.begins_with("Traffic"):
				category = "Trânsito (TrafficVehicle)"
			elif s_path.contains("Emergency") or p_name.begins_with("Emergency") or p_name.begins_with("Police"):
				category = "Emergência (EmergencyVehicle)"
			elif s_path.contains("Player") or p_name == "Player":
				category = "Jogador (Player Dante)"
			elif s_path.contains("Collectible") or p_name.begins_with("Collectible"):
				category = "Colecionável (Collectible)"
			elif s_path.contains("FixedTrafficSignal") or p_name.begins_with("SharedSignal3D"):
				category = "Semáforo (FixedTrafficSignal)"
			elif s_path.contains("CobraBurningBarrel") or p_name.begins_with("BurningBarrel"):
				category = "Barril Queimando (CobraBurningBarrel)"
			elif s_path.contains("Cemetery") or p_name.begins_with("Cemetery"):
				category = "Cemitério (CemeteryKeeper/Room)"
			elif s_path.contains("Interior") or p_name.contains("Interior"):
				category = "Interiores (Shops/Rooms)"
			elif parent is SubViewportContainer:
				category = "SubViewportContainer (%s)" % parent.name
			else:
				category = "Outro (%s / %s)" % [p_name, s_path.get_file()]
		
		if not categories.has(category):
			categories[category] = {
				"count": 0,
				"sizes": {},
				"modes": {0: 0, 1: 0, 2: 0, 3: 0},
				"own_world_3d": 0,
				"lights": 0,
				"cameras": 0,
				"envs": 0,
				"msaa": 0
			}

		var cat = categories[category]
		cat.count += 1
		var sz_str := "%dx%d" % [s_vp.size.x, s_vp.size.y]
		cat.sizes[sz_str] = cat.sizes.get(sz_str, 0) + 1
		cat.modes[s_vp.render_target_update_mode] = cat.modes.get(s_vp.render_target_update_mode, 0) + 1
		update_modes[s_vp.render_target_update_mode] += 1

		if s_vp.own_world_3d:
			cat.own_world_3d += 1
			own_world_count += 1
		if s_vp.msaa_3d != Viewport.MSAA_DISABLED:
			cat.msaa += 1
			msaa_count += 1

		for c in s_vp.get_children():
			if c is DirectionalLight3D:
				cat.lights += 1
				directional_lights += 1
			elif c is Camera3D:
				cat.cameras += 1
				cameras += 1
			elif c is WorldEnvironment:
				cat.envs += 1
				world_envs += 1

	print("\n--- DISTRIBUIÇÃO POR CATEGORIA ---")
	for cat_name in categories:
		var c = categories[cat_name]
		print("* %s: total=%d" % [cat_name, c.count])
		print("  Resoluções: %s" % [str(c.sizes)])
		print("  Modos [DISABLED=%d, ONCE=%d, WHEN_VISIBLE=%d, ALWAYS=%d]" % [
			c.modes.get(0, 0), c.modes.get(1, 0), c.modes.get(2, 0), c.modes.get(3, 0)
		])
		print("  own_world_3d=%d, cameras=%d, lights=%d, envs=%d, msaa=%d" % [
			c.own_world_3d, c.cameras, c.lights, c.envs, c.msaa
		])

	print("\n--- TOTAIS GLOBAIS ---")
	print("Modos de atualização na árvore parada:")
	print("  UPDATE_DISABLED (0): %d" % update_modes.get(0, 0))
	print("  UPDATE_ONCE (1): %d" % update_modes.get(1, 0))
	print("  UPDATE_WHEN_VISIBLE (2): %d" % update_modes.get(2, 0))
	print("  UPDATE_ALWAYS (3): %d" % update_modes.get(3, 0))
	print("SubViewports com own_world_3d: %d" % own_world_count)
	print("Câmeras 3D filhas de SubViewports: %d" % cameras)
	print("DirectionalLight3D filhas de SubViewports: %d" % directional_lights)
	print("WorldEnvironment filhos de SubViewports: %d" % world_envs)
	print("SubViewports com MSAA ativo: %d" % msaa_count)

	# Agora vamos inspecionar o HUD e WeaponIcon3D especificamente
	print("\n--- INSPEÇÃO DO HUD / WEAPON ICON ---")
	var weapon_icons := root.find_children("*", "WeaponIcon3D", true, false)
	print("Instâncias de WeaponIcon3D encontradas: %d" % weapon_icons.size())
	for icon in weapon_icons:
		var ctrl := icon as Control
		var has_vp := false
		for c in ctrl.find_children("*", "SubViewport", true, false):
			has_vp = true
		print("  WeaponIcon3D '%s': class=%s, size=%s, possui_subviewport=%s, frameless=%s" % [
			ctrl.get_path(), ctrl.get_class(), ctrl.size, has_vp, ctrl.get("frameless")
		])

	# Mede requisições dinâmicas durante condução real
	print("\n--- MEDIÇÃO DINÂMICA DE RENDERIZAÇÃO (CONDUÇÃO) ---")
	var car : CharacterBody2D = world.get_node_or_null("PlayerCar")
	if car:
		world.call("_drive")
		Input.action_press("ui_up")
		var frames_measured := 120
		var traffic_requests_start := 0
		var ped_requests_start := 0
		
		# Coleta contadores iniciais
		for node in root.find_children("*", "", true, false):
			if "body_render_requests" in node:
				traffic_requests_start += int(node.get("body_render_requests"))
			if "viewport_render_requests" in node:
				ped_requests_start += int(node.get("viewport_render_requests"))

		var per_frame_once_dispatched: Array[int] = []
		for f in frames_measured:
			await process_frame

		Input.action_release("ui_up")

		var traffic_requests_end := 0
		var ped_requests_end := 0
		for node in root.find_children("*", "", true, false):
			if "body_render_requests" in node:
				traffic_requests_end += int(node.get("body_render_requests"))
			if "viewport_render_requests" in node:
				ped_requests_end += int(node.get("viewport_render_requests"))

		var delta_traffic = traffic_requests_end - traffic_requests_start
		var delta_ped = ped_requests_end - ped_requests_start
		print("Em %d frames de condução:" % frames_measured)
		print("  Requisições de render de veículos (TrafficVehicle.UPDATE_ONCE): %d (média %.2f / frame)" % [
			delta_traffic, float(delta_traffic) / frames_measured
		])
		print("  Requisições de render de pedestres (AnimatedPedestrian3D.UPDATE_ONCE): %d (média %.2f / frame)" % [
			delta_ped, float(delta_ped) / frames_measured
		])

	print("\n=== FIM DO DIAGNÓSTICO DE SUBVIEWPORTS ===")
	quit(0)
