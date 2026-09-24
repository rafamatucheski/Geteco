extends SceneTree
## Read-only geometry audit. Exit 1 means static obstacles intersect an authored lane.
var findings: Dictionary = {}
var sample_count := 0
var lane_count := 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(180).timeout.connect(func(): print("BRIDGE_HULL_AUDIT TIMEOUT"); quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.gameplay_ready:
		await process_frame
	var world := current_scene
	var stream: Node = world.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	await physics_frame
	await process_frame
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
	var works: Node = world.get_node("Gateway/Works")
	var lower_access_rails: StaticBody2D = works.get_node("AccessRails")
	var upper_probe := CharacterBody2D.new()
	world.add_child(upper_probe)
	var cross_level_clearances := 0
	for lane in get_nodes_in_group("unified_traffic_lane"):
		var road := String(lane.get_meta("traffic_road_id", ""))
		if not ("mountain_bridge_" in road or "map2_highway_" in road or "map2_temporary_return" in road): continue
		if not lane is Path2D or lane.curve == null: continue
		lane_count += 1
		var length: float = lane.curve.get_baked_length()
		print("AUDIT_LANE ",lane.get_path()," road=",road," length=",length," start=",lane.to_global(lane.curve.sample_baked(0))," end=",lane.to_global(lane.curve.sample_baked(length)))
		for hull in [{"id":"center", "size":Vector2(2,2)}, {"id":"sedan", "size":Vector2(70,30)}, {"id":"truck", "size":Vector2(120,36)}]:
			var shape := RectangleShape2D.new()
			shape.size = hull.size
			for index in int(ceil(length / 16.0)) + 1:
				var progress := minf(float(index)*16.0, length)
				var point: Vector2 = lane.to_global(lane.curve.sample_baked(progress))
				var before: Vector2 = lane.to_global(lane.curve.sample_baked(maxf(0,progress-2)))
				var after: Vector2 = lane.to_global(lane.curve.sample_baked(minf(length,progress+2)))
				var query := PhysicsShapeQueryParameters2D.new()
				query.shape = shape
				query.collision_mask = 1
				query.transform = Transform2D((after-before).angle(),point)
				query.collide_with_areas = false
				sample_count += 1
				for hit in space.intersect_shape(query,64):
					var body: Node = hit.collider
					if not body is StaticBody2D: continue
					if body == lower_access_rails:
						# The construction access crosses beneath this deck. An
						# upper-level actor must ignore only its lower-level rails.
						upper_probe.global_position = point
						if not works.update_actor_layer(upper_probe) and upper_probe.get_collision_exceptions().has(body):
							cross_level_clearances += 1
							continue
					var key := "%s|%s|%s|%s" % [lane.get_path(),hull.id,body.get_path(),hit.shape]
					if not findings.has(key):
						var owner: Object = body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape)))
						findings[key] = {"lane":String(lane.get_path()), "road":road,"hull":hull.id,"collider":String(body.get_path()),"shape":String(owner.get_path()) if owner is Node else str(hit.shape),"first_position":point,"last_position":point,"progress_start":progress,"progress_end":progress,"hits":0}
					findings[key].hits += 1
					findings[key].progress_end = progress
					findings[key].last_position = point
	var mountain_lane: Path2D = stream.mountain.get_node("MountainTraffic").lane
	print("MOUNTAIN_SEAM start=",mountain_lane.to_global(mountain_lane.curve.sample_baked(0))," end=",mountain_lane.to_global(mountain_lane.curve.sample_baked(mountain_lane.curve.get_baked_length())))
	for point in [Vector2(5000,-3000),Vector2(6800,-4800),Vector2(6800,-4250),Vector2(6250,-4500)]:
		var probe := PhysicsPointQueryParameters2D.new()
		probe.position = point
		probe.collision_mask = 1
		var names: Array[String] = []
		for hit in space.intersect_point(probe,32): names.append(String(hit.collider.get_path()))
		print("WATER_PROBE position=",point," colliders=",names)
	for finding in findings.values(): print("OBSTRUCTION ",JSON.stringify(finding))
	print("BRIDGE_HULL_AUDIT lanes=",lane_count," samples=",sample_count," obstructions=",findings.size()," cross_level_clearances=",cross_level_clearances)
	upper_probe.queue_free()
	var report := FileAccess.open(OS.get_temp_dir().path_join("bridge_hull_clearance_current.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"lanes":lane_count,"samples":sample_count,"obstructions":findings.values()},"\t"))
	world.queue_free()
	await process_frame
	quit(0 if findings.is_empty() and lane_count == 8 and sample_count > 2000 else 1)
