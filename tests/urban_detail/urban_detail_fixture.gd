extends SceneTree

## Visual demonstration fixture and showcase for Urban Detail 3D architecture.
## Displays all reconstructed building typologies and transit models side by side
## with realistic street staging for visual inspection and FPS measurement by the integrator.

const SAMPLE_FRAMES := 180
var frame_times: Array[float] = []
var sampling := false
var showcase_root: Node3D

func _initialize() -> void:
	call_deferred("setup_showcase")

func setup_showcase() -> void:
	print("--- Setting up Urban Detail 3D Showcase Fixture ---")
	
	showcase_root = Node3D.new()
	showcase_root.name = "UrbanShowcase"
	root.add_child(showcase_root)
	
	# Sunlight and ambient environment (subtle, non-shadow-heavy)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(-0.85, 0.65, 0)
	sun.light_color = Color("fff7e6")
	sun.light_energy = 1.15
	showcase_root.add_child(sun)
	
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("687a82")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("90a0a8")
	env.ambient_light_energy = 0.55
	env_node.environment = env
	showcase_root.add_child(env_node)
	
	# Ground Plane
	var ground := MeshInstance3D.new()
	ground.name = "ShowcaseGround"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(250, 250)
	ground.mesh = ground_mesh
	ground.material_override = UrbanMaterials.sidewalk_stone()
	showcase_root.add_child(ground)
	
	var factory = preload("res://world/urban_detail/UrbanBuildingFactory.gd")
	
	# Showcase lineup of archetypes with spacing along X/Z grid
	var lineup: Array[Dictionary] = [
		{
			"id": "FoundryTerraceShowcase", "kind": "rowhouse_terrace", "name": "Foundry Terraces",
			"size": Vector2(13.1, 14.3), "color": "#7c463b", "grid_pos": Vector3(-50, 0, -30)
		},
		{
			"id": "CommercialTowerShowcase", "kind": "office", "name": "Exchange Tower",
			"size": Vector2(18.7, 20.0), "color": "#83c6cc", "grid_pos": Vector3(-20, 0, -30)
		},
		{
			"id": "CornerDinerShowcase", "kind": "corner_shop", "name": "Anchor Diner",
			"size": Vector2(13.1, 10.0), "color": "#e49d68", "grid_pos": Vector3(10, 0, -30)
		},
		{
			"id": "LaundryShowcase", "kind": "commercial_laundromat", "name": "Wash & Dry",
			"size": Vector2(10.6, 9.3), "color": "#4a8084", "grid_pos": Vector3(35, 0, -30)
		},
		{
			"id": "ArtisanWorkshopShowcase", "kind": "artisan_workshop", "name": "Harbor Bindery",
			"size": Vector2(12.1, 10.2), "color": "#825a47", "grid_pos": Vector3(-50, 0, 10)
		},
		{
			"id": "WarehouseShowcase", "kind": "warehouse", "name": "Cold Storage",
			"size": Vector2(26.2, 17.5), "color": "#78afb6", "grid_pos": Vector3(-15, 0, 10)
		},
		{
			"id": "FireStationShowcase", "kind": "fire_station", "name": "Northgate Fire",
			"size": Vector2(19.3, 13.7), "color": "#d97958", "grid_pos": Vector3(25, 0, 10)
		},
		{
			"id": "PolicePrecinctShowcase", "kind": "police_precinct", "name": "Harbor Patrol",
			"size": Vector2(11.8, 15.6), "color": "#68a8d3", "grid_pos": Vector3(55, 0, 10)
		},
		{
			"id": "MotorWorkshopShowcase", "kind": "garage", "name": "Motor Workshop",
			"size": Vector2(16.8, 13.1), "color": "#6bd2b2", "grid_pos": Vector3(-45, 0, 50)
		},
		{
			"id": "CobraBungalowShowcase", "kind": "cobra_house", "name": "Porch House",
			"size": Vector2(13.7, 10.0), "color": "#72594b", "grid_pos": Vector3(-15, 0, 50)
		},
		{
			"id": "LShapedLoftsShowcase", "kind": "l_shaped_block", "name": "Union Lofts",
			"size": Vector2(11.6, 16.2), "color": "#8b6e58", "grid_pos": Vector3(15, 0, 50)
		}
	]
	
	for item in lineup:
		var b_data := item.duplicate()
		b_data["position"] = item.grid_pos
		var building = factory.build_building(b_data)
		if building != null:
			showcase_root.add_child(building)
			factory.finalize_building(building, b_data)
	
	# Transit Models
	var tube_stop := UrbanStationModel3D.new()
	tube_stop.name = "TubeStopShowcase"
	tube_stop.position = Vector3(45, 0, 45)
	showcase_root.add_child(tube_stop)
	tube_stop.build(0.0, false)
	
	# Camera setup with good viewing angle
	var cam := Camera3D.new()
	cam.name = "ShowcaseCamera"
	cam.position = Vector3(0, 32, 85)
	cam.rotation = Vector3(-0.42, 0, 0)
	showcase_root.add_child(cam)
	
	print("Urban Detail Showcase ready. 11 Building Archetypes + Transit Station placed.")
	print("Starting frame time sampling window (%d frames)..." % SAMPLE_FRAMES)
	
	# Warm up for 10 frames before sampling
	for i in 10:
		await process_frame
	
	# Sample frame times
	for i in SAMPLE_FRAMES:
		var start_usec := Time.get_ticks_usec()
		await process_frame
		var delta_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
		frame_times.append(delta_ms)
	
	_report_performance_metrics()

func _report_performance_metrics() -> void:
	if frame_times.is_empty():
		return
	
	var sorted_times := frame_times.duplicate()
	sorted_times.sort()
	
	var sum_ms := 0.0
	for t in sorted_times:
		sum_ms += t
	
	var count := sorted_times.size()
	var mean_ms: float = sum_ms / float(count)
	var min_ms: float = sorted_times[0]
	var max_ms: float = sorted_times[-1]
	var median_ms: float = sorted_times[int(count * 0.50)]
	var p95_ms: float = sorted_times[int(count * 0.95)]
	var p99_ms: float = sorted_times[int(count * 0.99)]
	var approx_fps: float = 1000.0 / maxf(mean_ms, 0.001)
	
	print("==================================================")
	print("   URBAN DETAIL PERFORMANCE SAMPLING REPORT       ")
	print("==================================================")
	print(" Sample Window : %d frames" % count)
	print(" Mean Frame    : %.2f ms (approx %.1f FPS)" % [mean_ms, approx_fps])
	print(" Median Frame  : %.2f ms" % median_ms)
	print(" Min Frame     : %.2f ms" % min_ms)
	print(" Max Frame     : %.2f ms (stall threshold >33.3ms: %s)" % [max_ms, "EXCEEDED" if max_ms > 33.3 else "CLEAR"])
	print(" 95th Percentile: %.2f ms" % p95_ms)
	print(" 99th Percentile: %.2f ms" % p99_ms)
	print(" Target Check  : %s" % ["PASS (>= 60 FPS profile)" if mean_ms <= 16.67 else "PASS (>= 30 FPS profile)" if mean_ms <= 33.33 else "INVESTIGATE"])
	print("==================================================")
