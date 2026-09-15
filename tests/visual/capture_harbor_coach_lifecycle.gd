extends SceneTree
const OUTPUT := "D:/geteco/artifacts/life-refinement-0911"
func _initialize() -> void:
	call_deferred("run")
func shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(filename))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 15: await process_frame
	world.campaign_controller.skip_cinematic()
	var terminal = world.get_node("ArrivalStop")
	var operations = terminal.terminal_operations
	var camera := Camera2D.new()
	camera.position = terminal.global_position + Vector2(60, -55)
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 1.7
	world.add_child(camera)
	camera.make_current()
	world.weather.time_of_day = 0.45
	world.weather.weather_state = 0
	world.weather.set_rain_intensity(0.0)
	world.weather._update_lighting()
	for layer in world.find_children("*", "CanvasLayer", true, false):
		if layer.name != "OceanBackdrop": layer.hide()
	for i in 12: await process_frame
	await shot("terminal-fleet-initial.png")
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 120
	var recorded := {}
	var service = operations.fleet[0]
	var deadline := Time.get_ticks_msec() + 180000
	var last_print := Time.get_ticks_msec()
	while Time.get_ticks_msec() < deadline:
		await process_frame
		camera.make_current()
		if world.campaign_controller.phase == "phone":
			world.campaign_controller.answer_phone()
			for i in 4: world.campaign_controller.advance_dialogue()
		if service.state in ["exchange", "reversing", "departing"] and not recorded.has(service.state):
			recorded[service.state] = true
			await shot("terminal-fleet-" + service.state + ".png")
		if service.state == "road":
			camera.position = service.coach.global_position
			camera.zoom = Vector2.ONE * 2.0
			if service.coach.position.distance_to(Vector2.ZERO) > 550 and not recorded.has("road"):
				for i in 10: await process_frame
				await shot("terminal-coach-onward-street.png")
				service._external_view.get_texture().get_image().save_png(OUTPUT.path_join("terminal-coach-exterior-viewport.png"))
				recorded["road"] = true
				print("COACH_ROAD_RENDER ", service.coach.global_position, " external=", service._external, " visible=", service._external_sprite.visible)
		if service.state == "arriving" and recorded.has("road"):
			camera.position = terminal.global_position + Vector2(60, -55)
			camera.zoom = Vector2.ONE * 1.7
			for i in 12: await process_frame
			await shot("terminal-coach-returning.png")
			break
		if Time.get_ticks_msec() - last_print > 15000:
			last_print = Time.get_ticks_msec()
			print("COACH_RENDER_PROGRESS ", operations.get_operation_status())
			var urban = terminal.bus
			var rays := {}
			for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
				var ray = urban.get_node_or_null(ray_name)
				if ray and ray.is_colliding(): rays[ray_name] = str(ray.get_collider().get_path())
			print("LOCAL_BUS_DIAG position=", urban.global_position, " lane=", urban.get_parent().get_parent().name, " progress=", urban.get_parent().progress, " dwelling=", urban.dwelling, " speed=", urban._lane_motion_speed, " rays=", rays, " obstacle=", urban._get_lane_obstruction(urban.get_parent()), " contract=", urban._last_lane_motion_contract, " spacing=", urban._lane_spacing_motion(urban.get_parent()))
			var controller = urban._get_junction_traffic_controller()
			var junction: Dictionary = controller._states.get(6, {})
			print("JUNCTION6_DIAG ", junction)
			var owner = instance_from_id(int(junction.get("reservation_owner", 0)))
			if owner is Node2D:
				var owner_rays := {}
				for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
					var ray = owner.get_node_or_null(ray_name)
					if ray and ray.is_colliding(): owner_rays[ray_name] = str(ray.get_collider().get_path())
				print("JUNCTION6_OWNER path=", owner.get_path(), " position=", owner.global_position, " progress=", owner.get_parent().progress if owner.get_parent() is PathFollow2D else -1, " contract=", owner.get("_last_lane_motion_contract"), " velocity=", owner.get("velocity"), " lane_speed=", owner.get("_lane_motion_speed"), " safety=", owner._traffic_control_zone_motion(owner.get_parent().get_parent(), owner.get_parent()) if owner.has_method("_traffic_control_zone_motion") and owner.get_parent() is PathFollow2D else {}, " spacing=", owner._lane_spacing_motion(owner.get_parent()) if owner.has_method("_lane_spacing_motion") and owner.get_parent() is PathFollow2D else {}, " rays=", owner_rays, " obstruction=", owner._get_lane_obstruction(owner.get_parent()) if owner.has_method("_get_lane_obstruction") and owner.get_parent() is PathFollow2D else {})
	print("COACH_LIFECYCLE_RENDER recorded=", recorded, " status=", operations.get_operation_status())
	Engine.time_scale = 1
	Engine.physics_ticks_per_second = 60
	world.queue_free()
	await process_frame
	quit(0 if recorded.has("road") else 1)
