extends SceneTree
## Component visual review only; this is NOT a Main performance benchmark.
func _initialize() -> void: run.call_deferred()
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/motocross/finish-review-"+label+".png")
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("596b73")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b6c9df")
	env.environment.ambient_light_energy = .55
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-35,0)
	sun.light_energy = 1.3; sun.shadow_enabled = true
	world.add_child(sun)
	var course := preload("res://activities/motocross/MotocrossCourse.gd").new()
	world.add_child(course)
	course.finish_build()
	var forest := preload("res://gameplay/urban_v1/FreightOutskirts.gd").new()
	world.add_child(forest)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 24
	world.add_child(camera)
	camera.position = Vector3(-208,20,-17); camera.look_at(Vector3(-229,1,-33)); camera.make_current()
	for i in 100: await process_frame
	await shot("paddock")
	var tree: Vector3 = forest.tree_positions[0]
	for point in forest.tree_positions:
		if point.distance_squared_to(Vector3(-259,0,-35))<tree.distance_squared_to(Vector3(-259,0,-35)): tree=point
	camera.size = 15; camera.position = tree+Vector3(10,12,10); camera.look_at(tree+Vector3.UP*2.4)
	for i in 20: await process_frame
	await shot("trees")
	var bike := preload("res://activities/motocross/MotocrossBike.gd").new()
	world.add_child(bike); bike.max_speed = 17
	bike.reset_to(course.pose(course.length*.32))
	for i in 5: await physics_frame
	bike.speed = 15; bike._planar_velocity = -bike.global_basis.z*15
	var layer := CanvasLayer.new(); root.add_child(layer)
	var hud := preload("res://activities/motocross/MotocrossHUD.gd").new(); layer.add_child(hud)
	var row := {"bike":bike,"lane":0.0}
	for i in 900:
		preload("res://activities/motocross/MotocrossPilot.gd").drive(row,course,[row],16,1.0/60)
		await physics_frame
		camera.size = 13
		camera.position = bike.global_position+bike.global_basis*Vector3(-8,5,-6)
		camera.look_at(bike.global_position+Vector3.UP*.6)
		hud.present(2,6,1,3,float(i)/60,bike)
		if bike._air_time>.16 and bike.velocity.y>.25:
			await shot("jump-hud")
			break
	print("MOTOCROSS_COMPONENT_REVIEW_COMPLETE")
	quit()
