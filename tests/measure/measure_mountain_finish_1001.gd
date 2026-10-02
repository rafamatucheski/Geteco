extends SceneTree
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
const EXIT_SCRIPT = preload("res://gameplay/urban_v1/fort/MountainFortExit3D.gd")
const PAD_SCRIPT = preload("res://assets/regions/source/world/mountain_pass/MountainHelipad3D.gd")
const LIFT_SCRIPT = preload("res://world/environmental_parity/MountainChairliftParity3D.gd")
var world
var reports: Array[Dictionary] = []
var folder := "D:/geteco/artifacts/mountain-review-1001/site-performance"
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
func script_from(path: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path).replace("class_name MountainChairliftParity3D", "")
	var err := script.reload()
	if err != OK: push_error("Cannot load baseline "+path); quit(1)
	return script
func place(point: Vector3) -> void:
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	world.production.region.set_focus(point)
	world.player.teleport(point+Vector3.UP*.04)
	world.camera.global_position = point+Vector3(0,34,24)
	world.camera.look_at(point)
	await frames(120)
	for i in 1800:
		await process_frame
		if world.production.region.pending.is_empty(): break
func sample(site: String, variant: String) -> void:
	var warm := Time.get_ticks_usec()
	while Time.get_ticks_usec()-warm<5000000: await process_frame
	var values: Array[float] = []
	var began := Time.get_ticks_usec()
	var previous := began
	while Time.get_ticks_usec()-began<30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		values.append(float(now-previous)/1000.0)
		previous=now
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for v in values:
		total+=v
		if v>33.3: over33+=1
		if v>66.7: over66+=1
	var report := {"site":site,"variant":variant,"frames":values.size(),"duration_ms":total,"fps":values.size()*1000.0/total,"p50_ms":sorted[int((sorted.size()-1)*.5)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over33":over33,"over66":over66,"samples_ms":values}
	reports.append(report)
	var file := FileAccess.open(folder.path_join(site+"-"+variant+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	report.erase("samples_ms")
	print("MOUNTAIN_SITE_PERF ",JSON.stringify(report))
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(folder)
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	world.production.set_process(false)
	world.player.set_physics_process(false)
	world.camera.set_process(false)
	world.camera.set_process_unhandled_input(false)
	world.camera.locked=true
	world.camera.size=36
	world.camera.make_current()
	world.hud.hide()
	world.session.weather.time_of_day=.5
	world.session.weather.weather_state=0
	world.session.weather._update()
	world.session.weather.set_process(false)
	var old_exit := script_from("D:/geteco/artifacts/MountainFortExit3D.before.gd")
	var old_pad := script_from("D:/geteco/artifacts/MountainHelipad3D.before.gd")
	var old_lift := script_from("D:/geteco/artifacts/mountain-review-1001/MountainChairliftParity3D.before.gd")
	for site in ["hideout","helipad","lift_north"]:
		var center := Vector3(753.25,0,-487) if site=="hideout" else (Vector3(659.8,0,-487) if site=="helipad" else Vector3(712.5,0,-615.625))
		await place(center)
		var original: Node3D
		if site=="hideout": original=world.session.urban_operations.secret_passage.ski_exit
		elif site=="helipad": original=world.production.region.find_child("MountainHelipad",true,false)
		else:
			for node in world.production.region.find_children("*","Node3D",true,false):
				if node.get_script()==LIFT_SCRIPT: original=node; break
		if original==null: push_error("Site missing "+site); quit(1); return
		var parent := original.get_parent()
		var transform := original.transform
		# Only the changed object is swapped; final background, weather and population
		# are common to both variants. This isolates geometry/placement runtime cost.
		original.free()
		for variant in ["before","after"]:
			var script = (old_exit if site=="hideout" else (old_pad if site=="helipad" else old_lift)) if variant=="before" else (EXIT_SCRIPT if site=="hideout" else (PAD_SCRIPT if site=="helipad" else LIFT_SCRIPT))
			var object: Node3D=script.new()
			if site!="hideout": object.transform=transform
			if site=="helipad" and variant=="before": object.position=Vector3(-10.3125,0,5.9375)
			parent.add_child(object)
			if site=="hideout":
				object.configure(world.session)
				object.activate_now()
				world.session.urban_operations.secret_passage.ski_exit=object
			await sample(site,variant)
			object.free()
		var restored: Node3D=(EXIT_SCRIPT if site=="hideout" else (PAD_SCRIPT if site=="helipad" else LIFT_SCRIPT)).new()
		restored.transform=transform
		parent.add_child(restored)
		if site=="hideout":
			restored.configure(world.session)
			restored.activate_now()
			world.session.urban_operations.secret_passage.ski_exit=restored
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"comparison":"Original and revised object in the same final production background; controlled geometry and placement comparison, not original full-world replay.","scenarios":reports}
	var file := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	quit()
