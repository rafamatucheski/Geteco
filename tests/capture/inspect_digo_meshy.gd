extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("778c99")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = .8
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30,-30,0)
	world.add_child(light)
	var model := load("res://gameplay/digo/DigoMeshyModel.gd").new() as Node3D
	world.add_child(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.05
	world.add_child(camera)
	camera.position = Vector3(.15,1.2,3)
	camera.look_at(Vector3(0,.85,0))
	for skeleton: Skeleton3D in model.find_children("*","Skeleton3D",true,false):
		for i in skeleton.get_bone_count():
			if skeleton.get_bone_name(i) in ["mixamorig_Hips","mixamorig_Spine2","mixamorig_LeftArm","mixamorig_RightArm","mixamorig_LeftForeArm","mixamorig_RightForeArm"]:
				print("BONE ",i," ",skeleton.get_bone_name(i)," ",skeleton.get_bone_global_rest(i))
		print("BONES ",skeleton.get_bone_name(0)," ",skeleton.get_bone_count())
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false): print("MESH ",mesh.get_aabb()," ",mesh.mesh.get_surface_count())
	for day in [2,3,4]:
		model.set_day(day)
		await create_timer(.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/digo/meshy-shirt-%d.png" % day)
	world.free()
	quit()
