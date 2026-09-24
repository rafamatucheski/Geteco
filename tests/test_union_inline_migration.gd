extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "union_inline_test"
	arm_watchdog(120)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready:
		await process_frame
	var building := world.get_node("District/NorthFrontage3")
	var door: BuildingEntrance = building.get_node("ClothingEntrance")
	var facade: Node2D = building.get_node("UnionCutawayFacade")
	var room: Node2D = world.get_node("Interiors/InteriorSpaces/ClothingRoom0")
	var player: CharacterBody2D = world.get_node("Player")
	player.set_physics_process(false)
	assert(room.inline_mode and room.inline_region == &"harbor")
	assert(room.exit_door == null)
	assert(not door.show_entrance_marker and not door.show_interaction_prompt and not door.handle_input_locally)
	assert(building.get_node_or_null("BuildingSolid") == null)
	assert(room.global_position.distance_to(door.global_position - room.project_floor(Vector2(0, 2.12))) < .1)
	var outside := door.to_global(Vector2(0, 24))
	var inside := room.to_global(room.project_floor(Vector2(0, 1.0)))
	player.global_position = outside
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	await physics_frames(45)
	assert(door.open_amount > .55 and facade.door_blocker.disabled, "Union door must open before crossing")
	assert(await walk_union(player, inside), "Union threshold must have a clear walking path")
	await physics_frames(3)
	assert(room.contains_point(player.global_position))
	assert(player.get_meta("harbor_interior", false))
	assert(not facade.visible and room.sprite_3d.visible)
	assert(room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	assert(player.has_meta("interior_actor_presentation"))
	if DisplayServer.get_name() != "headless":
		await verify_depth(room, player.get_meta("interior_actor_presentation"), "Player")
	player.money = 5000
	room.shop.open_store(player)
	room.shop._select_outfit("dante_arctic")
	room.shop._on_action_pressed()
	assert(player.current_outfit_id == "dante_arctic" and player.money == 3200)
	room.shop.close_store()
	var bounds: Dictionary = preload("res://systems/interiors/InteriorSolidProjection.gd").mesh_bounds(room.room_model)
	for id in [&"BackWall", &"SideWall-1", &"SideWall1", &"FrontPlinth-1", &"FrontPlinth1", &"Checkout", &"Collection-1", &"Collection1", &"WindowLook-1", &"WindowLook1", &"WallRack-1", &"WallRack1", &"FittingBench"]:
		assert(bounds.has(id), "Union physical group missing: " + String(id))
	var checkout := room.to_global(room.project_floor(room.room_model.counter))
	assert(player.move_and_collide(checkout - player.global_position) != null, "Player cannot cross checkout")
	var npc: CharacterBody2D = preload("res://characters/AnimatedPedestrian3D.gd").new()
	world.add_child(npc)
	npc.set_physics_process(false)
	npc.collision_mask = 1
	npc.global_position = inside
	var npc_helper := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	world.add_child(npc_helper)
	npc_helper.configure(npc, room.camera_3d, room.sprite_3d)
	assert(npc.move_and_collide(checkout - npc.global_position) != null, "Real NPC cannot cross checkout")
	if DisplayServer.get_name() != "headless":
		await verify_depth(room, npc_helper, "Visitor")
	npc_helper.restore()
	npc_helper.queue_free()
	npc.queue_free()
	player.global_position = inside
	player.reset_physics_interpolation()
	var cash: Area2D = room.get_node("ShopCash")
	var money_before: int = player.money
	assert(await walk_union(player, cash.global_position), "Cash reward has a clear route")
	await physics_frames(5)
	assert(cash.collected and player.money == money_before + 300, "Union cash pays only after contact")
	cash._collect(player)
	assert(player.money == money_before + 300, "Union cash cannot duplicate")
	assert(await walk_union(player, inside), "Player can return to central aisle")
	assert(await walk_union(player, outside), "Player can walk back through same door")
	await physics_frames(3)
	assert(not player.get_meta("harbor_interior", false))
	assert(facade.visible and not room.sprite_3d.visible)
	assert(room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	print("UNION INLINE PASS door, walk, room, purchase, return")
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0)

func walk_union(actor: CharacterBody2D, target: Vector2) -> bool:
	for _step in 200:
		var motion := target - actor.global_position
		if motion.length() < 2.0: return true
		var hit := actor.move_and_collide(motion.limit_length(2.5))
		if hit != null:
			print("UNION ROUTE BLOCKED ", hit.get_collider().get_path(), " at=", actor.global_position, " target=", target)
			return false
		await physics_frame
	return false

func verify_depth(room: Node2D, adapter: Node, label: String) -> void:
	adapter._update_scale()
	adapter.set_process(false)
	var anchor: Node3D = adapter.anchor
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4, 4, .2)
	panel.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("427766")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = material
	room.viewport_3d.add_child(panel)
	panel.position = anchor.position + Vector3.UP + (room.camera_3d.position - anchor.position).normalized() * 1.5
	panel.look_at(room.camera_3d.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden_actor: Image = room.viewport_3d.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden_empty: Image = room.viewport_3d.get_texture().get_image()
	var pixel: Vector2 = room.camera_3d.unproject_position(anchor.position + Vector3.UP * .9)
	assert(changed_pixels(hidden_actor, hidden_empty, pixel) == 0, label + " stays behind an opaque solid")
	panel.hide()
	anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	var visible_actor: Image = room.viewport_3d.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var visible_empty: Image = room.viewport_3d.get_texture().get_image()
	assert(changed_pixels(visible_actor, visible_empty, pixel) > 100, label + " appears on open floor")
	panel.queue_free()
	anchor.show()
	adapter.set_process(true)

func changed_pixels(a: Image, b: Image, center: Vector2) -> int:
	var changed := 0
	for y in range(maxi(0, int(center.y) - 25), mini(a.get_height(), int(center.y) + 25)):
		for x in range(maxi(0, int(center.x) - 20), mini(a.get_width(), int(center.x) + 20)):
			if a.get_pixel(x, y) != b.get_pixel(x, y): changed += 1
	return changed
