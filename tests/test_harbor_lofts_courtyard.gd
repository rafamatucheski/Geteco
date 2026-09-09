extends SceneTree

## Real production Player sweeps through the visible courtyard, while the
## north/east wings still stop that same body. No collision-mask workaround.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for i in 8:
		await physics_frame
	var player := scene.get_node("Player") as CharacterBody2D
	player.set_physics_process(false)
	var original_mask := player.collision_mask
	var lofts := scene.get_node("District/FoundryLofts") as Node2D
	check(lofts.get_node("BuildingSolid").get_child_count()==2,"L collision has two physical wings")
	var space := scene.get_world_2d().direct_space_state
	var point := PhysicsPointQueryParameters2D.new()
	point.position = Vector2(1030,720)
	point.collision_mask = 1
	check(space.intersect_point(point).is_empty(),"Visible courtyard no longer contains an invisible solid")
	player.global_position = Vector2(1030,840)
	await physics_frame
	for destination in [Vector2(1030,720),Vector2(1050,720),Vector2(1030,720),Vector2(1030,840)]:
		var hit := player.move_and_collide(destination-player.global_position)
		check(hit==null,"Real Player traverses courtyard: %s" % destination)
		check(player.global_position.distance_to(destination)<0.1,"Player reaches courtyard destination")
	for destination in [Vector2(1030,620),Vector2(1130,720)]:
		player.global_position = Vector2(1030,720)
		await physics_frame
		var hit := player.move_and_collide(destination-player.global_position)
		check(hit!=null,"Real Player remains blocked by the visible wing")
		if hit != null:
			check(hit.get_collider()==lofts.get_node("BuildingSolid"),"Wing stops player against the correct building, not an unrelated prop")
	check(player.collision_mask==original_mask,"Player collision mask is unchanged")
	# Other building contracts were deliberately preserved byte-for-byte in size.
	var laundry := scene.get_node("District/Laundry") as Node2D
	check(laundry.get_node("BuildingSolid").get_child_count()==1,"Non-L buildings remain one solid")
	check(laundry.get_node("BuildingSolid").get_child(0).shape.size==laundry.footprint-Vector2(2,2),"Non-L collision dimensions are unchanged")
	print("HARBOR LOFTS COURTYARD: four real player passages, two blocked walls, failures=%d" % failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
