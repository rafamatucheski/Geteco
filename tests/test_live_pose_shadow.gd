extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(20,true,false,true).timeout.connect(func(): quit(2))
	root.size=Vector2i(1000,600)
	root.content_scale_size=root.size
	var world:=Node2D.new()
	root.add_child(world)
	current_scene=world
	var background:=Polygon2D.new()
	background.polygon=PackedVector2Array([Vector2.ZERO,Vector2(1000,0),Vector2(1000,600),Vector2(0,600)])
	background.color=Color("b7b9b4")
	world.add_child(background)
	var actor=load("res://Player.gd").new()
	var actor_camera:=Camera2D.new()
	actor_camera.name="Camera"
	actor.add_child(actor_camera)
	actor.position=Vector2(130,100)
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.get_node("Camera").enabled=false
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.position=Vector2(140,100)
	camera.zoom=Vector2(6,6)
	for i in 10: await process_frame
	var display:Sprite2D=actor.sprite_3d_display
	var shadow:Sprite2D=display.get_node("PoseShadow")
	var before:Vector2=shadow.material.get_shader_parameter("foot")
	# Reframing occurs on entry/exit and death; the shadow must follow it.
	actor.viewport_3d.size=Vector2i(256,256)
	actor.viewport_3d.get_camera_3d().look_at(Vector3(0,.4,0))
	for i in 10: await process_frame
	var expected:Vector2=actor.viewport_3d.get_camera_3d().unproject_position(Vector3.ZERO)-Vector2(actor.viewport_3d.size)*.5+display.offset
	var actual:Vector2=shadow.material.get_shader_parameter("foot")
	var ok:=actual.distance_to(expected)<.01 and actual.distance_to(before)>1
	print("SHADOW ","PASS" if ok else "FAIL"," calibrated pivot after viewport/camera change actual=",actual," expected=",expected)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/bank-video-0913/shadow.png")
	quit(0 if ok else 1)
