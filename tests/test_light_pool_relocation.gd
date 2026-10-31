extends "res://tests/test_belt_lantern_occlusion.gd"
## Uma luminária estática do pool não pode arrastar uma luz interpolada entre suportes.
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	Engine.max_fps = 120
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(640,360)
	var stage := Node3D.new()
	root.add_child(stage)
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0,16,10)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23
	camera.make_current()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .01
	camera.environment = environment
	box(stage,Vector3(0,-.1,0),Vector3(24,.2,16))
	var pool := preload("res://world/city_look/CityLocalLighting.gd").new()
	stage.add_child(pool)
	pool.set_process(false)
	var dark := brightness(await picture(),Vector3(0,.02,0))
	var max_gain := 0.0
	var flashes := 0
	var records: Array = []
	for index in 240:
		await process_frame
		if index%17==0:
			var side := -1.0 if int(index/17)%2==0 else 1.0
			pool.apply_sources([{"id":str(side),"point":Vector3(side*8,1.5,0),"range":4.0,"energy":5.0,"camera_safe":true}],Vector3.ZERO,1.0)
		await RenderingServer.frame_post_draw
		var gain := brightness(root.get_texture().get_image(),Vector3(0,.02,0))-dark
		max_gain = maxf(max_gain,gain)
		if gain > .025: flashes += 1
		records.append({"frame":index,"gain":gain,"physical_position":str(pool.lights[0].global_position),"render_position":str(pool.lights[0].get_global_transform_interpolated().origin)})
	print("POOL_RELOCATION flashes=",flashes," max_gain=",max_gain)
	check(flashes==0,"recycled lamp never illuminates the space between its old and new fittings")
	var out := "res://evidence/mobile-lights-rain-20261015/pool-relocation"
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("samples.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
	stage.free()
	quit(1 if failures else 0)
