extends SceneTree

const PRESENTATION := preload("res://systems/interiors/InteriorActorPresentation.gd")
var failures := 0
var world: Node2D
var cabin: Node2D
var artifact_dir := "D:/geteco/artifacts/interior-solids-0913/"
class BagProbe extends Node:
	var bag: Node2D
	var anchor: Node3D
	func _update_scale() -> void: bag.place(bag.global_position)

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var coroner := OS.get_cmdline_user_args().has("coroner")
	if coroner: artifact_dir = "D:/geteco/artifacts/coroner-depth/"
	DirAccess.make_dir_recursive_absolute(artifact_dir)
	create_timer(90).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	cabin = load("res://world/mountain_pass/MountainCabinInterior.gd").new()
	cabin.position = Vector2(22500, 20000)
	world.add_child(cabin)
	var player = load("res://Player.gd").new()
	player.name = "Player"
	player.collision_layer = 4
	player.collision_mask = 7
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5
	capsule.height = 16
	collision.shape = capsule
	player.add_child(collision)
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	var npc = load("res://Mortician.tscn").instantiate() if coroner else load("res://AnimatedPedestrian3D.gd").new()
	world.add_child(npc)
	for actor in [player, npc]:
		actor.set_physics_process(false)
		actor.global_position = cabin.spawn_point.global_position
	var resident = load("res://world/mountain_pass/WinterResident.gd").new()
	resident.is_stationary = true
	resident.position = cabin.project_floor(Vector2(3, 3))
	cabin.add_child(resident)
	resident.set_physics_process(false)
	cabin.set_npc_rendering_active(true)
	var review_camera := Camera2D.new()
	world.add_child(review_camera)
	review_camera.global_position = cabin.global_position
	review_camera.zoom = Vector2.ONE * 1.35
	review_camera.make_current()
	await physics_frame
	await physics_frame
	if coroner:
		var bag := preload("res://world/shared/emergency/CoronerRecoveryBag.gd").new()
		bag.name = "CoronerRecoveryBag"
		cabin.add_child(bag)
		bag.place(cabin.to_global(cabin.project_floor(Vector2(0,.4))))
		check(bag.configure_room(cabin),"Recovery bag uses the room renderer")
		var floor_query := PhysicsShapeQueryParameters2D.new()
		floor_query.shape = CircleShape2D.new()
		floor_query.shape.radius = bag.clearance_radius+20
		floor_query.collision_mask = 1
		floor_query.exclude = [bag.solid.get_rid()]
		var clear_floor := false
		for point in [Vector2(0,2),Vector2(-1,2),Vector2(1,2),Vector2(0,3),Vector2(-1,3)]:
			var ground: Vector2 = cabin.to_global(cabin.project_floor(point))
			floor_query.transform = Transform2D(0,ground)
			if world.get_world_2d().direct_space_state.intersect_shape(floor_query,1).is_empty():
				bag.place(ground)
				clear_floor = true
				break
		check(clear_floor,"Bag collision fixture has clear floor for all four approaches")
		for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var edge := bag.global_position
			for i in bag.footprint.size():
				var hit: Variant = Geometry2D.segment_intersects_segment(bag.global_position,bag.global_position+direction*1000,bag.to_global(bag.footprint[i]),bag.to_global(bag.footprint[(i+1)%bag.footprint.size()]))
				if hit is Vector2: edge = hit
			player.global_position = edge+direction*12
			await physics_frame
			var hit: KinematicCollision2D = player.move_and_collide(bag.global_position-player.global_position)
			if hit != null and hit.get_collider()!=bag.solid: print("BAG_SWEEP other=",hit.get_collider().get_path()," from=",direction)
			check(hit != null and hit.get_collider()==bag.solid,"Recovery bag mesh blocks movement from "+str(direction))
		if DisplayServer.get_name() != "headless":
			var probe := BagProbe.new()
			probe.bag = bag
			probe.anchor = bag.room_mesh
			world.add_child(probe)
			await check_depth_occlusion(bag,probe,.09)
			probe.queue_free()
		bag.queue_free()
		await process_frame
	check(resident.has_meta("interior_actor_presentation"), "Room automatically binds resident NPC depth")
	var probes := [Vector2(-3, -3.1), Vector2(-3, -2.1), Vector2(5.5, -2.8), Vector2(2.2, 4.2), Vector2(0, 4.5)]
	for point in probes:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = cabin.to_global(cabin.project_floor(point))
		query.collision_mask = 1
		check(not world.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "Recorded missing object blocks ground: " + str(point))
	var solids := 0
	for shape in cabin.walls_body.get_children():
		if shape.has_meta("model_floor_rect"): solids += 1
	check(solids >= 17, "All physical furniture groups are registered, including small props")
	for actor in [player, npc]:
		var original_parent: Node = actor.model_root.get_parent()
		var original_visible: bool = actor.sprite_3d_display.visible
		var helper := PRESENTATION.new()
		world.add_child(helper)
		actor.global_position = cabin.to_global(cabin.project_floor(Vector2(2.2, -1.2)))
		helper.configure(actor, cabin.camera_3d, cabin.sprite_3d)
		check(actor.global_position.distance_to(cabin.spawn_point.global_position) < .01, "Invalid saved/NPC position returns to clear ground: " + actor.name)
		var spawn_query := PhysicsShapeQueryParameters2D.new()
		spawn_query.shape = helper.collider.shape
		spawn_query.transform = helper.collider.global_transform
		spawn_query.collision_mask = 1
		spawn_query.exclude = [actor.get_rid()]
		check(world.get_world_2d().direct_space_state.intersect_shape(spawn_query).is_empty(), "The complete actor body fits the cabin spawn: " + actor.name)
		check(actor.model_root.get_viewport() == cabin.viewport_3d, "Actor shares furniture depth: " + actor.name)
		check(not actor.sprite_3d_display.visible, "No duplicate actor overlay: " + actor.name)
		for shape in cabin.walls_body.get_children():
			if not shape.has_meta("model_floor_rect"): continue
			var rect: Rect2 = shape.get_meta("model_floor_rect")
			for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				var start: Vector2 = rect.get_center() + direction * (rect.size * 0.5 + Vector2.ONE)
				actor.global_position = cabin.to_global(cabin.project_floor(start))
				helper._update_scale()
				await physics_frame
				var target: Vector2 = cabin.to_global(cabin.project_floor(rect.get_center()))
				var hit: KinematicCollision2D = actor.move_and_collide(target - actor.global_position)
				check(hit != null and actor.global_position.distance_to(target) > 1, "%s cannot cross %s from %s" % [actor.name, shape.name, direction])
		actor.global_position = cabin.spawn_point.global_position
		helper._update_scale()
		check(absf(helper.anchor.global_position.y) < .001, "Feet remain on ground, never furniture tops")
		if actor == player:
			check(actor.get_weapon_muzzle_position().distance_to(helper.project_world(actor.muzzle_flash_3d.global_position)) < .01, "Weapon origin follows the room camera")
			if DisplayServer.get_name() != "headless":
				for point in [Vector2(2.2, -2.4), Vector2(4.8, -1.7), Vector2(0, 3.7), Vector2(-4.8, -0.2)]:
					actor.global_position = cabin.to_global(cabin.project_floor(point))
					helper._update_scale()
					await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(artifact_dir + "depth-%s.png" % str(point))
		if DisplayServer.get_name() != "headless":
			await check_depth_occlusion(actor, helper)
		helper.restore()
		helper.restore() # Exit/respawn/unload may all request cleanup.
		check(actor.model_root.get_parent() == original_parent and actor.sprite_3d_display.visible == original_visible, "Exit restores rig and sprite: " + actor.name)
		helper.queue_free()
		actor.global_position = Vector2.ZERO
	cabin.set_npc_rendering_active(false)
	check(not resident.has_meta("interior_actor_presentation"), "Resident presentation restores on room suspension")
	check(cabin.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Unoccupied room does not render")
	# Teardown must not orphan a rig borrowed by a room or delete the player.
	cabin.set_npc_rendering_active(true)
	var removing_npc := PRESENTATION.new()
	world.add_child(removing_npc)
	removing_npc.configure(npc, cabin.camera_3d, cabin.sprite_3d)
	var npc_rig: WeakRef = weakref(npc.model_root)
	npc.queue_free()
	await process_frame
	await process_frame
	check(npc_rig.get_ref() == null and removing_npc.actor == null, "Removing an admitted NPC frees its borrowed rig")
	removing_npc.queue_free()
	var unloading_room := PRESENTATION.new()
	world.add_child(unloading_room)
	var player_parent: Node = player.model_root.get_parent()
	unloading_room.configure(player, cabin.camera_3d, cabin.sprite_3d)
	cabin.queue_free()
	await process_frame
	await process_frame
	check(is_instance_valid(player.model_root) and player.model_root.get_parent() == player_parent and player.sprite_3d_display.visible, "Room unload restores the surviving player")
	unloading_room.queue_free()
	for script in ["SummitSkiLodgeInterior", "MountainMysteryCaveInterior"]:
		var room: Node2D = load("res://world/mountain_pass/" + script + ".gd").new()
		room.position = Vector2(22500, 20000)
		world.add_child(room)
		player.global_position = room.spawn_point.global_position
		var resident_positions := {}
		for child in room.find_children("*", "CharacterBody2D", true, false):
			resident_positions[child] = child.global_position
		room.set_npc_rendering_active(true)
		for child in resident_positions:
			check(child.global_position.distance_to(resident_positions[child]) < .01, "Authored resident spawn is clear without fallback: " + child.name)
		var presentation := PRESENTATION.new()
		world.add_child(presentation)
		presentation.configure(player, room.camera_3d, room.sprite_3d)
		var previous: Vector3 = presentation.anchor.global_position
		player.global_position += Vector2(4, 0)
		await process_frame
		await process_frame
		check(player.model_root.get_viewport() == room.viewport_3d and presentation.anchor.global_position.distance_to(previous) > .01, "Shared rig follows movement in " + script)
		check(room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Occupied room renders its moving actor in " + script)
		if script == "SummitSkiLodgeInterior":
			# Lighting changes must preserve full-body collision and depth for guests.
			var visitor = load("res://AnimatedPedestrian3D.gd").new()
			world.add_child(visitor)
			visitor.set_physics_process(false)
			var visitor_helper := PRESENTATION.new()
			world.add_child(visitor_helper)
			visitor.global_position = room.spawn_point.global_position
			visitor_helper.configure(visitor, room.camera_3d, room.sprite_3d)
			for pair in [[player, presentation], [visitor, visitor_helper]]:
				var walker: CharacterBody2D = pair[0]
				var helper: Node = pair[1]
				var other: Node2D = visitor if walker == player else player
				other.global_position = room.to_global(room.room_view.project_floor(Vector2(-6.8,0)))
				for shape in room.walls_body.get_children():
					if not shape.has_meta("model_floor_rect"): continue
					var rect: Rect2 = shape.get_meta("model_floor_rect")
					for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
						walker.global_position = room.to_global(room.room_view.project_floor(rect.get_center() + direction * (rect.size * 0.5 + Vector2.ONE)))
						helper._update_scale()
						await physics_frame
						var target: Vector2 = room.to_global(room.room_view.project_floor(rect.get_center()))
						var hit := walker.move_and_collide(target-walker.global_position)
						check(hit != null and walker.global_position.distance_to(target) > 1, "Lodge blocks " + walker.name + " at " + shape.name)
				if DisplayServer.get_name() != "headless":
					cabin = room
					await check_depth_occlusion(walker, helper)
			visitor_helper.restore()
			visitor_helper.queue_free()
			visitor.queue_free()
			player.global_position = room.spawn_point.global_position
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(artifact_dir + script + ".png")
		room.set_npc_rendering_active(false)
		presentation.restore()
		check(player.model_root.get_parent() == player_parent and room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Exit restores actor and suspends " + script)
		presentation.queue_free()
		room.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	await process_frame
	print("PROJECTED_INTERIOR_CONTRACT failures=", failures, " solid_groups=", solids, " swept_approaches=", solids*8)
	quit(0 if failures == 0 else 1)

func check_depth_occlusion(actor: Node2D, helper: Node, focus_height := .9) -> void:
	# An opaque object between camera and actor must hide the rig completely.
	# Compare the same rendered crop with/without the rig behind that object.
	# The lodge's center is a solid dressing cabin; use its clear entrance lane
	# for the positive visibility control, independently of furniture occlusion.
	var point: Vector2 = cabin.project_floor(Vector2(0, 0.4)) if cabin.has_method("project_floor") else cabin.room_view.project_floor(Vector2(0, 3))
	actor.global_position = cabin.to_global(point)
	helper._update_scale()
	helper.set_process(false)
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4, 4, .2)
	panel.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("427766")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = material
	cabin.viewport_3d.add_child(panel)
	panel.position = helper.anchor.position + Vector3(0, 1, 0) + (cabin.camera_3d.position - helper.anchor.position).normalized() * 1.5
	panel.look_at(cabin.camera_3d.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	var with_actor: Image = cabin.viewport_3d.get_texture().get_image()
	helper.anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var without_actor: Image = cabin.viewport_3d.get_texture().get_image()
	var pixel: Vector2 = cabin.camera_3d.unproject_position(helper.anchor.position + Vector3.UP * focus_height)
	var changed := 0
	for y in range(int(pixel.y)-25, int(pixel.y)+25):
		for x in range(int(pixel.x)-20, int(pixel.x)+20):
			if with_actor.get_pixel(x, y) != without_actor.get_pixel(x, y): changed += 1
	check(changed == 0, "Opaque room geometry hides the actor in the real depth buffer")
	print("DEPTH_OCCLUSION actor=", actor.name, " changed_pixels=", changed)
	# Positive control prevents an invisible or misplaced rig from passing.
	panel.hide()
	helper.anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	with_actor = cabin.viewport_3d.get_texture().get_image()
	helper.anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	without_actor = cabin.viewport_3d.get_texture().get_image()
	changed = 0
	for y in range(int(pixel.y)-25, int(pixel.y)+25):
		for x in range(int(pixel.x)-20, int(pixel.x)+20):
			if with_actor.get_pixel(x, y) != without_actor.get_pixel(x, y): changed += 1
	check(changed > 100, "Unobstructed actor is visible at the same ground position")
	print("DEPTH_VISIBLE_CONTROL actor=", actor.name, " changed_pixels=", changed)
	panel.queue_free()
	helper.anchor.show()
