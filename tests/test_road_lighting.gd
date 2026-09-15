extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("LIGHTING_TEST_TIMEOUT"); quit(2))
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/road-lighting-0911/test-saves/"
	root.get_node("SaveManager").clear_pending_save()
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	var lighting = world.get_node("RoadLighting")
	while not lighting.ready_for_audit: await process_frame
	_check(lighting.report.after.underlit == 0,"All sampled harbor lane centers/edges receive useful ground light")
	_check(lighting.report.added_poles > 100,"Production scene fills missing streets")
	_check(lighting.report.roads >= 38,"City, port, Cobra roads and lower construction accesses are covered")
	var elevated := get_nodes_in_group("elevated_road_light")
	_check(elevated.size() > 40,"Both bridges contain real industrial hardware")
	for fixture in elevated:
		_check(not fixture.has_method("take_damage") and not fixture.has_method("receive_vehicle_impact"),"Overhead hardware cannot be damaged")
		_check(fixture.find_children("*","CollisionObject2D",true,false).is_empty(),"Overhead fixtures never block traffic")
		_check(fixture.hardware.texture is ViewportTexture,"Hardware is rendered from 3D geometry")
		if fixture.always_on: _check(fixture.pool.enabled,"Tunnel safety luminaires must emit ground light during the day")
		fixture._near_view = true
		fixture._refresh_visibility()
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = 0.0
	world.weather.set_weather(0)
	world.weather._update_lighting()
	for fixture in elevated: _check(fixture.is_lit and fixture.pool.visible,"Night turns on visible fixtures")
	world.weather.time_of_day = .45
	world.weather._update_lighting()
	for fixture in elevated:
		_check(fixture.is_lit == fixture.always_on,"Day switches street hardware off and preserves tunnel safety lights")
	world.weather.set_weather(2)
	for fixture in elevated: _check(fixture.is_lit,"Storm switches lights on")
	var first = elevated[0]
	first._near_view = false
	first._refresh_visibility()
	_check(not first.pool.visible and not first.beam.visible,"Offscreen lights and beams stop rendering")
	# New physical posts must not overlap any previously authored world collider.
	await physics_frame
	var excluded: Array[RID] = []
	for lamp in lighting.get_children():
		if lamp is StreetLamp: excluded.append(lamp.get_rid())
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 11
	query.shape = circle
	query.collision_mask = 1
	query.exclude = excluded
	for lamp in lighting.get_children():
		if not lamp is StreetLamp: continue
		query.transform = Transform2D(0,lamp.global_position)
		for hit in world.get_world_2d().direct_space_state.intersect_shape(query,32):
			_check(not hit.collider is StaticBody2D,"New post overlaps existing solid at %s" % lamp.global_position)
	var lamp = lighting.get_node("RoadPost000")
	lamp._near_view = true
	lamp.set_lit(true)
	lamp.receive_vehicle_impact(220,Vector2.RIGHT)
	_check(lamp.broken and not lamp.lamp_light.visible and lamp.collision_layer == 0,"Street-level poles retain impact/breakage behavior")
	var stream = world.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	var mountain_lighting = stream.mountain.get_node("RoadLighting")
	# The region can sleep offscreen; initialization and the audit still finish.
	while not mountain_lighting.ready_for_audit: await process_frame
	_check(mountain_lighting.report.after.underlit == 0,"Mountain road, bridge, tunnel and village accesses have no sampled lighting gaps")
	var output := {"harbor":lighting.report,"mountain":mountain_lighting.report,"elevated_fixtures":get_nodes_in_group("elevated_road_light").size(),"failures":failures}
	var file := FileAccess.open("D:/geteco/artifacts/road-lighting-0911/coverage.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"))
	for failure in failures: push_error(failure)
	print("ROAD_LIGHTING_TEST failures=%d harbor_samples=%d mountain_samples=%d" % [failures.size(),lighting.report.after.samples,mountain_lighting.report.after.samples])
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
