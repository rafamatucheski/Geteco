extends SceneTree
## Finite production-geometry overview. This inspection does not measure gameplay FPS.
const REGION := preload("res://world/editing/EditableDesertRegion.gd")
const L := preload("res://world/desert/DesertLayout.gd")
var region: Node3D

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("COMPACT_OVERVIEW timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var output := "res://evidence/desert-compact-overview-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1800,1100)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("a6afb0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("e2d2b3")
	environment.environment.ambient_light_energy = .7
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-32,0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	stage.add_child(sun)
	region = REGION.new()
	region.initial_focus = Vector3(L.BOUNDS.get_center().x,0,L.BOUNDS.get_center().y)
	stage.add_child(region)
	region.set_developer_view(L.BOUNDS, true, true)
	# Finite inspection admission of production geometry, yielding per cell;
	# this full-map photo is separate from normal streaming and FPS tests.
	region.set_process(false)
	var admitted := 0
	for key in region.developer_view_cells:
		region._complete_focus_chunk(key)
		admitted += 1
		if admitted % 24 == 0: print("COMPACT_OVERVIEW cells=",admitted)
		await process_frame
	region.set_process(true)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 4000
	camera.size = (L.BOUNDS.size.x + 220.0)*float(root.size.y)/float(root.size.x)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	stage.add_child(camera)
	var center := Vector3(L.BOUNDS.get_center().x,0,L.BOUNDS.get_center().y)
	camera.position = center + Vector3(0,1400,500)
	camera.look_at(center)
	camera.current = true
	var deadline := Time.get_ticks_msec()+180000
	while not region.is_streaming_idle() and Time.get_ticks_msec()<deadline:
		await process_frame
	if not region.is_streaming_idle(): push_error("Overview streaming incomplete"); quit(1); return
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("overview.png"))
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"bounds":str(L.BOUNDS),"cells":region.chunks.size(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"engine":Engine.get_version_info().string,"scope":"Production geometry and saved editor changes; no Main population or FPS approval."},"\t"))
	print("COMPACT_OVERVIEW ",output)
	quit()
