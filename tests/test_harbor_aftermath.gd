extends SceneTree

## Segmented post-victory checkpoint QA, not a claim of a complete human campaign run.
const GAME := preload("res://world/harbor/HarborGame.tscn")
var failures: Array[String] = []
var world: Node2D
var player: CharacterBody2D
var adapter: Node
var works: Node2D
var ledger: RefCounted

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("AFTERMATH: " + message)

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await frames(4)

func click(button: Button) -> void:
	var pos := button.get_global_rect().get_center()
	Input.warp_mouse(pos)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await frames(4)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.global_position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await frames(4)

func wait_phase(expected: String, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if adapter.get_status().phase == expected:
			return true
		await create_timer(0.1).timeout
		elapsed += 0.1
	print("AFTERMATH phase timeout expected=", expected, " state=", adapter.get_status())
	print("AFTERMATH safety safe=", adapter._safe(), " pos=", player.global_position, " visible=", player.visible, " dead=", player.is_dead, " disabled=", player.is_control_disabled, " dialogue=", player.is_in_dialogue, " paused=", paused, " wanted=", root.get_node("WantedManager").current_stars, " active=", ledger.data.active_id, " territory=", world.get_node("CobraTerritory").state)
	return false

func _run() -> void:
	root.size = Vector2i(1280, 720)
	seed(9007)
	var campaign := root.get_node("CampaignState")
	root.get_node("SaveManager").clear_pending_save()
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	world = GAME.instantiate()
	root.add_child(world)
	current_scene = world
	await frames(10)
	player = world.get_node("Player")
	player.equip_weapon("pistol") # Armed UI regression: clicking must not fire through it.
	ledger = world.get_node("CobraCampaign").ledger
	adapter = world.get_node_or_null("CobraAftermath")
	works = world.get_node_or_null("Gateway/Works")
	check(adapter != null and works != null, "Actual HarborGame integrates aftermath and north works")
	if adapter == null or works == null:
		await finish()
		return
	check(adapter.get_status().phase == "waiting", "No call before actual victory")
	check(not works.get_works_contract().works_complete, "North works initially unfinished")
	check_gateway()
	await capture("before")
	# Explicit authoritative victory fixture; other negative fixture conditions are reset below.
	ledger.data.completed.cobra_finale = true
	ledger.data.defeated = true
	player.is_dead = true
	await create_timer(0.25).timeout
	check(adapter.get_status().phase == "waiting", "Dead actor never receives call")
	player.is_dead = false
	var wanted := root.get_node("WantedManager")
	wanted.current_stars = 1
	wanted.police_spawn_timer = 100.0
	await create_timer(0.25).timeout
	check(adapter.get_status().phase == "waiting", "Wanted actor never receives call")
	wanted.current_stars = 0
	var garage: Node2D = world.get_node("Interiors").garage_interior
	player.global_position = garage.to_global(Vector2(0, 160))
	await create_timer(0.25).timeout
	check(adapter.get_status().phase == "waiting", "Interior actor never receives call")
	player.global_position = Vector2(1700, 2050)
	player.is_in_dialogue = true
	await create_timer(0.25).timeout
	check(adapter.get_status().phase == "waiting", "Other dialogue retains input focus")
	player.is_in_dialogue = false
	check(await wait_phase("ringing", 1.0), "Safe outdoor player gets real incoming call")
	check(adapter._audio.playing, "Incoming call has ringing audio")
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	await frames(3)
	check(adapter._button.text.contains("Maciota") and adapter._button.text.contains("Call"), "Aftermath action updates to English without saving settings")
	TranslationServer.set_locale(previous_locale)
	await frames(3)
	for point in [adapter._button.get_global_rect().get_center(), Vector2(1100, 100)]:
		var hover := InputEventMouseMotion.new()
		hover.position = point
		hover.global_position = point
		Input.warp_mouse(point)
		Input.parse_input_event(hover)
		await frames(4)
	check(not player.is_in_dialogue and not player.is_control_disabled, "Leaving unanswered phone hover releases input lock")
	var ammo_before: Dictionary = player.weapon_ammo.duplicate(true)
	await click(adapter._button)
	check(adapter.get_status().phase == "dialogue" and adapter.get_status().line_index == 0, "Actual mouse answers phone")
	for index in adapter.LINES.size():
		await key(KEY_F8)
	check(player.weapon_ammo == ammo_before and wanted.current_stars == 0, "Armed phone mouse/key interaction never fires or creates wanted stars")
	check(not player.is_control_disabled and not player.is_in_dialogue, "Completed phone releases its own control lock")
	check(adapter.get_status().phase == "delay" and adapter.get_status().call_complete, "Native F8 finishes fixed dialogue")
	var delay_save: Dictionary = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	player.is_in_dialogue = true
	var blocked_elapsed: float = adapter.get_status().safe_elapsed
	await create_timer(0.6).timeout
	check(is_equal_approx(float(adapter.get_status().safe_elapsed), blocked_elapsed), "Unsafe time does not advance seven safe seconds")
	player.is_in_dialogue = false
	await create_timer(5.0).timeout
	check(not paused and adapter.get_status().phase == "delay", "Shot does not start before seven safe seconds")
	var previous_camera := root.get_camera_2d()
	check(await wait_phase("shot", 8.0), "Seven real safe seconds starts shot")
	if adapter.get_status().phase != "shot":
		await finish()
		return
	check(paused and adapter.get_status().owns_pause and root.get_camera_2d() != previous_camera, "Shot owns its pause and separate camera")
	await key(KEY_ESCAPE)
	check(not paused and root.get_camera_2d() == previous_camera, "Explicit cancellation restores prior camera and pause")
	check(not world.get_node("PauseMenu").visible, "Escape cancels shot without simultaneously opening pause menu")
	campaign.restore_from_save(delay_save)
	await create_timer(0.2).timeout
	check(adapter.get_status().phase == "delay" and adapter.get_status().call_complete, "JSON resume does not repeat completed phone call")
	check(await wait_phase("shot", 12.0), "Resumed safe delay reaches shot")
	check(await wait_phase("done", 8.0), "Shot completes without external advancement")
	check(not paused and root.get_camera_2d() == previous_camera, "Completed shot restores gameplay camera and tree")
	check(works.get_works_contract().works_complete, "Work completion is visible and persistent")
	check_gateway()
	await capture("after")
	var completed_save: Dictionary = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	campaign.restore_from_save(completed_save)
	await create_timer(0.3).timeout
	check(adapter.get_status().phase == "done" and not adapter._panel.visible, "Completed JSON resume does not replay shot or call")
	# Scene exit during an owned shot must release the global pause as well.
	campaign.restore_from_save(delay_save)
	await create_timer(0.2).timeout
	check(await wait_phase("shot", 12.0), "Cleanup fixture reaches actual paused shot")
	world.queue_free()
	await frames(4)
	check(not paused, "Freeing scene during shot does not strand global pause")
	world = null
	print("AFTERMATH failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func check_gateway() -> void:
	var contract: Dictionary = works.get_works_contract()
	var gateway: Dictionary = world.get_node("Gateway").get_map2_connection_contract()
	check(not contract.connected and not contract.destination_available and not gateway.connected and str(gateway.transition_scene).is_empty(), "Local work never falsely opens missing Map 2")
	var network: Node2D = world.get_node("RoadNetwork")
	check(network.get_validation_errors().is_empty(), "Existing road graph remains valid")
	var found_return := false
	var probe := CircleShape2D.new()
	probe.radius = 9
	for road in network.get_graph_data().roads:
		if str(road.id) != str(gateway.temporary_return_road_id):
			continue
		found_return = true
		check(road.lanes.size() == 2 and not road.open_start and not road.open_end, "Physical local return remains authored with connected ends")
		for lane in road.lanes:
			var path: Path2D = network.get_lane_path(str(lane.lane_id))
			for distance in range(0, int(path.curve.get_baked_length()), 30):
				var query := PhysicsShapeQueryParameters2D.new()
				query.shape = probe
				query.transform = Transform2D(0, path.to_global(path.curve.sample_baked(distance)))
				query.collision_mask = 1
				for hit in world.get_world_2d().direct_space_state.intersect_shape(query):
					check(not hit.collider is StaticBody2D, "Works do not obstruct physical return at " + str(query.transform.origin))
	check(found_return, "Temporary return still exists in actual network")
	for x in [5880.0, 6120.0]:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = Vector2(x, -4460)
		query.collision_mask = 1
		var blocked := false
		for hit in world.get_world_2d().direct_space_state.intersect_point(query):
			blocked = blocked or hit.collider is StaticBody2D
		check(blocked, "Future absent region stays physically sealed at " + str(query.position))

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless":
		return
	var old := root.get_camera_2d()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = works.get_focus_position()
	camera.zoom = Vector2(0.9, 0.9)
	camera.make_current()
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/harbor-stage5-works-" + label + ".png")
	camera.enabled = false
	camera.queue_free()
	if is_instance_valid(old):
		old.make_current()

func finish() -> void:
	if is_instance_valid(world):
		world.queue_free()
	await frames(4)
	print("AFTERMATH failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
