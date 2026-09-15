extends SceneTree
## Read-only geometry audit: production lanes versus fixed world colliders.
var paths: Array[Path2D] = []
func _initialize() -> void: run.call_deferred()
func collect(node: Node) -> void:
	if node is Path2D and node.curve != null and (node.is_in_group("unified_traffic_lane") or node.is_in_group("unified_lane_connector")):
		paths.append(node)
	for child in node.get_children(): collect(child)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func run() -> void:
	var region := "mountain" if OS.get_cmdline_user_args().has("--mountain") else "harbor"
	var source := "res://world/mountain_pass/MountainPass.tscn" if region == "mountain" else "res://world/harbor/HarborGame.tscn"
	var world = load(source).instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 40: await process_frame
	freeze(world)
	await physics_frame
	await physics_frame
	collect(world)
	if OS.get_cmdline_user_args().has("--verify"):
		await verify_hits(world, region)
		quit()
		return
	var results: Array = []
	var samples := 0
	var space := root.world_2d.direct_space_state
	for model in ["sedan_classic", "summit_suv", "route_city"]:
		var probe = ModernTrafficFactory.spawn_parked_vehicle(world, "AuditProbe", Vector2(-90000,-90000), 0, model, 0, Color.WHITE)
		freeze(probe)
		var shape: CollisionShape2D = probe.get_node("Collision")
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape.shape
		query.collision_mask = probe.collision_mask
		query.exclude = [probe.get_rid()]
		query.margin = 0.0
		for path in paths:
			var hits := {}
			var sharpest := 0.0
			var sharp_at := Vector2.ZERO
			var length := path.curve.get_baked_length()
			for index in range(ceili(length / 4.0) + 1):
				var offset := minf(index * 4.0, length)
				var pose := path.global_transform * path.curve.sample_baked_with_rotation(offset, true)
				var ahead := path.global_transform * path.curve.sample_baked_with_rotation(minf(offset + 4.0, length), true)
				var angle := absf(angle_difference(pose.get_rotation(), ahead.get_rotation()))
				if angle > sharpest:
					sharpest = angle
					sharp_at = pose.origin
				query.transform = pose * shape.transform
				samples += 1
				for hit in space.intersect_shape(query, 32):
					if not hit.collider is StaticBody2D: continue
					var key := str(hit.collider.get_path())
					if not hits.has(key): hits[key] = {"obstacle": key, "at": [pose.origin.x, pose.origin.y], "offset": offset, "samples": 0}
					hits[key].samples += 1
			if not hits.is_empty() or sharpest > deg_to_rad(20.0):
				results.append({"model": model, "lane": str(path.get_path()), "connection": path.get_meta("traffic_connection_id", ""), "length": length, "hull": str(shape.shape.get_rect()), "static_hits": hits.values(), "max_heading_change_over_4px_degrees": rad_to_deg(sharpest), "sharp_at": [sharp_at.x, sharp_at.y]})
		probe.queue_free()
	var report := {"region": region, "lanes": paths.size(), "samples": samples, "results": results}
	var output := "D:/geteco/artifacts/traffic-turn-audit-0912-" + region + ".json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TURN_AUDIT region=", region, " lanes=", paths.size(), " samples=", samples, " findings=", results.size(), " output=", output)
	quit()

func verify_hits(world: Node2D, region: String) -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("D:/geteco/artifacts/traffic-turn-audit-0912-" + region + ".json"))
	var verified: Array = []
	for finding in report.results:
		if finding.static_hits.is_empty(): continue
		var path := root.get_node(NodePath(String(finding.lane).trim_prefix("/root/"))) as Path2D
		var probe = ModernTrafficFactory.spawn_parked_vehicle(world, "VerifyProbe", Vector2(-90000,-90000), 0, finding.model, 0, Color.WHITE)
		freeze(probe)
		for hit in finding.static_hits:
			var offset := float(hit.offset)
			var pose := path.global_transform * path.curve.sample_baked_with_rotation(offset, true)
			probe.global_transform = path.global_transform * path.curve.sample_baked_with_rotation(maxf(0, offset - 4.0), true)
			var works := world.get_node_or_null("Gateway/Works")
			if works: works.update_actor_layer(probe)
			await physics_frame
			await physics_frame
			var contact := KinematicCollision2D.new()
			var blocked: bool = probe.test_move(probe.global_transform, pose.origin - probe.global_position, contact)
			var swept_clear: bool = probe.can_apply_lane_pose(pose)
			var row := {"model": finding.model, "lane": finding.lane, "at": hit.at, "kinematic_blocked": blocked, "collider": str(contact.get_collider().get_path()) if blocked else "", "production_pose_clear": swept_clear, "exceptions": probe.get_collision_exceptions().map(func(body): return str(body.get_path()))}
			verified.append(row)
			print("TURN_VERIFY ", JSON.stringify(row))
		probe.queue_free()
		await process_frame
	var file := FileAccess.open("D:/geteco/artifacts/traffic-turn-audit-0912-" + region + "-verified.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(verified, "\t"))
	file.close()
	print("TURN_VERIFY_COMPLETE region=", region, " cases=", verified.size())
