extends SceneTree
## Visual staging only: real bank, room Camera3D, furniture and shared actor rigs.
## Solid admission is checked before each capture; no presentation is frozen.
var failures: Array[String] = []
var captured: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(110,true,false,true).timeout.connect(func(): printerr("BANK_FURNITURE_CAPTURE_TIMEOUT"); quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met"]: state.set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null: await process_frame
	var world: Node2D = current_scene
	while not world.gameplay_ready: await process_frame
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
		Input.action_release(action)
	var manager: Node = world.get_node("Interiors")
	var room: Node2D = manager.get_node("InteriorSpaces/BankInterior")
	var player: Node2D = world.get_node("Player")
	player.active_weapon_id = "fists"
	player.weapon_aim_active = false
	var originals := {}
	var physics_before := {}
	for npc in room.guards+room.civilians:
		originals[npc] = npc.global_position
		physics_before[npc] = npc.is_physics_processing()
		npc.set_physics_process(false)
	manager._on_exterior_destination_requested(room.entrance,player,room.entrance.destination_id,null,&"",room,room.spawn_point)
	await create_timer(.8).timeout
	if not room.actor_inside() or not player.has_meta("interior_actor_presentation"):
		printerr("BANK_FURNITURE_CAPTURE entry/presentation unavailable")
		quit(1)
		return
	physics_before[player] = player.is_physics_processing()
	player.set_physics_process(false)
	originals[player] = room.spawn_point.global_position
	room.get_node("BankPassage").set_physics_process(false)
	# Only the 2D framing is a fixture. Keep the bank's production Camera3D,
	# projection, geometry and actor presentation running unchanged.
	var gameplay_camera := root.get_camera_2d()
	var camera := Camera2D.new()
	world.add_child(camera)
	var bounds: Rect2 = room.get_gameplay_camera_bounds()
	camera.global_position = bounds.get_center()
	camera.zoom = Vector2.ONE * minf(1280.0/bounds.size.x,720.0/bounds.size.y)*.9
	camera.offset = Vector2.ZERO
	camera.make_current()
	camera.reset_physics_interpolation()
	camera.reset_smoothing()
	camera.force_update_scroll()
	player._refresh_weapon_ui()
	var cases := [
		["counter-front",Vector2(-4.5,.05)],
		["counter-behind",Vector2(-4.5,-2.2)],
		["counter-side",Vector2(-2.65,-.8)],
		["partition-behind",Vector2(-4.5,-4.1)],
		["vault-front",Vector2(0,-2.4)],
	]
	var folder := "D:/geteco/artifacts/chapter-one-0913/bank-furniture-depth"
	DirAccess.make_dir_recursive_absolute(folder)
	for actor in [player,room.civilians[0]]:
		var helper: Node = actor.get_meta("interior_actor_presentation")
		var actor_name := "player" if actor == player else "helena"
		for spec in cases:
			actor.global_position = room.to_global(room.project_floor(spec[1]))
			camera.global_position = bounds.get_center()
			camera.make_current()
			camera.reset_smoothing()
			camera.force_update_scroll()
			actor.velocity = Vector2.ZERO
			actor.reset_physics_interpolation()
			helper._update_scale()
			if not helper._placement_is_clear(room):
				var reason := "%s/%s blocked at %s" % [actor_name,spec[0],str(spec[1])]
				failures.append(reason)
				printerr("BANK_FURNITURE_CAPTURE ",reason)
				continue
			for i in 5: await physics_frame
			await RenderingServer.frame_post_draw
			if root.get_camera_2d() != camera or camera.get_screen_center_position().distance_to(bounds.get_center()) > 5.0:
				failures.append("camera staging failed " + actor_name + "/" + spec[0])
				printerr("BANK_FURNITURE_CAPTURE camera mismatch: ",root.get_camera_2d()," center=",camera.get_screen_center_position()," expected=",bounds.get_center())
				continue
			var path := folder.path_join("%s-%s.png" % [actor_name,spec[0]])
			if root.get_texture().get_image().save_png(path) == OK:
				captured.append(path)
				print("BANK_FURNITURE_CAPTURE saved ",path)
			else: failures.append("save failed "+path)
		actor.global_position = originals[actor]
		actor.velocity = Vector2.ZERO
		actor.reset_physics_interpolation()
		helper._update_scale()
	for actor in originals:
		actor.global_position = originals[actor]
		actor.velocity = Vector2.ZERO
		actor.reset_physics_interpolation()
		actor.get_meta("interior_actor_presentation")._update_scale()
	# Flush body relocation before restoring actors; do not feed it back into
	# CharacterBody as platform motion. No gameplay route is claimed here.
	for i in 3: await physics_frame
	for actor in physics_before: actor.set_physics_process(physics_before[actor])
	gameplay_camera.make_current()
	camera.queue_free()
	room.get_node("BankPassage").has_previous = false
	room.get_node("BankPassage").pending_door = null
	room.get_node("BankPassage").set_physics_process(true)
	print("BANK_FURNITURE_CAPTURE_RESULT images=",captured.size()," blocked_or_failed=",failures)
	world.queue_free()
	for i in 3: await process_frame
	quit(0 if failures.is_empty() else 1)
