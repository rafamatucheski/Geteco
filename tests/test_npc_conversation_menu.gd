extends SceneTree
## Production session with isolated save: proximity, menu routing and recovery.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const OUTPUT := "res://artifacts/npc-hud-implementation-20261022/"
var world
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description)
	print(("PASS " if ok else "FAIL ") + description)

func frames(count := 8) -> void:
	for i in count: await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + label + ".png")

func button(text: String) -> Button:
	for child in world.session.column.get_children():
		if child is Button and child.text == text: return child
	return null

func sample_frames() -> Dictionary:
	var warmup := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < warmup: await process_frame
	var samples: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec() - started < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	var elapsed_ms := float(previous - started) / 1000.0
	samples.sort()
	return {"frames": samples.size(), "duration_ms": elapsed_ms, "fps": samples.size() * 1000.0 / elapsed_ms,
		"p50_ms": samples[int(samples.size() * .50)], "p95_ms": samples[int(samples.size() * .95)],
		"p99_ms": samples[int(samples.size() * .99)], "max_ms": samples[-1],
		"over_33ms": samples.filter(func(value): return value > 33.333).size(),
		"over_66ms": samples.filter(func(value): return value > 66.667).size()}

func measure_caption() -> void:
	# Optional comparison uses the exact pre-edit UI sources saved in the task's
	# artifacts. Only their inheritance path is redirected to the saved parent.
	var original = load(OUTPUT + "before/BaselineCard.gd").new()
	var current = world.session.dialogue_card
	world.hud.add_child(original)
	current.hide()
	original.configure(current.speaker_label.text, current.message.text, root.get_node("GameInput"))
	await frames(12)
	await capture("09-caption-before")
	print("HUD_CAPTION_BENCH before: 30 seconds in the rendered garage")
	var before := await sample_frames()
	original.queue_free()
	await frames(4)
	current.show()
	print("HUD_CAPTION_BENCH after: 30 seconds in the same rendered garage")
	var after := await sample_frames()
	var settings := root.get_node("V2Settings")
	var result := {"scenario": "rendered production garage, stationary dialogue, isolated fixture; comparison restricted to caption presentation",
		"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "viewport": str(root.get_visible_rect().size),
		"vsync": DisplayServer.window_get_vsync_mode(), "fps_limit": Engine.max_fps,
		"render_scale": settings.render_scale, "shadow_quality": settings.shadow_quality,
		"before": before, "after": after}
	FileAccess.open(OUTPUT + "caption-performance.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("HUD_CAPTION_BENCH ", JSON.stringify(result))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var folder := FIXTURE.output_dir("npc-hud-implementation-20261022/save")
	var snapshot := FIXTURE.full_snapshot(Vector3(166, .1, 112), true)
	# Early campaign avoids the post-campaign reward-car action taking priority
	# over Maciota at his desk. The introduction is already complete.
	snapshot.campaign = preload("res://systems/campaign/CampaignRuntime.gd").new().snapshot()
	var path := FIXTURE.write_fixture(folder, "save.json", snapshot)
	check(not path.is_empty(), "isolated save created")
	if path.is_empty(): quit(1); return
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path", path)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session != null and world.session.ready_for_play, "real session ready")
	if world.session == null or not world.session.ready_for_play: quit(1); return
	for i in 1200:
		if root.get_node_or_null("StartupCurtain") == null: break
		await process_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	TranslationServer.set_locale("pt_BR")
	var session = world.session
	check(await session.enter_place("maciota", false), "production garage entry")
	await frames(60)
	world.player.teleport(world.maciota_place.interaction_points.maciota + Vector3.UP * .04)
	await frames(20)
	check(not session.modal, "proximity does not open a conversation automatically")
	check(session.nearest().get("id", "") == "maciota", "Maciota interaction is reachable")
	await capture("01-proximidade")
	check(await session.interact(), "normal interaction opens Maciota")
	await frames(12)
	check(session.modal and not session.dialogue_open, "Maciota offers actions separately from spoken dialogue")
	check(button("Ver missões") != null and button("Informações") != null, "missions and information are explicit choices")
	check(button("Cancelar missão") == null, "conversation menu does not expose mission cancellation")
	check(session.panel.size.x <= 400 and session.panel.size.y < 320, "Maciota menu stays compact")
	check(not session.column.get_parent().get_v_scroll_bar().visible, "short Maciota menu fits without scrolling or clipping its help hint")
	await capture("02-menu-maciota")
	var campaign_before: Dictionary = session.state.campaign.snapshot().duplicate(true)
	button("Informações").pressed.emit()
	await frames(12)
	check(button("Cancelar missão") == null, "reading information has no cancel action")
	check(session.state.campaign.snapshot() == campaign_before, "reading information preserves mission progress")
	check(session.column.get_parent() is ScrollContainer and session.column.find_children("*", "Button", true, false).size() <= 3, "information is scrollable read-only content")
	await capture("03-informacoes")
	button("Ver missões").pressed.emit()
	await frames(12)
	check(button("Informações") != null, "journal keeps access to story records")
	await capture("04-missoes")
	# Exercise an active objective without triggering mission spawns or rewards.
	check(session.state.campaign.restore_snapshot(FIXTURE.before_document(true)), "active mission checkpoint restored for journal check")
	session.show_journal()
	await frames(8)
	check(button("Cancelar missão") != null and button(session.mission_world.objective()) == null, "active objective is information while cancellation is an action")
	session.state.campaign.restore_snapshot(campaign_before)
	session.close_menu()
	await frames()
	check(not session.modal and not world.player.input_locked, "closing menus restores gameplay controls")
	session.show_dialogue([{"speaker":"Maciota", "message":"Se quiser descobrir por onde seu irmão passou, começa pelo porto. Eu conheço quem estava trabalhando naquela noite, mas a gente precisa conversar com calma antes de seguir."}])
	await frames(12)
	check(session.dialogue_open and session.dialogue_card.visible and not session.panel.visible, "spoken dialogue owns only its caption")
	check(session.dialogue_card.size.x <= 610, "conversation caption has compact width at 720p")
	await capture("05-conversa")
	if "--measure-caption" in OS.get_cmdline_user_args(): await measure_caption()
	session._advance_dialogue()
	await frames()
	check(not session.dialogue_open and not world.player.input_locked, "ending dialogue restores gameplay")
	var menu = world.pause_panel.settings
	world.pause_panel.pause_game()
	world.pause_panel.open_settings()
	menu._select_tab(3)
	await frames(12)
	check(menu._pages[3].is_visible_in_tree() and menu.is_visible_in_tree(), "HUD help is visible through the production pause/settings flow")
	await capture("06-ajuda-16x9")
	TranslationServer.set_locale("en")
	await frames(12)
	await capture("07-help-english")
	TranslationServer.set_locale("pt_BR")
	root.size = Vector2i(800, 600)
	await frames(20)
	await capture("08-ajuda-800x600")
	menu.close()
	world.pause_panel.resume_game()
	world.queue_free()
	await frames(4)
	print("NPC_CONVERSATION_MENU checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
