extends SceneTree
var failures: Array[String] = []
var world: Node2D
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _run() -> void:
	root.size = Vector2i(1280,720)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := CharacterBody2D.new()
	player.add_to_group("player")
	var player_cam := preload("res://systems/DynamicCamera.gd").new()
	player_cam.name = "Camera"
	player_cam.position_smoothing_enabled = true
	player.add_child(player_cam)
	world.add_child(player)
	var ids := ["sedan_classic","summit_suv","arctic_jeep"]
	for id in ids:
		var car = ModernTrafficFactory.spawn_parked_vehicle(world,"Handoff_"+id,Vector2(10000,6000),0,id,0,Color("3f7589"))
		player.position = car.position + Vector2(0,-45)
		player_cam.make_current()
		player_cam.position = Vector2.ZERO
		player_cam.zoom = Vector2.ONE * 1.85
		player_cam.reset_smoothing()
		player_cam.force_update_scroll()
		await process_frame
		var before := player_cam.get_screen_center_position()
		car.enter_vehicle(player)
		check(car.camera.get_screen_center_position().distance_to(before)<2.0,id+" preserves entry center")
		check(car.camera.zoom.distance_to(Vector2.ONE*1.85)<0.03,id+" preserves entry zoom")
		# Drive far away while the hidden pedestrian remains at the entry point.
		car.position += Vector2(6000,3000)
		car.camera.position = Vector2.ZERO
		car.camera.reset_smoothing()
		car.camera.force_update_scroll()
		await process_frame
		before = car.camera.get_screen_center_position()
		car.exit_vehicle()
		check(player_cam.get_screen_center_position().distance_to(before)<2.0,id+" preserves exit center after distant drive")
		for frame in 20:
			await process_frame
			check(player_cam.get_screen_center_position().distance_to(player.position)<150,id+" no excursion to stale smoothing origin")
		for i in 20:
			car._last_crash_visual_ms = -999999
			car._apply_crash_deformation(Vector2.LEFT,450,car.to_global(Vector2(30,10)))
		if car.is_3d_vehicle:
			check(car.dents_container==null or car.dents_container.get_child_count()==0,id+" no flat decals over native model")
			check(car.body_model.max_deformation()>0.0001 and car.body_model.max_deformation()<=0.14001,id+" native dent exists and respects model metre bound")
			print("DENT ",id," displacement_m=",car.body_model.max_deformation())
			check(car.body_model.marks.is_empty(),id+" no unattached scrape tubes")
		else:
			check(car.dents_container.get_child_count()<=6,id+" bounded persistent scratches")
			for mark in car.dents_container.get_children():
				check(mark is Line2D,id+" no sheet polygons")
				for point in mark.points: check(absf(point.x)<25 and absf(point.y)<14,id+" scratches within body")
		car.queue_free()
		await process_frame
	for script_path in ["res://PlayerCar.gd","res://prototypes/living_cast/HarborCoupe.gd"]:
		var owned = load(script_path).new()
		var owned_camera := Camera2D.new()
		owned_camera.name = "Camera"
		owned_camera.position_smoothing_enabled = true
		owned.add_child(owned_camera)
		var owned_area := Area2D.new()
		owned_area.name = "InteractArea"
		owned.add_child(owned_area)
		var owned_collision := CollisionShape2D.new()
		owned_collision.name = "Collision"
		owned_collision.shape = RectangleShape2D.new()
		owned.add_child(owned_collision)
		world.add_child(owned)
		owned.position = Vector2(22000,14000)
		player.position = owned.position+Vector2(0,-45)
		player_cam.position = Vector2.ZERO
		player_cam.make_current()
		player_cam.reset_smoothing()
		player_cam.force_update_scroll()
		await process_frame
		var before := player_cam.get_screen_center_position()
		owned.enter_vehicle(player)
		check(owned.camera.get_screen_center_position().distance_to(before)<2.0,script_path+" entry center")
		owned.position += Vector2(8000,1000)
		owned.camera.position = Vector2.ZERO
		owned.camera.reset_smoothing()
		owned.camera.force_update_scroll()
		await process_frame
		before = owned.camera.get_screen_center_position()
		owned.exit_vehicle()
		check(player_cam.get_screen_center_position().distance_to(before)<2.0,script_path+" exit center after distant drive")
		owned.queue_free()
		await process_frame
	# Damage first, then cut/open a door, then damage again: topology changed.
	var model := preload("res://prototypes/living_cast/models/SummitSUVModel.gd").new()
	var space := Node3D.new()
	world.add_child(space)
	space.add_child(model)
	model.apply_impact(Vector3(-0.8,0.8,-0.5),Vector3.RIGHT,25)
	var door := preload("res://prototypes/living_cast/VehicleDoor3D.gd").new()
	model.add_child(door)
	door.configure(model)
	model.apply_impact(Vector3(-0.8,0.8,-0.5),Vector3.RIGHT,25)
	check(model.max_deformation()<=0.14001,"door topology changes invalidate obsolete damage buffers")
	model.repair()
	check(is_zero_approx(model.max_deformation()),"repair restores deformation")
	if DisplayServer.get_name() != "headless":
		player.hide()
		var review_cam := Camera2D.new()
		review_cam.position = Vector2(180,100)
		review_cam.zoom = Vector2.ONE * 2.1
		world.add_child(review_cam)
		review_cam.make_current()
		var floor := Polygon2D.new()
		floor.color = Color("343e42")
		floor.polygon = PackedVector2Array([Vector2(-500,-400),Vector2(700,-400),Vector2(700,500),Vector2(-500,500)])
		world.add_child(floor)
		for i in 6:
			var id: String = ["sedan_classic","summit_suv","arctic_jeep","union_sedan","courier_van","ranch_single"][i]
			var position := Vector2((i%3)*150, (i/3)*135)
			var reviewed = ModernTrafficFactory.spawn_parked_vehicle(world,"Review_"+id,position,0.25,id,0,Color("548075"))
			for hit in 12:
				reviewed._last_crash_visual_ms = -999999
				reviewed._apply_crash_deformation(Vector2.LEFT,450,reviewed.to_global(Vector2(30,10)))
			var caption := Label.new()
			caption.text = id+" / 12 impactos"
			caption.add_theme_font_size_override("font_size",10)
			caption.position = position+Vector2(-55,32)
			caption.z_index = 20
			world.add_child(caption)
		for frame in 20: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/vehicle-damage-camera-review.png")
	print("VEHICLE DAMAGE CAMERA FAILURES: ",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
