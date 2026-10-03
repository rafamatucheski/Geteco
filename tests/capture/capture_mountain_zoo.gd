extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene:=Node3D.new()
	root.add_child(scene)
	var zoo=load("res://world/mountain_detail/zoo/MountainZoo.gd").new()
	scene.add_child(zoo)
	var ground:=MeshInstance3D.new()
	var plane:=PlaneMesh.new(); plane.size=Vector2(100,100)
	ground.mesh=plane
	var mat:=StandardMaterial3D.new(); mat.albedo_color=Color("65725a")
	ground.material_override=mat; scene.add_child(ground)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("879ca7")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("e2e7ea")
	env.environment.ambient_light_energy=.6
	scene.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-50,-30,0)
	sun.shadow_enabled=true; scene.add_child(sun)
	var camera:=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=51; camera.position=Vector3(16,40,36)
	scene.add_child(camera); camera.look_at(Vector3.ZERO); camera.make_current()
	root.size=Vector2i(1280,720)
	for i in 90: await process_frame
	DirAccess.make_dir_recursive_absolute("res://artifacts/mountain-zoo")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/mountain-zoo/preview.png")
	for row in [["giraffe",Vector3(-10.5,0,-8.5)],["lion",Vector3(10.5,0,-8.5)],["monkey",Vector3(10.5,0,8.5)],["zebra",Vector3(-10.5,0,8.5)]]:
		camera.size=14; camera.position=row[1]+Vector3(5,10,12); camera.look_at(row[1]+Vector3.UP)
		for i in 15: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/mountain-zoo/"+row[0]+".png")
	quit()
