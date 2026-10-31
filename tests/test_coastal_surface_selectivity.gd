extends SceneTree
## Aceitação renderizada para "nem tudo reflete": um reflexo branco
## precisa afetar uma minoria de uma rua toda molhada, e nada de uma rua seca.
var errors: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	root.size = Vector2i(640,480)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .8
	stage.add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 64
	stage.add_child(camera)
	camera.position = Vector3(64,60,120)
	camera.look_at(Vector3(64,0,120),Vector3.FORWARD)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100,100)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(64,0,120)
	var material := ShaderMaterial.new()
	material.shader = load("res://world/urban_detail/coastal_wet_asphalt.gdshader")
	material.set_shader_parameter("base_texture",solid(Color(.16,.17,.18)))
	material.set_shader_parameter("roughness_texture",solid(Color.WHITE))
	material.set_shader_parameter("reflection_texture",solid(Color.WHITE))
	material.set_shader_parameter("reflection_projection",camera.get_camera_projection()*Projection(camera.global_transform.affine_inverse()))
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	material.set_shader_parameter("wetness",1.0)
	material.set_shader_parameter("reflection_enabled",false)
	var wet_base := await capture()
	material.set_shader_parameter("reflection_enabled",true)
	var wet_reflected := await capture()
	material.set_shader_parameter("wetness",0.0)
	var dry_reflected := await capture()
	material.set_shader_parameter("reflection_enabled",false)
	var dry_base := await capture()
	var affected := 0
	var sampled := 0
	var dry_delta := 0.0
	var peak := 0.0
	for y in range(40,wet_base.get_height()-40,2):
		for x in range(40,wet_base.get_width()-40,2):
			var difference := wet_reflected.get_pixel(x,y).r-wet_base.get_pixel(x,y).r
			if difference > .004: affected += 1
			peak = maxf(peak,difference)
			dry_delta = maxf(dry_delta,absf(dry_reflected.get_pixel(x,y).r-dry_base.get_pixel(x,y).r))
			sampled += 1
	var share := float(affected)/sampled
	if share < .05 or share > .40: errors.append("Wet road reflection must remain selective: "+str(share))
	if peak < .025: errors.append("Selected wet patches must still reflect")
	if dry_delta > .004: errors.append("Dry asphalt must not reflect scene capture")
	var folder := "res://evidence/coastal-weather-20261013/selectivity-test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	wet_base.save_png(folder+"/wet-base.png")
	wet_reflected.save_png(folder+"/wet-reflected.png")
	print("COASTAL_SURFACE_SELECTIVITY reflected_fraction=",share," peak=",peak," dry_delta=",dry_delta," errors=",errors)
	stage.queue_free()
	for i in 3: await process_frame
	quit(0 if errors.is_empty() else 1)
func solid(color: Color) -> ImageTexture:
	var image := Image.create(8,8,false,Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
func capture() -> Image:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
