extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ")+label)
	if not value: failures.append(label)
func _run() -> void:
	create_timer(35).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player = load("res://characters/Player.gd").new()
	player.name = "Player"
	player.collision_layer = 4
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	var collider := CollisionShape2D.new()
	collider.shape = CircleShape2D.new()
	collider.shape.radius = 7
	player.add_child(collider)
	scene.add_child(player)
	player.set_physics_process(false)
	for outfit in ["dante_classic","dante_arctic"]:
		player.current_outfit_id = outfit
		player._rebuild_dante_costume()
		Input.action_press("ui_up")
		Input.action_press("sprint")
		var max_gap := 0.0
		var max_shoulder_gap := 0.0
		for frame in 180:
			player._physics_process(1.0/60.0)
			var head_anchor: Vector3 = player.torso_node.to_global(Vector3(0,0.40,0))
			max_gap = maxf(max_gap,head_anchor.distance_to(player.head_node.global_position))
			max_shoulder_gap = maxf(max_shoulder_gap,player.torso_node.to_global(Vector3(0.185,0.20,0)).distance_to(player.right_upper_arm.global_position))
		Input.action_release("ui_up")
		Input.action_release("sprint")
		check(max_gap < 0.001 and max_shoulder_gap < 0.001,"neck/shoulder continuous during sprint: "+outfit)
		check(player.torso_node.rotation.x < 0,"sprint leans forward: "+outfit)
	player.current_outfit_id = "dante_classic"
	player._rebuild_dante_costume()
	var cabin = load("res://world/mountain_pass/MountainCabinInterior.gd").new()
	scene.add_child(cabin)
	cabin.set_npc_rendering_active(true)
	check(cabin.cabin_3d_world.get_node_or_null("SilasVance3D") == null,"unwanted cabin NPC removed")
	check(cabin.cabin_3d_world.get_node_or_null("TacticalKnife3D") == null,"no misleading counter knife duplicate")
	player.set_meta("mountain_interior",true)
	player.position = cabin.project_floor(Vector2(0,2.5))
	player.sprite_3d_display.scale = Vector2.ONE * 0.65
	player.z_index = 8
	camera.set_script(null)
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 1.4
	for i in 4: await physics_frame
	for station in cabin._active_weapon_stations:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = station.global_position
		query.collision_mask = 1
		check(scene.get_world_2d().direct_space_state.intersect_point(query).is_empty(),"pickup in walkable floor outside furniture: "+station.weapon_id)
		var initial: float = station.model.rotation.y
		await create_timer(0.12).timeout
		check(station.model.rotation.y == initial and station.model.position.y < 0.10,"weapon rests close to floor: "+station.weapon_id)
		check(station.model.get_node("FloorWeapon").get_child_count()>5,"detailed shared geometry: "+station.weapon_id)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/cabin-floor-loot-review.png")
	for station in cabin._active_weapon_stations:
		player.global_position = station.global_position
		for i in 5: await physics_frame
		check(station.collected and not station.model.visible,"physical pickup without E: "+station.weapon_id)
		check(player.world_pickups_collected.has(station.pickup_id),"persistent world pickup ID: "+station.weapon_id)
		var ammo_before: Dictionary = player.weapon_ammo.duplicate(true)
		station._collect(player)
		check(ammo_before == player.weapon_ammo,"no duplicated ammo after reentry: "+station.weapon_id)
	var dropped = load("res://legacy/city_demo/scenes/pickups/WeaponPickup.gd").new()
	dropped.weapon_id = &"shotgun"
	dropped.position = player.position + Vector2(100,0)
	scene.add_child(dropped)
	for i in 3: await physics_frame
	player.position = dropped.position
	for i in 5: await physics_frame
	check(dropped._consumed and player.weapon_inventory.get("shotgun",false),"street drop responds to real player layer")
	print("CHARACTER_FLOOR_LOOT failures=",failures.size())
	scene.queue_free()
	for i in 5: await process_frame
	quit(0 if failures.is_empty() else 1)
