extends SceneTree

const CAR := preload("res://prototypes/living_cast/RearEngineCoupe.gd")

func _init() -> void: call_deferred("run")

func label(parent: Node, value: String, pos: Vector2, size: int) -> void:
	var l := Label.new()
	l.text = value
	l.position = pos
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",Color("e5dccb"))
	parent.add_child(l)

func run() -> void:
	root.size = Vector2i(1500,1020)
	root.content_scale_size = root.size
	var scene := Node.new()
	root.add_child(scene)
	current_scene = scene
	var canvas := CanvasLayer.new()
	scene.add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("172129")
	background.size = Vector2(1500,1020)
	canvas.add_child(background)
	label(canvas,"BREAKWATER / ESTUDO AUTOMOTIVO 01",Vector2(35,24),20)
	label(canvas,"Esportivo de motor traseiro — inspirado no 911",Vector2(35,60),34)
	var positions := [Vector2(30,140),Vector2(815,140),Vector2(815,535)]
	var sizes := [Vector2i(755,735),Vector2i(650,365),Vector2i(650,340)]
	var angles := [Vector3(5,3.15,-6),Vector3(-4.7,2.7,6),Vector3(0,8,0)]
	var names := ["FRENTE / 3/4", "TRASEIRA / 3/4", "SILHUETA SUPERIOR"]
	for i in 3:
		var viewport := SubViewport.new()
		viewport.size = sizes[i]
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		scene.add_child(viewport)
		var world := Node3D.new()
		viewport.add_child(world)
		var car := CAR.new()
		world.add_child(car)
		if i == 2: car.rotation.y = PI/2
		var floor_mesh := PlaneMesh.new()
		floor_mesh.size = Vector2(200,200)
		car.mesh_node(floor_mesh,Vector3(0,-0.012,0),car.mat("floor","434b50",0,0.95))
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("434b50")
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color("a1b2c5")
		env.environment.ambient_light_energy = 0.85
		var sky := Sky.new()
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color("52667b")
		sky_mat.sky_horizon_color = Color("c9c8c2")
		sky_mat.ground_bottom_color = Color("252d35")
		sky.sky_material = sky_mat
		env.environment.sky = sky
		world.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-48,-32,0)
		light.light_energy = 1.4
		light.light_color = Color("fff0da")
		light.shadow_enabled = true
		world.add_child(light)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-30,140,0)
		fill.light_color = Color("acbfd7")
		fill.light_energy = 0.45
		world.add_child(fill)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = angles[i]
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = [5.2,3.5,3.2][i]
		camera.look_at(Vector3(0,0.55,0),Vector3.FORWARD if i == 2 else Vector3.UP)
		var picture := TextureRect.new()
		picture.position = positions[i]
		picture.size = sizes[i]
		picture.texture = viewport.get_texture()
		canvas.add_child(picture)
		label(canvas,names[i],positions[i]+Vector2(18,16),18)
	label(canvas,"Modelo 3D original no Godot / carroceria continua, rodas, vidros e iluminacao",Vector2(35,907),21)
	label(canvas,"Sem logotipos. Estudo visual isolado — ainda nao substitui um veiculo do jogo.",Vector2(35,950),19)
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("D:/geteco/rear_engine_coupe_review.png")
	print("COUPE_CAPTURE result=%d" % result)
	quit(result)
