extends SceneTree
## Fotografa o modelo que o FleetCatalog entrega hoje (motos, empilhadeira, qualquer id). Não certifica FPS.
## Uso: --script res://tools/fleet_fixups/capture_ids.gd -- --ids=bike_urban,port_forklift --out=evidence/two-wheel-20261012/before
const MESH := preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var ids: Array = []
	var out := "res://evidence/two-wheel-20261012/before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="): ids = Array(arg.trim_prefix("--ids=").split(","))
		if arg.begins_with("--out="): out = "res://" + arg.trim_prefix("--out=")
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(1280, 800)
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("86969e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c4d4de")
	env.ambient_light_energy = .65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_color = Color("ffe2b8")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("545c60")
	mat.roughness = .88
	ground.material_override = mat
	world.add_child(ground)
	var camera := Camera3D.new()
	camera.fov = 34
	camera.near = .05
	world.add_child(camera)
	camera.make_current()
	for id: String in ids:
		var model: Node3D = preload("res://runtime/FleetCatalog.gd").create(id)
		if model == null: print("PHOTO_MISSING ", id); continue
		world.add_child(model)
		await process_frame
		var spec: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(id)
		var paint := preload("res://runtime/VehiclePaint.gd").new()
		paint.bind(model, id)
		var palette: Array = spec.get("colors", [])
		if not palette.is_empty(): paint.apply(Color.html(str(palette[0])))
		var size: Array = spec.get("bounds_size", [2.0, 1.5, 4.8])
		var scale: float = maxf(float(size[2]) / 4.8, float(size[1]) / 1.6)
		var target := Vector3(0, float(size[1]) * .43, 0)
		for view in [{"id": "front", "at": Vector3(-5.7, 3.0, -6.7)}, {"id": "rear", "at": Vector3(5.7, 2.9, 6.7)}, {"id": "side", "at": Vector3(8.5, 1.8, 0.0)}]:
			camera.position = view.at * scale
			camera.look_at(target)
			for frame in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out) + "/" + id + "-" + str(view.id) + ".png")
		print("PHOTO ", id, " ", MESH.counts(model))
		model.free()
		await process_frame
	world.free()
	quit()
