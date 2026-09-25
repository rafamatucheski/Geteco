extends SceneTree
## Real session regression for the transitions shown in the 24/09 recording.
var world: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("VIDEO_SESSION PASS " if ok else "VIDEO_SESSION FAIL ") + label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for _i in count: await physics_frame

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or "--skip-arrival" not in OS.get_cmdline_user_args():
		push_error("Requires --no-save --skip-arrival; never use the personal save")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for _i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "real session ready")
	if not failures.is_empty():
		quit(1)
		return
	var session = world.session
	var state = session.state
	var weather = session.weather
	check(world.production.no_save, "isolated from personal save")
	weather.weather_state = 1
	weather.weather_timer = 99999.0
	weather._update()
	check(weather.precipitation.emitting and weather.precipitation.visible, "outdoor rain active")
	state.grant_weapon("pistol")
	state.equip_weapon("pistol")
	world.gameplay._update_visual()
	world.hud.refresh_from_state()
	session.prompt.text = "E  Entrar"
	if await session.enter_place("maciota", false):
		check(not weather.precipitation.visible and not weather.precipitation.emitting, "garage hides existing rain in admission frame")
		check(not weather.snow.visible and not weather.hail.visible, "garage hides every precipitation layer")
		check(not state.weapons_allowed() and not state.can_attack() and state.equipped_weapon == "fists", "garage still holsters and blocks attacks")
		check(not world.gameplay.gun.visible and world.gameplay.visual_id == "fists", "garage hides the held gun in admission frame")
		check(world.hud.weapon_icon.weapon_id == "fists" and not world.hud.ammo_label.visible, "garage HUD already displays holstered weapon")
		check(session.prompt.text.is_empty() and not world.hud.interaction_row.visible, "garage admission clears stale exterior interaction")
		check(not state.equip_weapon("pistol"), "garage refuses drawing an owned firearm")
		check(session.leave_place(), "garage exit")
		check(weather.precipitation.visible and weather.precipitation.emitting, "rain resumes in exterior return frame")
		check(state.weapons_allowed() and state.equip_weapon("pistol"), "exit preserves inventory and releases firearm")
		_check_exterior_camera("garage")
	else: check(false, "garage entry")
	await frames(4)
	if await session.enter_place("harbor_ammunation", false):
		check(not weather.precipitation.visible, "Ammu-Nation hides rain immediately")
		check(not world.production.environment.environment.fog_enabled, "interior fog cleared before first render")
		world.player.teleport(session.room.interaction_points.service + Vector3.UP * .05)
		await frames(4)
		var action: Dictionary = session.nearest()
		check(action.get("id", "") == "service" and action.get("label", "") == "Falar com Vance", "vendor action at counter")
		session.weapon_shop_entrance._leave()
		check(state.place_id.is_empty(), "Ammu-Nation automatic exit")
		check(world.camera._store_focus_active and is_equal_approx(world.camera.size, 11.0), "exit zoom starts close in the same frame")
		check(world.player.input_locked, "exit zoom temporarily owns movement")
		for _i in 120:
			await physics_frame
			if not session.weapon_shop_entrance._leaving: break
		check(not world.camera._store_focus_active and world.camera.size > 11.0 and not world.player.input_locked, "exit zoom opens view and restores movement")
		_check_exterior_camera("Ammu-Nation")
	else: check(false, "Ammu-Nation entry")
	await frames(4)
	if await session.enter_place("harbor_bank", false):
		world.player.teleport(session.room.exit_position + Vector3.UP * .05)
		await frames(4)
		check(session.nearest().get("id", "") != "exit", "bank walk-up exit offers no E action")
		session.prompt.text = "E  Conversar"
		world.gameplay.health = 0
		session._on_death()
		check(session.prompt.text.is_empty() and session.nearest().is_empty(), "death clears interaction prompt immediately")
		for _i in 600:
			await physics_frame
			if not session.rescue_pending and not session.respawn_busy: break
		check(not session.rescue_pending and not session.respawn_busy and state.place_id.is_empty(), "bank death completes exterior rescue")
		check(world.gameplay.health > 0 and world.player.visible, "rescued player alive and visible")
		check(weather.precipitation.visible and weather.precipitation.emitting, "rescue restores exterior weather")
		_check_exterior_camera("rescue")
	else: check(false, "bank entry")
	print("VIDEO_SESSION checks=", checks, " failures=", failures.size())
	world.queue_free()
	await frames(6)
	quit(0 if failures.is_empty() else 1)

func _check_exterior_camera(label: String) -> void:
	check(world.camera.initialized and world.camera.target == world.player and not world.camera.locked,
		label + " camera synchronized before yielding")
	check(world.camera.focus.distance_to(world.player.global_position) < 5.0,
		label + " camera no longer points at remote interior")
