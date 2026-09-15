extends SceneTree
## GETECO-PERF-02A: Inventário Atômico de SubViewports
## Executa uma captura única e consistente de todos os SubViewports da cena viva de HarborGame.
## Garante que a soma das categorias coincida exatamente com os totais globais.

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

	var deadline := Time.get_ticks_msec() + 60000
	while (not world.get("gameplay_ready") or not world.get("world_build_ready")) and Time.get_ticks_msec() < deadline:
		await process_frame

	for i in 60:
		await process_frame

	var all_vps := root.find_children("*", "SubViewport", true, false)
	
	var cat_counts := {}
	var cat_modes := {}
	var cat_resolutions := {}
	var cat_own_worlds := {}
	var cat_cameras := {}
	var cat_lights := {}
	var cat_envs := {}
	var cat_msaa := {}

	var total_disabled := 0
	var total_once := 0
	var total_when_vis := 0
	var total_always := 0
	var total_own_world := 0
	var total_cameras := 0
	var total_lights := 0
	var total_envs := 0
	var total_msaa := 0

	for vp in all_vps:
		var s := vp as SubViewport
		var parent = s.get_parent()
		var cat := "Outro"

		if parent:
			var p_name : String = parent.name
			var p_script = parent.get_script()
			var s_path : String = p_script.resource_path if p_script else ""

			if s_path.contains("AnimatedPedestrian") or p_name.begins_with("HarborResident") or p_name.begins_with("Walker"):
				cat = "Pedestres (AnimatedPedestrian3D)"
			elif s_path.contains("UrbanPassenger") or p_name.begins_with("UrbanCommuter"):
				cat = "Passageiros Ônibus (UrbanPassenger)"
			elif s_path.contains("HarborDockWorker") or p_name.begins_with("SouthDockWorker") or p_name.begins_with("DockOperator"):
				cat = "Trabalhadores Porto (HarborDockWorker)"
			elif s_path.contains("TrafficVehicle") or p_name.begins_with("HarborTraffic") or p_name.begins_with("Traffic") or p_name.ends_with("Coupe"):
				cat = "Trânsito (TrafficVehicle)"
			elif s_path.contains("Emergency") or p_name.begins_with("Emergency") or p_name.begins_with("Police"):
				cat = "Emergência (EmergencyVehicle)"
			elif s_path.contains("Player") or p_name == "Player":
				cat = "Jogador (Player Dante)"
			elif s_path.contains("Collectible") or p_name.begins_with("Collectible"):
				cat = "Colecionáveis (Collectible)"
			elif s_path.contains("FixedTrafficSignal") or p_name.begins_with("SharedSignal3D"):
				cat = "Semáforos (FixedTrafficSignal)"
			elif s_path.contains("CobraBurningBarrel") or p_name.begins_with("BurningBarrel"):
				cat = "Barris (CobraBurningBarrel)"
			elif s_path.contains("UrbanStationView") or p_name.begins_with("NativeStation3D"):
				cat = "Estações de Metrô (UrbanStationView)"
			elif p_name.begins_with("StoneTomb"):
				cat = "Túmulos Cemitério (StoneTomb)"
			elif p_name.begins_with("PortBuilding"):
				cat = "Prédios do Porto (PortBuilding)"
			elif p_name.begins_with("CargoStack3D"):
				cat = "Pilhas de Carga (CargoStack3D)"
			elif p_name.begins_with("SantaMare"):
				cat = "Navio Cargueiro (SantaMare)"
			elif p_name.begins_with("QuaysideCrane3D") or p_name.begins_with("HoistedCargo3D"):
				cat = "Guindastes de Cais (QuaysideCrane3D)"
			elif p_name.begins_with("PortFloodlight"):
				cat = "Refletores do Porto (PortFloodlight)"
			elif s_path.contains("AmmunationBranchView") or s_path.contains("HarborHospital") or s_path.contains("HarborDistrict") or s_path.contains("HarborStorageArt") or s_path.contains("HarborNorthDistrict"):
				cat = "Fachadas e Distritos (Edifícios Estáticos)"
			elif s_path.contains("UrbanBusTrailer"):
				cat = "Ônibus Articulado (UrbanBusTrailer)"

		cat_counts[cat] = cat_counts.get(cat, 0) + 1
		if not cat_modes.has(cat):
			cat_modes[cat] = {0: 0, 1: 0, 2: 0, 3: 0}
			cat_resolutions[cat] = {}
			cat_own_worlds[cat] = 0
			cat_cameras[cat] = 0
			cat_lights[cat] = 0
			cat_envs[cat] = 0
			cat_msaa[cat] = 0

		var mode = s.render_target_update_mode
		cat_modes[cat][mode] = cat_modes[cat].get(mode, 0) + 1
		var res_str := "%dx%d" % [s.size.x, s.size.y]
		cat_resolutions[cat][res_str] = cat_resolutions[cat].get(res_str, 0) + 1

		if mode == 0: total_disabled += 1
		elif mode == 1: total_once += 1
		elif mode == 2: total_when_vis += 1
		elif mode == 3: total_always += 1

		if s.own_world_3d:
			cat_own_worlds[cat] += 1
			total_own_world += 1
		if s.msaa_3d != Viewport.MSAA_DISABLED:
			cat_msaa[cat] += 1
			total_msaa += 1

		for child in s.get_children():
			if child is Camera3D:
				cat_cameras[cat] += 1
				total_cameras += 1
			elif child is DirectionalLight3D:
				cat_lights[cat] += 1
				total_lights += 1
			elif child is WorldEnvironment:
				cat_envs[cat] += 1
				total_envs += 1

	print("=== INVENTÁRIO ATÔMICO DE SUBVIEWPORTS ===")
	print("Total de SubViewports: %d" % all_vps.size())
	print("%-40s | %-5s | %-4s | %-4s | %-4s | %-4s | %-4s | %-4s | %-4s | %-4s | %-4s" % [
		"Categoria", "Total", "DIS", "ONCE", "VIS", "ALW", "3D", "Cam", "Luz", "Env", "MSAA"
	])

	var sum_total := 0
	var sum_dis := 0
	var sum_once := 0
	var sum_vis := 0
	var sum_alw := 0
	var sum_3d := 0
	var sum_cam := 0
	var sum_light := 0
	var sum_env := 0
	var sum_msaa := 0

	for c in cat_counts:
		var cnt : int = cat_counts[c]
		var m = cat_modes[c]
		sum_total += cnt
		sum_dis += m[0]
		sum_once += m[1]
		sum_vis += m[2]
		sum_alw += m[3]
		sum_3d += cat_own_worlds[c]
		sum_cam += cat_cameras[c]
		sum_light += cat_lights[c]
		sum_env += cat_envs[c]
		sum_msaa += cat_msaa[c]

		print("%-40s | %5d | %4d | %4d | %4d | %4d | %4d | %4d | %4d | %4d | %4d" % [
			c, cnt, m[0], m[1], m[2], m[3],
			cat_own_worlds[c], cat_cameras[c], cat_lights[c], cat_envs[c], cat_msaa[c]
		])

	print("-".repeat(95))
	print("%-40s | %5d | %4d | %4d | %4d | %4d | %4d | %4d | %4d | %4d | %4d" % [
		"SOMA DAS CATEGORIAS", sum_total, sum_dis, sum_once, sum_vis, sum_alw,
		sum_3d, sum_cam, sum_light, sum_env, sum_msaa
	])
	print("%-40s | %5d | %4d | %4d | %4d | %4d | %4d | %4d | %4d | %4d | %4d" % [
		"TOTAIS GLOBAIS DIRETOS", all_vps.size(), total_disabled, total_once, total_when_vis, total_always,
		total_own_world, total_cameras, total_lights, total_envs, total_msaa
	])

	quit(0)
