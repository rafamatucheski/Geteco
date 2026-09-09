extends SceneTree

func _init() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1000,700)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-1000,-1000),Vector2(1000,-1000),Vector2(1000,1000),Vector2(-1000,1000)])
	ground.color = Color("494d49")
	world.add_child(ground)
	var car := preload("res://prototypes/living_cast/HarborBossMuscle.gd").new()
	world.add_child(car)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE*6
	world.add_child(camera)
	camera.make_current()
	for i in 8: await process_frame
	car._animate_car_door()
	await create_timer(0.36).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/boss-muscle-door-open.png")
	print("BOSS_DOOR_CAPTURE hinge=%s length=%.2f" % [car._door_visual.position,car._door_visual._door_length])
	quit()
