extends SceneTree

const OUTPUT := "D:/geteco/artifacts/winter-clothing-0910/"

func _initialize() -> void:
	_run.call_deferred()

func _shot(file: String) -> void:
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + file + ".png")

func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2.ONE * 1.2
	var player = load("res://characters/Player.gd").new()
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5
	capsule.height = 16
	collision.shape = capsule
	player.add_child(collision)
	var player_camera := Camera2D.new()
	player_camera.name = "Camera"
	player.add_child(player_camera)
	world.add_child(player)
	player.set_physics_process(false)
	player.money = 3500
	player.position = Vector2(0,80)
	camera.make_current()
	for winter in [false,true]:
		var room = load("res://world/harbor/interiors/ClothingRoom3D.gd").new()
		room.winter_stock = winter
		world.add_child(room)
		await _shot("mountain-interior" if winter else "union-interior")
		room.shop.open_store(player)
		if not winter:
			room.shop._select_outfit("dante_arctic")
			room.shop._populate_outfit_list()
		await _shot("mountain-shop" if winter else "union-shop")
		if winter:
			room.shop.current_filter="Todos"
			room.shop._select_outfit("dante_classic")
			room.shop._populate_outfit_list()
			await _shot("dante-classic-shop")
			room.shop._select_outfit("dante_trench")
			room.shop._populate_outfit_list()
			root.size=Vector2i(1024,768)
			await _shot("compact-shop-1024")
			root.size=Vector2i(1920,1080)
			await _shot("compact-shop-1920")
			root.size=Vector2i(1280,720)
		room.shop.close_store()
		room.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	print("WINTER CLOTHING CAPTURES COMPLETE")
	quit()
