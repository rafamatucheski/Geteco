extends SceneTree

const ROOM := preload("res://world/harbor/residences/ResidenceInterior.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node2D.new()
	world.name = "ResidenceCompactionContract"
	root.add_child(world)
	current_scene = world
	var spaces := Node2D.new()
	spaces.name = "InteriorSpaces"
	world.add_child(spaces)
	var room := ROOM.new() as ResidenceInterior
	room.name = "Residence_contract"
	room.configure({"id": "contract"}, 0, null)
	spaces.add_child(room)
	await process_frame

	var authored_size := room.authored_viewport_size()
	var collision_before := _collision_signature(room)
	var spawn_before := room.spawn_point.position
	var station_before := room.stations.duplicate(true)
	var projected_before := room.project_floor(Vector2(1.5, 2.5))
	_check(authored_size == Vector2i(800, 667), "physical residence retains its calibrated target size as a separate contract")
	_check(room.viewport_3d.get_meta("authored_resident_size", Vector2i.ZERO) == authored_size, "authored target size is persistent metadata")
	_check(room.is_presentation_compacted() and room.viewport_3d.size == Vector2i(2, 2), "inactive residence target uses Godot's effective 2x2 minimum")
	_check(room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "compacted residence never submits rendering")
	_check(not room.room_display.visible, "compacted room display stays hidden")
	_check(not collision_before.is_empty() and room.walls_body.get_child_count() > 10, "projected furniture solids remain present while target is compacted")

	# Use a moving physics body with the production Player capsule. Point queries
	# do not prove that the complete body can use a corridor or that a large
	# displacement cannot tunnel through projected furniture.
	var body := _production_player_body()
	world.add_child(body)
	body.global_position = room.spawn_point.global_position
	body.reset_physics_interpolation()
	await physics_frame
	var corridor_start := body.global_position
	var corridor_target := room.to_global(room.project_floor(Vector2(0.0, 0.4)))
	var corridor_hit := body.move_and_collide(corridor_target - body.global_position)
	if corridor_hit != null:
		var collider := corridor_hit.get_collider() as CollisionObject2D
		var shape_name := "<unknown>"
		if collider != null:
			var owner_id := collider.shape_find_owner(corridor_hit.get_collider_shape_index())
			var shape_owner := collider.shape_owner_get_owner(owner_id)
			if is_instance_valid(shape_owner): shape_name = String(shape_owner.name)
		print("RESIDENCE_CORRIDOR_HIT collider=%s shape=%s start=%s target=%s position=%s travel=%s remainder=%s normal=%s" % [
			str(corridor_hit.get_collider().get_path()) if is_instance_valid(corridor_hit.get_collider()) else "<invalid>",
			shape_name,
			corridor_start,
			corridor_target,
			body.global_position,
			corridor_hit.get_travel(),
			corridor_hit.get_remainder(),
			corridor_hit.get_normal(),
		])
	_check(corridor_hit == null and body.global_position.distance_to(corridor_target) < 0.1, "production-sized body traverses the authored center corridor")
	var spawn_return_hit := body.move_and_collide(room.spawn_point.global_position - body.global_position)
	_check(spawn_return_hit == null and body.global_position.distance_to(room.spawn_point.global_position) < 0.1, "center corridor remains traversable in both directions")
	var boundary_target := room.to_global(room.project_floor(Vector2(0.0, 5.6)))
	var boundary_hit := body.move_and_collide(boundary_target - body.global_position)
	_check(boundary_hit != null and boundary_hit.get_collider() == room.walls_body, "production-sized body sweep cannot cross the solid residence door boundary")
	_check(body.global_position.distance_to(boundary_target) > 1.0, "blocked sweep leaves the complete body before the far side of the solid")

	var hook_state := {"calls": 0}
	room.viewport_3d.set_meta("quality_residency_hook", func() -> bool:
		hook_state.calls += 1
		room.viewport_3d.msaa_3d = Viewport.MSAA_2X
		room.viewport_3d.remove_meta("quality_residency_hook")
		return true)
	var ready_state := {"called": false}
	room.prepare_presentation_for_entry(func(): ready_state.called = true)
	_check(hook_state.calls == 1, "late residency consumes the RenderQuality hook exactly once")
	_check(room.viewport_3d.size == authored_size and room.viewport_3d.msaa_3d == Viewport.MSAA_2X, "entry restores authored size and pending MSAA before submission")
	_check(not ready_state.called and not room.room_display.visible, "room cannot become visible before its restored render frame")
	for _frame in 4:
		if ready_state.called: break
		await process_frame
	_check(ready_state.called and room.is_entry_frame_ready(), "entry callback waits for the restored target readiness boundary")
	_check(room.room_display.visible, "room display becomes visible only after readiness")

	room.set_npc_rendering_active(true)
	_check(room.viewport_3d.size == authored_size and room.room_display.visible, "active room keeps authored presentation")
	room.set_npc_rendering_active(false)
	_check(room.viewport_3d.size == Vector2i(2, 2) and room.is_presentation_compacted(), "exit returns the room to compact residency")
	_check(room.project_floor(Vector2(1.5, 2.5)).is_equal_approx(projected_before), "runtime target size never changes floor projection")
	_check(room.spawn_point.position.is_equal_approx(spawn_before), "spawn remains invariant across compact and restore")
	_check(_collision_signature(room) == collision_before, "solid geometry remains invariant across compact and restore")
	_check(room.stations == station_before, "interaction positions remain invariant across compact and restore")

	world.queue_free()
	await process_frame
	print("RESIDENCE_VIEWPORT_COMPACTION failures=%s" % JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)


func _collision_signature(room: ResidenceInterior) -> String:
	var parts: Array[String] = []
	for child in room.walls_body.get_children():
		if child is CollisionPolygon2D:
			parts.append(str(child.polygon))
		elif child is CollisionShape2D and child.shape != null:
			parts.append("%s:%s:%s" % [child.name, child.position, child.shape.get_rect()])
	return "|".join(parts)


func _production_player_body() -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = "ResidencePlayerBodyProbe"
	body.collision_layer = 4
	body.collision_mask = 7
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape2D.new()
	# Keep this identical to HarborPreview.tscn's PlayerShape. A smaller legacy
	# capsule would falsely approve corridors that the production Player cannot use.
	capsule.radius = 5.0
	capsule.height = 16.0
	collision.shape = capsule
	body.add_child(collision)
	return body


func _check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures.append(label)
