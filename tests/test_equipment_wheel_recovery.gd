extends SceneTree
## Real damage/death/respawn while wheel owns time. Separate from ordinary UI tests.
const STARTUP := preload("res://tests/fixtures/TravelBagScene.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("WHEEL_RECOVERY: "+label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	check(await STARTUP.wait_for_startup(world),"real session ready")
	if not failures.is_empty(): world.free(); quit(1); return
	var session = world.session
	var wheel = session.equipment_wheel
	var economy = session.state.economy
	check(economy.grid_equip_bag("backpack") and economy.grant_weapon("hunting_rifle") and economy.grid_store_weapon("hunting_rifle","storage"),"rifle stored in carried backpack")
	check(wheel.open() and wheel.entries[5].enabled,"carried backpack rifle available in wheel")
	wheel.selected = 5
	wheel.close(true)
	check(session.state.equipped_weapon == "hunting_rifle" and economy.can_carry_weapon("hunting_rifle"),"wheel transfers selected carried rifle into usable loadout")
	check(wheel.open(),"wheel opens before lethal damage")
	world.gameplay.damage_environment(1000)
	check(world.gameplay.health == 0 and session.rescue_pending and not wheel.active,"lethal damage synchronously cancels wheel and begins real death")
	check(is_equal_approx(Engine.time_scale,.2) and is_equal_approx(session._recovery_time_scale,1),"death presentation takes normal baseline rather than multiplying wheel slow motion")
	var deadline := Time.get_ticks_msec()+20000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not session.rescue_pending and not session.respawn_busy and not session.is_transition_blocked() and not world.player.input_locked and world.gameplay.health > 0: break
	check(not session.rescue_pending and not session.respawn_busy and world.gameplay.health > 0,"actual hospital respawn finishes")
	check(is_equal_approx(Engine.time_scale,1) and not world.player.input_locked,"hospital recovery restores normal time and control")
	check(wheel.open(),"wheel opens after death recovery")
	wheel.close(false)
	world.free()
	await process_frame
	check(is_equal_approx(Engine.time_scale,1),"scene teardown preserves normal clock after recovery")
	print("EQUIPMENT_WHEEL_RECOVERY_RESULT ",checks," checks failures=",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
