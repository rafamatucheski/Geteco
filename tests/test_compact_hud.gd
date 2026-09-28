extends SceneTree
## Real Main/HUD integration, plus directed navigation and camera option checks.
var world
var checks := 0
var failures: Array[String] = []
const OUT := "res://evidence/compact-hud-20260925"

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("COMPACT_HUD ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT.path_join(label + ".png")) == OK, "capture " + label)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(25092026)
	DirAccess.make_dir_recursive_absolute(OUT)
	test_navigation()
	var settings := root.get_node("V2Settings")
	settings.window_mode = 0
	settings.resolution = 0
	settings.camera_view = 0
	settings.apply_settings()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main ready")
	if not failures.is_empty(): finish(); return
	check(world.production.no_save, "personal saves disabled")
	var hud = world.hud
	var gameplay = world.gameplay
	var state = world.session.state
	world.player.controlled_automatically = true
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999
	world.session.weather._update()
	await frames(30)
	hud.refresh_from_state()
	check(hud.minimap.size == Vector2(188,188), "compact cartographic map has no auxiliary readout rows")
	check(not hud.minimap.caption.visible, "time, temperature and permanent distance stay off the map")
	check(hud.minimap.compass_label.text == "N", "compact north indicator")
	check(hud.combat_panel.visible and not hud.stars_label.visible, "equipped weapon remains visible; inactive police stars do not")
	check(hud.money_label.visible, "wallet balance remains visible")
	await shot("01-exploration")
	var intro_snapshot: Dictionary = state.intro.snapshot()
	var completed_intro := intro_snapshot.duplicate(true)
	completed_intro.phase = "complete"
	completed_intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	check(state.intro.restore_snapshot(completed_intro), "completed tutorial fixture restores through validated progression API")
	hud.minimap.refresh()
	hud.refresh_from_state()
	check(hud.minimap.objective_target == Vector2.ZERO and not hud.minimap.caption.visible and hud.minimap.size.y == 188, "free exploration hides stale destination without resizing map")
	check(state.intro.restore_snapshot(intro_snapshot), "onboarding fixture restored through progression API")
	hud.minimap.refresh()
	hud.refresh_from_state()
	state.grant_weapon("pistol")
	state.add_ammo("pistol", 100)
	state.equip_weapon("pistol")
	await frames(8)
	check(hud.combat_panel.visible, "equipped weapon is readable during exploration")
	gameplay.armor = 50
	Input.action_press("aim")
	await frames(24)
	check(hud.combat_panel.visible and hud.combat_panel.modulate.a > .9, "real aiming reveals combat strip")
	check(hud.weapon_icon.weapon_id == "pistol" and " | " in hud.ammo_label.text, "weapon and ammunition use authoritative inventory")
	check(hud.armor_bar.value == 50 and hud.health_bar.value == gameplay.health, "health and armor values match gameplay")
	var map_position: Vector2 = hud.minimap.position
	await shot("02-combat")
	Input.action_release("aim")
	await frames(360)
	check(hud.combat_panel.visible and not hud.weapon.carousel.visible, "only the switch carousel retracts after inactivity")
	check(hud.minimap.position.is_equal_approx(map_position), "combat animation does not shift map")
	gameplay.damage_player(10)
	await frames(24)
	check(hud.combat_panel.visible and hud.health_bar.value < 100 and hud.armor_bar.value < 50, "actual damage reveals changed health and armor")
	# Freeze only simulation of hostile actors while inspecting deterministic levels.
	gameplay.set_physics_process(false)
	gameplay.register_crime(70, world.player.global_position)
	# Explicit police contact selects pursuit; without it the existing case
	# director enters search and intentionally adds the functional BUSCA label.
	gameplay.report_contact(world.player.global_position)
	hud.refresh_from_state()
	await frames(20)
	check(gameplay.stars > 0 and hud.stars_label.text == "★".repeat(gameplay.stars), "only active wanted stars are shown")
	gameplay.contact_age = 2.0
	hud.refresh_from_state()
	check(hud.stars_label.text == "★".repeat(gameplay.stars)+"  BUSCA", "lost police contact retains existing search indication")
	check(hud.stars_label.get_global_rect().position.y < 140, "active wanted state stays in upper right")
	await shot("03-wanted")
	hud.refresh_from_state()
	await frames(24)
	check(hud.stars_label.visible and hud.combat_panel.visible, "active pursuit and equipped weapon remain readable")
	gameplay.clear_wanted()
	hud.refresh_from_state()
	check(not hud.stars_label.visible and hud.stars_label.text.is_empty(), "clearing pursuit removes all stars immediately")
	state.economy.grant_reward("compact_hud_fixture", 200)
	hud.refresh_from_state()
	check(hud.money_label.visible and hud.money_label.text == "$ "+preload("res://ui/GameStyle.gd").amount(state.economy.balance), "wallet displays actual formatted balance")
	hud.refresh_from_state()
	check(hud.money_label.visible, "wallet remains visible after transaction")
	gameplay.health = 20
	hud.refresh_from_state()
	await frames(24)
	check(hud.combat_panel.visible, "critical health remains visible outside combat")
	gameplay.health = 100
	hud.refresh_from_state()
	await frames(24)
	check(hud.player_status.visible, "recovering health preserves compact status")
	gameplay.set_physics_process(true)
	world.session.modal = true
	hud.refresh_from_state()
	hud.minimap.refresh()
	check(not hud.top_right_panel.is_visible_in_tree() and not hud.minimap.visible, "modal hides whole navigation/status cluster")
	world.session.modal = false
	paused = true
	hud.refresh_from_state()
	hud.minimap.refresh()
	check(not hud.top_right_panel.is_visible_in_tree() and not hud.minimap.visible, "pause hides cluster")
	paused = false
	hud.refresh_from_state()
	hud.minimap.refresh()
	check(hud.minimap.visible, "navigation returns on resume")
	for dimensions in [Vector2i(1024,768), Vector2i(1920,1080)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		await frames(6)
		hud.refresh_from_state()
		check(root.get_visible_rect().encloses(hud.minimap.get_global_rect()), "map respects safe margins at " + str(dimensions))
		check(hud.minimap.size.x == 188, "map stays compact at " + str(dimensions))
	root.content_scale_size = Vector2i(1280,720)
	root.size = Vector2i(1280,720)
	await frames(6)
	var original_offset: Vector3 = world.camera.offset
	var original_heading: float = world.camera.heading
	var menu = load("res://ui/SettingsMenu.tscn").instantiate()
	root.add_child(menu)
	menu.open()
	menu._widgets.camera_view.item_selected.emit(1)
	check(settings.camera_view == 1 and world.camera.preview_view, "real settings option applies diagonal camera")
	menu.close()
	check(settings.camera_view == 0 and not world.camera.preview_view, "Cancel restores original camera preference")
	menu.open()
	menu._widgets.camera_view.item_selected.emit(1)
	menu.hide()
	await frames(40)
	check(world.camera.preview_view and world.camera._preview_blend > .99, "camera preference enables diagonal preview smoothly")
	check(world.camera.offset == original_offset and world.camera.heading == original_heading, "preview preserves original camera state for reversal")
	await shot("04-diagonal-camera")
	menu.queue_free()
	settings.camera_view = 0
	settings.applied.emit()
	await frames(40)
	check(world.camera._preview_blend == 0, "original camera can be restored")
	# Navigate to the real onboarding target from an existing street segment.
	var actor_origin: Vector3 = world.player.position
	world.player.teleport(actor_origin + Vector3(35,0,5))
	await frames(45)
	hud.minimap.refresh()
	check(hud.minimap.objective_target.distance_to(Vector2(world.maciota_place.entry_position.x, world.maciota_place.entry_position.z)) < .1, "onboarding GPS keeps the actual Maciota target")
	check(hud.minimap.route_points.size() >= 2, "production road graph supplies a visible route to the real objective")
	await shot("05-navigation")
	world.player.teleport(actor_origin)
	await frames(5)
	# Garages retain their authored camera and holstered HUD source.
	check(await world.session.enter_place("maciota", false, "maciota"), "real garage entry")
	await frames(15)
	settings.camera_view = 1
	settings.applied.emit()
	var garage_offset: Vector3 = world.camera.offset
	await frames(35)
	check(world.camera.locked and world.camera._exterior_view_offset() == garage_offset, "experimental view cannot alter locked interior camera")
	check(not state.weapons_allowed() and hud.weapon_icon.weapon_id == "fists", "garage still holsters weapons and HUD reflects it")
	check(not hud.minimap.visible, "interior keeps outdoor map hidden")
	finish()

func test_navigation() -> void:
	var routes = load("res://gameplay/NativeTrafficRoutes.gd").new()
	routes.configure([
		{"id":"east", "width":8, "points":PackedVector3Array([Vector3(0,0,0),Vector3(50,0,0)])},
		{"id":"south", "width":8, "points":PackedVector3Array([Vector3(50,0,0),Vector3(50,0,50)])}
	])
	var nav = load("res://ui/v1/NavigationRoute.gd").new()
	nav.update(routes, "test", Vector3(10,0,0), Vector3(50,0,40), true, Vector3.RIGHT)
	check(nav.points.size() >= 3, "GPS follows actual L-shaped streets")
	var info: Dictionary = nav.instruction(nav.remaining(Vector2(10,0)), Vector2(50,40))
	check(not info.is_empty() and absf(info.distance-80.0) < .01 and info.turn == "↱", "GPS turn and distance follow roads rather than direct diagonal")
	nav.update(routes, "test", Vector3(30,0,0), Vector3(10,0,0), false, Vector3.ZERO)
	info = nav.instruction(nav.remaining(Vector2(30,0)), Vector2(10,0))
	check(not info.is_empty() and absf(info.distance-20.0) < .01, "walking back on the same street does not detour through intersections")
	nav.update(routes, "test", Vector3(10,0,0), Vector3(500,0,500), true, Vector3.RIGHT)
	check(nav.points.is_empty(), "unreachable/off-network destination never fabricates a route")
	routes.configure([{"id":"bridge_inbound", "width":8, "points":PackedVector3Array([Vector3.ZERO,Vector3(50,0,0)])}])
	nav.update(routes, "one-way", Vector3(30,0,0), Vector3(10,0,0), true, Vector3.RIGHT)
	check(nav.points.is_empty(), "GPS respects one-way bridges rather than drawing an illegal reverse route")

func finish() -> void:
	print("COMPACT_HUD_RESULT checks=", checks, " failures=", failures.size())
	if is_instance_valid(world): world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
