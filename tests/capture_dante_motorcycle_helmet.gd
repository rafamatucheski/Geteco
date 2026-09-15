extends SceneTree
var views: Array[SubViewport] = []
func _initialize() -> void: run.call_deferred()

func snapshot(source: Node3D, label_text: String, on_foot: bool = false) -> void:
	var index := views.size()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(440,440)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	views.append(viewport)
	var model := source.duplicate(0) as Node3D
	model.rotation = Vector3.ZERO
	viewport.add_child(model)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("26313c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-35,0)
	light.light_energy = 1.2
	viewport.add_child(light)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.9 if on_foot else 2.9
	camera.position = Vector3(3,2.1,-4)
	camera.look_at(Vector3(0,.8,0))
	var label := Label.new()
	label.position = Vector2(18,20)
	label.text = label_text
	label.add_theme_font_size_override("font_size",18)
	viewport.add_child(label)
	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.position = Vector2(index%3*440,index/3*440)
	root.add_child(display)

func run() -> void:
	root.size = Vector2i(1320,880)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	world.hide()
	var actor = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	actor.add_child(camera)
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.active_weapon_id = "fists"
	actor._update_equipped_weapon_3d_mesh()
	var state = actor.ensure_motorcycle_helmet()
	state.set_process(false)
	var bike = preload("res://emergency/ModernTrafficFactory.gd").spawn_parked_vehicle(world,"Moto",Vector2.ZERO,0,"bike_sport",0,Color("2165d9"))
	bike.ensure_presentation()
	bike.set_physics_process(false)
	bike.enter_vehicle(actor)
	await create_timer(.6).timeout
	state.advance(2.9)
	bike.body_model.update_riding_pose(1.0,0,0,true)
	snapshot(bike.body_model,"DANTE • ANTES DOS 3 s")
	state.advance(.40)
	bike.body_model.update_riding_pose(1.0,0,0,true)
	snapshot(bike.body_model,"COLOCANDO O CAPACETE")
	state.advance(.60)
	bike.body_model.update_riding_pose(1.0,0,0,true)
	snapshot(bike.body_model,"PRONTO PARA PILOTAR")
	bike.exit_vehicle()
	actor.set_physics_process(false)
	actor._update_locomotion(1.0,false,false)
	actor.combat_pose.update(actor,1.0,false,false,0)
	state.advance(9.9)
	snapshot(actor.model_root,"AO DESCER • MANTÉM POR 10 s",true)
	state.advance(.50)
	state.apply_on_foot_pose()
	snapshot(actor.model_root,"RETIRANDO O CAPACETE",true)
	state.advance(.60)
	actor.combat_pose.update(actor,1.0,false,false,0)
	snapshot(actor.model_root,"ROSTO E CABELO RESTAURADOS",true)
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var output := Image.create(1320,880,false,Image.FORMAT_RGBA8)
	for i in views.size():
		var part := views[i].get_texture().get_image()
		part.convert(Image.FORMAT_RGBA8)
		output.blit_rect(part,Rect2i(0,0,440,440),Vector2i(i%3*440,i/3*440))
	output.save_png("D:/geteco/artifacts/dante-motorcycle-helmet.png")
	world.queue_free()
	await process_frame
	quit()
