extends SceneTree
var actors: Array=[]
var viewports: Array[SubViewport]=[]
var gaits: Array=[]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,800)
	root.content_scale_size=root.size
	var stage=Node2D.new()
	root.add_child(stage)
	current_scene=stage
	for i in 6:
		var actor: Node2D
		if i<4:
			actor=AnimatedPedestrian3D.new()
			actor.appearance_seed=10+i
			actor.archetype_override=1
		elif i==4:
			actor=load("res://world/harbor/interiors/HarborConversationalNPC.gd").new()
			actor.shirt_color=Color("65adae")
			actor.pants_color=Color("34767e")
		else:
			actor=load("res://characters/Player.gd").new()
			var cam=Camera2D.new()
			cam.name="Camera"
			actor.add_child(cam)
		stage.add_child(actor)
		if i==5: actor.get_node("Camera").enabled=false
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.position=Vector2(108+i*212,525)
		if i<4: actor.ensure_presentation()
		var viewport: SubViewport=actor.viewport if i<4 else actor.viewport_3d
		viewport.size=Vector2i(384,384)
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		viewports.append(viewport)
		actor.sprite_3d_display.scale=Vector2.ONE*.57
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
		if i<4:
			var gait=load("res://characters/pedestrians/CitizenGait.gd").new()
			gait.configure(actor,i)
			gaits.append(gait)
		var title=Label.new()
		title.text=["TRANQUILO","APRESSADO","CAUTELOSO","ENÉRGICO","ATENDENTE","DANTE"][i]
		title.position=Vector2(i*212+30,40)
		stage.add_child(title)
		var portrait=SubViewport.new()
		portrait.size=Vector2i(384,384)
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
		display.scale=Vector2.ONE*.49
		display.position=Vector2(108+i*212,205)
		stage.add_child(display)
	# Initial portraits use the neutral rig, before body bounce changes height.
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/npc-personality-0912/faces.png")
	var state_label=Label.new()
	state_label.position=Vector2(540,700)
	stage.add_child(state_label)
	for frame in 120:
		var running: bool=frame>=60
		state_label.text="CORRIDA" if running else "CAMINHADA"
		for i in 4:
			gaits[i].advance(1.0/20.0,2.1 if running else 1.0,running)
			gaits[i].apply_pose()
			actors[i].model_root.rotation.y=PI if frame<40 else PI*.5 if frame<80 else 0.0
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/npc-personality-0912/frames/%03d.png"%frame)
	quit()
