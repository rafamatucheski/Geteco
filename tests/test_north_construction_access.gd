extends SceneTree
const ACCESS := preload("res://world/harbor/HarborNorthAccess.gd")
var failures: Array[String] = []
var samples := 0

func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		if failures.size() < 20: push_error(message)

func _run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for i in 10: await physics_frame
	while not scene.world_build_ready: await process_frame
	var works := scene.get_node("Gateway/Works")
	var bridge_trees := get_nodes_in_group("bridge_verge_tree")
	check(bridge_trees.size() == 30,"All 30 exposed causeway verge trees use 3D presentation")
	for tree in bridge_trees:
		check(tree.presentation != null and tree.presentation.texture != null,"Bridge tree has its projected 3D model")
		check(not tree.is_snowy,"Harbor bridge foliage has no snow")
		var trunk: CollisionShape2D = tree.get_node("TrunkCol")
		check(trunk.shape.radius > 0 and tree.collision_layer == 1,"Bridge tree trunk is solid")
		var trunk_x: float = tree.global_position.x + trunk.position.x
		check(trunk_x + trunk.shape.radius < 5750 or trunk_x - trunk.shape.radius > 6250,"Tree solids remain within the planted verges")
		var player_body := scene.get_node("Player") as CharacterBody2D
		var tree_hit := KinematicCollision2D.new()
		var approach := Transform2D(0,tree.global_position + Vector2(0,40))
		check(player_body.test_move(approach,Vector2(0,-40),tree_hit) and tree_hit.get_collider() == tree,"Player movement cannot cross a bridge tree trunk")
	var excluded: Array[RID] = []
	for body in scene.find_children("*","PhysicsBody2D",true,false):
		if not body is StaticBody2D:
			excluded.append(body.get_rid())
			body.set_physics_process(false)
	var probe := CharacterBody2D.new()
	probe.name = "AccessDriveProbe"
	var collision := CollisionShape2D.new()
	collision.shape = RectangleShape2D.new()
	collision.shape.size = Vector2(65,28)
	probe.collision_mask = 1
	probe.collision_layer = 0
	probe.add_child(collision)
	scene.add_child(probe)
	for body in scene.find_children("*","PhysicsBody2D",true,false):
		if not body is StaticBody2D and body != probe: probe.add_collision_exception_with(body)
	await physics_frame
	var routes := ACCESS.curves()
	check(routes.size() == 2,"Two independent carriageways required")
	for index in routes.size():
		var route := routes[index]
		for reverse in [false,true]:
			var first := 0.0 if index == 0 else 100.0
			var last := route.get_baked_length() - (100.0 if index == 0 else 0.0)
			var positions: Array[float] = []
			for offset in range(int(first),int(last),22): positions.append(float(offset))
			positions.append(last)
			if reverse: positions.reverse()
			# Start on an exposed section to select the lower level before crossing.
			probe.position = route.sample_baked(positions[0])
			works.update_actor_layer(probe)
			for offset in positions:
				var point := route.sample_baked(offset)
				var tangent := (route.sample_baked(offset+2)-route.sample_baked(offset-2)).normalized()
				probe.rotation = tangent.angle()
				works.update_actor_layer(probe)
				var motion := point-probe.position
				var hit := KinematicCollision2D.new()
				if probe.test_move(probe.global_transform,motion,hit):
					check(false,"Access %d reverse=%s at %s blocked by %s" % [index,reverse,point,hit.get_collider().get_path()])
				probe.position = point
				samples += 1
	# Cross the complete mouth in both directions, including the avenue before
	# the curve starts. Earlier route-only samples missed these joins.
	for endpoint in [routes[0].get_point_position(0),routes[1].get_point_position(routes[1].point_count-1)]:
		for reverse in [false,true]:
			var start: Vector2 = endpoint+Vector2(0,180) if not reverse else endpoint
			var finish: Vector2 = endpoint if not reverse else endpoint+Vector2(0,180)
			probe.position = start
			probe.rotation = PI/2
			works.update_actor_layer(probe)
			var hit := KinematicCollision2D.new()
			check(not probe.test_move(probe.global_transform,finish-start,hit),"Avenue/access mouth must have no curb collision at %s" % endpoint)
	# Actual upper bridge routes still collide with upper rails, not lower rails.
	for road in preload("res://world/harbor/HarborMountainConnector.gd").road_definitions():
		probe.position = road.points[0]
		works.update_actor_layer(probe)
		for point in road.points:
			works.update_actor_layer(probe)
			probe.rotation = (point-probe.position).angle()
			var hit := KinematicCollision2D.new()
			if probe.test_move(probe.global_transform,point-probe.position,hit): check(false,"Upper bridge blocked by %s" % hit.get_collider().get_path())
			probe.position = point
	for x in ACCESS.AXES:
		probe.position = Vector2(x,ACCESS.GATE_Y+70)
		probe.rotation = -PI/2
		works.update_actor_layer(probe)
		check(probe.test_move(probe.global_transform,Vector2(0,-110)),"Construction gate must physically stop a car")
	works.set_works_complete(true)
	check(works.get_works_contract().worker_positions.size() == 6,"Workers persist after campaign milestone")
	check(works.get_works_contract().construction_progress == 0,"Cosmetic work never advances construction")
	check(not works.get_works_contract().destination_available,"Missing Map 2 remains closed")
	var hud := preload("res://ui/ZoneEntryHUD.gd").new()
	scene.add_child(hud)
	hud.show_zone("SERRA DA NEVASCA")
	check(is_equal_approx(hud.title.anchor_top,0.18) and hud.title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,"Zone title centered in upper screen")
	check(hud.zone_at(Vector2(7400,-4560)) == "SERRA DA NEVASCA","Mountain entry uses correct name")
	check(scene.get_node("RoadNetwork").get_validation_errors().is_empty(),"Through-traffic graph retains valid connections")
	# Exercise the real driven car/camera, not just a material parameter in isolation.
	var car := scene.get_node("PlayerCar") as CharacterBody2D
	car.set("is_driven_by_player",true)
	car.set_physics_process(false)
	var follow := car.get_node("Camera") as Camera2D
	follow.enabled = true
	follow.make_current()
	for distance in range(0,1700,20):
		car.position = routes[1].sample_baked(distance)
		works.update_actor_layer(car)
	car.position = Vector2(6800,-4550)
	car.rotation = PI/2
	car.velocity = Vector2(0,400)
	for i in 20: works._physics_process(0.05)
	check(follow.has_meta("north_underpass_zoom"),"Driving below upper bridge activates zoom")
	check(works._reveal > 0.95,"Upper deck fades and blurs for lower car")
	follow._process(1.0)
	check(follow.zoom.x > 2.1 and is_zero_approx(follow.rotation),"Real camera zooms closer without rotating away from top view")
	var travel := root.get_node("RegionTravel")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(travel.snapshot_world()))
	check(saved.vehicle.get("north_access_lower",false),"Saved vehicle records lower bridge level")
	if OS.get_cmdline_user_args().has("--capture"):
		root.size = Vector2i(1600,1100)
		root.content_scale_size = root.size
		car.reset_physics_interpolation()
		follow.position = Vector2.ZERO
		follow.position_smoothing_enabled = false
		follow.reset_physics_interpolation()
		for layer in root.find_children("*","CanvasLayer",true,false):
			if layer.layer >= 0: layer.hide()
		follow.reset_smoothing()
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/north-junctions-0911/underpass.png")
	car.position = Vector2(6120,-3800)
	for i in 20: works._physics_process(0.05)
	check(not follow.has_meta("north_underpass_zoom") and is_zero_approx(works._reveal),"Leaving underpass restores normal deck and camera")
	car.set("is_driven_by_player",false)
	if OS.get_cmdline_user_args().has("--capture"):
		root.size = Vector2i(1600,1100)
		root.content_scale_size = root.size
		for c in scene.find_children("*","Camera2D",true,false): c.enabled = false
		var camera := Camera2D.new()
		scene.add_child(camera)
		camera.position = Vector2(6240,-4900)
		camera.zoom = Vector2.ONE*0.48
		camera.make_current()
		for layer in root.find_children("*","CanvasLayer",true,false):
			if layer.layer >= 0: layer.hide()
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/north-junctions-0911/overview.png")
		camera.position = Vector2(6000,-4090)
		camera.zoom = Vector2.ONE*1.45
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		var junction_image := root.get_texture().get_image()
		junction_image.save_png("D:/geteco/artifacts/north-junctions-0911/junctions.png")
		for point in [ACCESS.avenue_opening(true).position,ACCESS.avenue_opening(false).position,Vector2(5880,-4200),Vector2(6120,-4200)]:
			var pixel: Vector2 = scene.get_global_transform_with_canvas()*Vector2(point)
			var dark := 0
			for shift in [Vector2(-6,-6),Vector2(6,-6),Vector2(-6,6),Vector2(6,6)]:
				var q := Vector2i(pixel+shift)
				var c := junction_image.get_pixel(q.x,q.y)
				if c.r+c.g+c.b < 1.0: dark += 1
			check(dark >= 3,"Rendered mouth must contain continuous asphalt, not sidewalk, at %s" % point)
		camera.position = Vector2(5940,-5470)
		camera.zoom = Vector2.ONE*1.4
		var clock_before: float = works._clock
		for i in 5: await process_frame
		check(works._clock > clock_before,"Workers continue their repeating activity at the worksite")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/north-junctions-0911/works.png")
	travel.pending_world = saved
	travel._restore_saved_vehicle(scene,scene.get_node("Player"))
	var restored := travel.controlled_car() as PhysicsBody2D
	check(restored != null and works.update_actor_layer(restored),"Restored car remains below the bridge")
	if restored != null:
		restored.force_exit_vehicle()
		check(bool(scene.get_node("Player").get_meta("north_access_lower",false)),"Disembarking keeps the player on the lower road")
	travel.pending_world.clear()
	print("NORTH_ACCESS samples=%d failures=%d" % [samples,failures.size()])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
