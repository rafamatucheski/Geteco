extends SceneTree
var actors: Array=[]
var viewports: Array[SubViewport]=[]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	seed(914)
	root.size=Vector2i(1920,960)
	RenderingServer.set_default_clear_color(Color("242c36"))
	root.content_scale_size=root.size
	var stage=Node2D.new()
	root.add_child(stage)
	current_scene=stage
	for i in 7:
		var actor: Node2D
		if i<6:
			actor=AnimatedPedestrian3D.new()
			actor.appearance_seed=[120,124,128,132,136,139][i]
			actor.appearance_gender=2 if i==5 else 1
			actor.body_type_override=[1,0,2,3,4,2][i]
			actor.hair_style_override=[0,1,7,5,0,2][i]
			actor.archetype_override=1
			actor.beard_style_override=[0,5,3,2,4,0][i]
			actor.defer_presentation=true
		else:
			actor=load("res://characters/Player.gd").new()
			var cam=Camera2D.new()
			cam.name="Camera"
			actor.add_child(cam)
		stage.add_child(actor)
		if i==6: actor.get_node("Camera").enabled=false
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.position=Vector2(137+i*274,635)
		if i<6:
			actor.has_sunglasses=false
			actor.has_cap=false
			actor.has_beanie=false
			actor.has_beard=i in [1,2,3,4]
			actor.has_coffee_cup=false
			actor.has_briefcase=false
			actor.has_walking_stick=false
			actor.skin_color=[Color("b88465"),Color("c49776"),Color("80553e"),Color("d1ae8f"),Color("a97453"),Color("b48469")][i]
			actor.hair_color=[Color("26231f"),Color("402c20"),Color("282322"),Color("8c8c87"),Color("342b26"),Color("241e1c")][i]
			actor.shirt_color=[Color("496d7c"),Color("a08450"),Color("727b59"),Color("a8a38d"),Color("805752"),Color("527777")][i]
			actor.pants_color=[Color("303e49"),Color("393632"),Color("46494b"),Color("334354"),Color("33383a"),Color("35434c")][i]
			actor.shoe_color=[Color("49392e"),Color("302826"),Color("4c4033"),Color("332b27"),Color("39302c"),Color("302829")][i]
			actor.ensure_presentation()
			actor.gait.apply_pose()
		var viewport: SubViewport=actor.viewport if i<6 else actor.viewport_3d
		viewport.size=Vector2i(640,640)
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		viewports.append(viewport)
		actor.sprite_3d_display.scale=Vector2.ONE*.48
		actor.sprite_3d_display.position=Vector2.ZERO
		actor.model_root.rotation.y=PI
		var camera=viewport.get_camera_3d()
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.look_at_from_position(Vector3(0,1.8,5),Vector3(0,.7,0))
		camera.size=1.85
		for light in viewport.find_children("*","DirectionalLight3D",true,false):
			light.rotation_degrees=Vector3(-40,-25,0)
			light.light_energy=.85
		var world=viewport.find_world_3d()
		if world.environment:
			world.environment.ambient_light_energy=.65
			world.environment.ambient_light_color=Color("a4b2c4")
		actors.append(actor)
		var title=Label.new()
		title.text=["MAGRO / SEM BARBA","MEDIO / BIGODE","GORDO / BARBA CHEIA","ALTO / BARBA CURTA","BAIXO / CAVANHAQUE","CORPO CHEIO","DANTE"][i]
		title.position=Vector2(i*274+25,40)
		stage.add_child(title)
		var portrait=SubViewport.new()
		portrait.size=Vector2i(640,640)
		portrait.transparent_bg=true
		portrait.world_3d=viewport.find_world_3d()
		portrait.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		stage.add_child(portrait)
		var close=Camera3D.new()
		portrait.add_child(close)
		close.projection=Camera3D.PROJECTION_ORTHOGONAL
		close.size=.43
		var head_y: float=actor.head_node.global_position.y
		close.look_at_from_position(Vector3(0,head_y+.025,3),Vector3(0,head_y,0))
		var display=Sprite2D.new()
		display.texture=portrait.get_texture()
		display.scale=Vector2.ONE*.34
		display.position=Vector2(137+i*274,250)
		stage.add_child(display)
	var output := "D:/geteco/artifacts/citizens-diversity-0914/gallery"
	DirAccess.make_dir_recursive_absolute(output+"/frames")
	for direction in 3:
		for actor in actors: actor.model_root.rotation.y=[PI,PI*.5,0.0][direction]
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/"+["front","side","back"][direction]+".png")
	if OS.get_cmdline_user_args().has("--motion"):
		for frame in 180:
			var moving:=frame>=15 and frame<155
			var running:=frame>=75 and frame<135
			for i in 7:
				var actor=actors[i]
				actor.model_root.rotation.y=PI if frame<60 else PI*.5 if frame<135 else 0.0
				if i<6:
					var camera: Camera3D=actor.viewport.get_camera_3d()
					var pixels: float=(camera.unproject_position(Vector3(0,0,.01))-camera.unproject_position(Vector3(0,0,-.01))).length()*actor.sprite_3d_display.scale.x/.02
					actor.gait.advance_distance(1.0/30.0,Vector2(0,((2.5 if running else .95) if moving else 0.0)*pixels/30.0),running)
					actor.gait.apply_pose()
				else:
					actor.walk_clock+=(.31 if running else .225) if moving else 0
					actor._update_locomotion(1.0/30.0,moving,running)
					actor.combat_pose.update(actor,1.0/30.0,false,running and moving,actor._gait_arm_swing())
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/frames/%03d.png"%frame)
	quit(0)
