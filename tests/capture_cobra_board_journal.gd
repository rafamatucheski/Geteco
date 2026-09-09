extends SceneTree

## Real-renderer captures of the seven-row board and the Cobra journal, in
## both languages, plus a resolution/overlap sanity pass at 1280x720 and
## 1920x1080. Not a pass/fail test — a deliverable capture script.

func frames(count: int) -> void:
	for _i in count:
		await physics_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(3)

func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var campaign := root.get_node("CampaignState")
	var saves := root.get_node("SaveManager")
	var sm := root.get_node("SettingsManager")
	campaign.reset_campaign()
	saves.clear_pending_save()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_started", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	sm.set_language("pt_BR")

	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var world: Node2D = (load("res://world/harbor/HarborGame.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await frames(20)
	var bridge = world.get_node("CobraCampaign")
	var player = world.get_node("Player")
	var garage = world.get_node("Interiors").garage_interior

	# --- Board, 1280x720, PT-BR ---
	player.global_position = bridge.board.global_position + Vector2(0, 25)
	await frames(10)
	await key(KEY_E)
	await frames(10)
	await shot("D:/geteco/cobra-board-720-pt.png")

	sm.set_language("en")
	await frames(4)
	await shot("D:/geteco/cobra-board-720-en.png")
	sm.set_language("pt_BR")
	await frames(4)
	await key(KEY_ESCAPE)

	# --- Journal, 1280x720, PT-BR then EN ---
	player.global_position = garage.jager_npc.global_position + Vector2(0, 45)
	await frames(10)
	await key(KEY_J)
	await frames(6)
	await shot("D:/geteco/cobra-journal-720-pt.png")
	sm.set_language("en")
	await frames(4)
	await shot("D:/geteco/cobra-journal-720-en.png")
	sm.set_language("pt_BR")
	await frames(4)

	# --- Same journal, 1920x1080, legibility/overlap check ---
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	await frames(6)
	await shot("D:/geteco/cobra-journal-1080-pt.png")
	await key(KEY_J)

	# --- Board, 1920x1080 ---
	player.global_position = bridge.board.global_position + Vector2(0, 25)
	await frames(10)
	await key(KEY_E)
	await frames(10)
	await shot("D:/geteco/cobra-board-1080-pt.png")

	world.queue_free()
	await frames(4)
	print("CAPTURE_DONE")
	quit()
