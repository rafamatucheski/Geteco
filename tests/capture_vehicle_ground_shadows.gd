extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	# Floor background (gray asphalt)
	var bg := ColorRect.new()
	bg.color = Color("434a54")
	bg.size = Vector2(1280, 720)
	world.add_child(bg)

	var camera := Camera2D.new()
	camera.position = Vector2(530, 330)
	camera.zoom = Vector2(1.35, 1.35)
	world.add_child(camera)

	# 1. Dante (Player)
	var player = preload("res://Player.gd").new()
	player.position = Vector2(200, 260)
	world.add_child(player)

	var label_p := Label.new()
	label_p.text = "Player (Dante)"
	label_p.position = Vector2(160, 200)
	world.add_child(label_p)

	# 2. Car straight (Modular3DCar)
	var car1 = preload("res://prototypes/living_cast/Modular3DCar.gd").new()
	car1.position = Vector2(400, 260)
	car1.rotation = 0.0
	world.add_child(car1)

	var label_c1 := Label.new()
	label_c1.text = "Modular3DCar (0 deg)"
	label_c1.position = Vector2(340, 190)
	world.add_child(label_c1)

	# 3. Car rotated (Modular3DCar at 45 deg)
	var car2 = preload("res://prototypes/living_cast/Modular3DCar.gd").new()
	car2.position = Vector2(660, 260)
	car2.rotation = PI * 0.25
	world.add_child(car2)

	var label_c2 := Label.new()
	label_c2.text = "Modular3DCar (45 deg)"
	label_c2.position = Vector2(600, 180)
	world.add_child(label_c2)

	# 4. Traffic vehicle
	var traffic = preload("res://cars/traffic/TrafficVehicle.gd").new()
	traffic.position = Vector2(400, 420)
	traffic.rotation = PI
	world.add_child(traffic)

	var label_tr := Label.new()
	label_tr.text = "TrafficVehicle"
	label_tr.position = Vector2(350, 470)
	world.add_child(label_tr)

	# 5. Props: Trash Dumpster & Wood Crate
	var dumpster = preload("res://world/shared/BreakableProp.gd").new()
	dumpster.position = Vector2(200, 410)
	dumpster.debris_material = "trash"
	world.add_child(dumpster)

	var crate = preload("res://world/shared/BreakableProp.gd").new()
	crate.position = Vector2(600, 410)
	crate.debris_material = "wood"
	world.add_child(crate)

	# 6. Street lamp with full pole shadow
	var lamp = preload("res://StreetLamp.gd").new()
	lamp.position = Vector2(780, 410)
	world.add_child(lamp)

	var label_l := Label.new()
	label_l.text = "StreetLamp"
	label_l.position = Vector2(750, 470)
	world.add_child(label_l)

	# 7. Collectible (Briefcase)
	var collectible = preload("res://economy/Collectible.gd").new()
	collectible.position = Vector2(800, 260)
	collectible.collectible_id = "test_case_999"
	world.add_child(collectible)

	var label_col := Label.new()
	label_col.text = "Briefcase"
	label_col.position = Vector2(775, 200)
	world.add_child(label_col)

	# 8. Fixed Traffic Signal
	var sig = preload("res://world/shared/roads/traffic/FixedTrafficSignal.gd").new()
	sig.position = Vector2(920, 410)
	world.add_child(sig)
	sig.ensure_presentation()

	var label_sig := Label.new()
	label_sig.text = "TrafficSignal"
	label_sig.position = Vector2(880, 470)
	world.add_child(label_sig)

	# Wait for subviewports to render and materials to bind
	for i in 15:
		await process_frame

	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var out_path := "res://tests/captured_vehicle_ground_shadows.png"
		var abs_out := ProjectSettings.globalize_path(out_path)
		img.save_png(abs_out)
		print("VERIFICATION_PASS: captured ground shadows showcase to ", abs_out)

	quit()
