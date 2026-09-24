extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	root.size = Vector2i(1000, 700)
	var stage := Node2D.new()
	root.add_child(stage)
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2.ZERO, Vector2(1000, 0), Vector2(1000, 700), Vector2(0, 700)])
	ground.color = Color("555c58")
	stage.add_child(ground)
	var building = load("res://world/harbor/HarborBuilding.gd").new()
	building.name = "Garage"
	building.footprint = Vector2(390, 250)
	building.building_kind = "garage"
	building.business_name = "MACIOTA"
	building.entrance_offset = -40.0
	building.position = Vector2(500, 350)
	building.scale = Vector2(1.7, 1.7)
	stage.add_child(building)
	if not "before" in OS.get_cmdline_user_args():
		var exterior = building.get_node("GarageExterior3D")
		var actor := CharacterBody2D.new()
		actor.collision_layer = 2
		actor.collision_mask = 1
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 5.0
		shape.shape = circle
		actor.add_child(shape)
		exterior.add_child(actor)
		await physics_frame
		for sweep in [
			[Vector2(-7,4), Vector2(-4,4)],
			[Vector2(2.6,4), Vector2(0,4)],
			[Vector2(2.6,4), Vector2(5,4)],
			[Vector2(10,4), Vector2(7,4)],
		]:
			actor.position = exterior.project_floor(sweep[0])
			var end: Vector2 = exterior.to_global(exterior.project_floor(sweep[1]))
			assert(actor.test_move(actor.global_transform, end - actor.global_position), "Facade must block swept movement")
		actor.position = exterior.project_floor(Vector2(2.6,0))
		var alley_end: Vector2 = exterior.to_global(exterior.project_floor(Vector2(2.6,10)))
		assert(not actor.test_move(actor.global_transform, alley_end - actor.global_position), "Side passage must remain clear")
		actor.queue_free()
		print("PASS four facade collision sweeps and side passage")
	await create_timer(5.0).timeout
	await RenderingServer.frame_post_draw
	var tag := "before" if "before" in OS.get_cmdline_user_args() else "after"
	var result := root.get_texture().get_image().save_png("D:/geteco/game/docs/measurements/maciota-exterior-%s.png" % tag)
	assert(result == OK, "Screenshot must be saved")
	print("CAPTURE ", tag)
	quit()
