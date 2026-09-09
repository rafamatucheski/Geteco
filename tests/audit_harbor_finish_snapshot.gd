extends SceneTree

## Read-only diagnostic snapshot: known finish defects are printed, not hidden
## behind a green regression assertion. Never modifies production geometry.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene := load("res://district/harbor_preview/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for i in 8:
		await physics_frame
	var space := scene.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = Vector2(1030,720)
	query.collision_mask = 1
	query.collide_with_areas = false
	var solids: Array[String] = []
	for hit in space.intersect_point(query,32):
		solids.append(String(hit.collider.get_path()))
	print("FINISH_SNAPSHOT L_VISIBLE_COURTYARD point=(1030,720) physical_solids=",solids)
	var grouped := {}
	var duplicates: Array[String] = []
	var east := 0
	var north := 0
	for lamp in get_nodes_in_group("obstacle"):
		if not lamp is StreetLamp:
			continue
		var parent_id := String(lamp.get_parent().name)
		grouped[parent_id] = int(grouped.get(parent_id,0))+1
		if lamp.global_position.distance_to(Vector2(743,1136))<0.1:
			duplicates.append(String(lamp.get_path()))
		if Rect2(4380,-100,2380,2700).has_point(lamp.global_position):
			east += 1
		if Rect2(4380,-2400,2380,2300).has_point(lamp.global_position):
			north += 1
	print("FINISH_SNAPSHOT LAMPS_BY_PARENT ",grouped)
	print("FINISH_SNAPSHOT LAMPS_AT_(743,1136) ",duplicates)
	print("FINISH_SNAPSHOT PHYSICAL_LAMPS_IN_EAST=%d IN_NORTH=%d" % [east,north])
	var laundry: Node2D = scene.get_node("District/Laundry")
	var laundry_bounds := Rect2(laundry.global_position-laundry.footprint*0.5,laundry.footprint)
	var stale_paving := Rect2(726,855,40,275)
	print("FINISH_SNAPSHOT LEGACY_SERVICE_PAINT_INTERSECTION_LAUNDRY ",stale_paving.intersection(laundry_bounds))
	print("FINISH_SNAPSHOT completed: diagnostic findings, not a zero-defect declaration")
	scene.queue_free()
	await process_frame
	quit()
