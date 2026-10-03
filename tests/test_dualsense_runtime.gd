extends SceneTree
## Run with --no-save --skip-arrival on Godot .NET after compiling Harbor.csproj.
## Production consumers receive joypad events; positions/equipment are explicit fixtures.
## This checks input integration, not rendered camera quality, FPS or full travel routes.
const SKATE_LAYOUT := preload("res://activities/skate/SkateParkLayout.gd")
const ACTIVITY := preload("res://activities/ActivityDefinitions.gd")
var world
var controls: Node
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("DUALSENSE_RUNTIME ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func send_button(index: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func send_axis(index: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = index
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(index: JoyButton) -> void:
	send_button(index, true)
	await frames(2)
	send_button(index, false)
	await frames(2)

func place(point: Vector3) -> void:
	world.player.set_physics_process(false)
	world.production.region.set_focus(point)
	world.player.teleport(point + Vector3.UP * .1)
	await frames(60)
	world.player.set_physics_process(true)
	await frames(20)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("DUALSENSE_RUNTIME requires --no-save")
		quit(2)
		return
	controls = root.get_node("GameInput")
	controls.reset_bindings()
	controls.set_controller_layout(1)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for index in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "production session becomes ready")
	if world.session == null or not world.session.ready_for_play:
		finish()
		return
	world.session.state.intro.stage = "complete"
	if not world.session.state.place_id.is_empty(): await world.session.leave_place()
	await check_camera()
	await check_inventory()
	await check_garage()
	await check_skate()
	await check_ski()
	finish()

func check_camera() -> void:
	await frames(30)
	var before: float = world.camera.heading
	send_axis(JOY_AXIS_RIGHT_X, 1)
	await frames(12)
	check(absf(world.camera.heading - before) > .02, "right stick rotates the real exterior camera")
	send_axis(JOY_AXIS_RIGHT_X, 0)
	before = world.camera.heading
	await frames(6)
	check(is_equal_approx(world.camera.heading, before), "centering right stick stops camera rotation")
	controls.aim_direction = Vector2.RIGHT
	send_axis(JOY_AXIS_TRIGGER_LEFT, 1)
	send_axis(JOY_AXIS_RIGHT_X, .8)
	send_axis(JOY_AXIS_RIGHT_Y, -.8)
	await frames(12)
	check(is_equal_approx(world.camera.heading, before), "L2 aiming owns the stick and holds camera heading")
	check(controls.aim_direction.y < -.1, "right stick changes real gameplay aim while L2 is held")
	send_axis(JOY_AXIS_TRIGGER_LEFT, 0)
	send_axis(JOY_AXIS_RIGHT_X, 0)
	send_axis(JOY_AXIS_RIGHT_Y, 0)
	world.camera.heading = 0

func check_inventory() -> void:
	var session = world.session
	await tap(JOY_BUTTON_DPAD_LEFT)
	var ui = session.field_inventory.ui
	check(session.modal and ui.visible, "left D-pad opens inventory through real input")
	if not ui.visible: return
	var focus_before: Control = null
	for node in ui.card.find_children("*", "Button", true, false):
		if node.text == "×":
			node.grab_focus()
			focus_before = node
			break
	await tap(JOY_BUTTON_DPAD_LEFT)
	check(session.modal and ui.visible, "left D-pad navigates instead of closing inventory")
	check(focus_before != null and root.gui_get_focus_owner() != focus_before, "inventory focus moves left")
	var heading: float = world.camera.heading
	send_axis(JOY_AXIS_RIGHT_X, 1)
	await frames(6)
	send_axis(JOY_AXIS_RIGHT_X, 0)
	check(is_equal_approx(world.camera.heading, heading), "inventory blocks background camera input")
	# Circle shares gameplay surrender. Closing a modal must not also surrender.
	world.gameplay.stars = 1
	world.gameplay.police_case.surrender_block = 0
	world.player.velocity = Vector3.ZERO
	await tap(JOY_BUTTON_B)
	check(not session.modal and not ui.visible and not world.player.input_locked, "Circle closes inventory and restores movement")
	check(not world.gameplay.police_surrendering(), "Circle closing inventory does not leak into surrender")
	world.gameplay.stars = 1
	world.player.velocity = Vector3.ZERO
	send_button(JOY_BUTTON_B, true)
	check(world.gameplay.police_surrendering(), "Circle surrenders during free gameplay")
	send_button(JOY_BUTTON_B, false)
	send_button(JOY_BUTTON_B, true)
	check(not world.gameplay.police_surrendering(), "Circle cancels surrender on a second press")
	send_button(JOY_BUTTON_B, false)
	world.gameplay.clear_wanted()

func check_garage() -> void:
	var session = world.session
	var state = session.state
	var gameplay = world.gameplay
	check(state.economy.grant_weapon("pistol") and state.economy.grant_weapon("grenade"), "garage fixture owns persistent firearm and explosive")
	check(state.equip_weapon("pistol"), "firearm can be equipped before entering garage")
	var owned_before: Dictionary = state.economy.snapshot().weapons.duplicate(true)
	gameplay.clear_wanted()
	var entered: bool = await session.enter_place("maciota", false)
	check(entered and state.place_id == "maciota", "real garage entry completes")
	if not entered: return
	await frames(4)
	check(state.equipped_weapon == "fists" and not state.can_attack(), "garage entry automatically holsters weapon")
	await tap(JOY_BUTTON_RIGHT_SHOULDER)
	await tap(JOY_BUTTON_LEFT_SHOULDER)
	check(state.equipped_weapon == "fists" and not state.equip_weapon("pistol") and not state.equip_weapon("grenade"), "garage blocks controller cycling and firearm/explosive draw")
	var attack_before: int = gameplay._attack_serial
	send_axis(JOY_AXIS_TRIGGER_LEFT, 1)
	send_axis(JOY_AXIS_TRIGGER_RIGHT, 1)
	await frames(8)
	send_axis(JOY_AXIS_TRIGGER_LEFT, 0)
	send_axis(JOY_AXIS_TRIGGER_RIGHT, 0)
	check(gameplay._attack_serial == attack_before and gameplay._swing_age < 0 and not gameplay.aim_active, "garage L2/R2 cannot aim, fire, throw or punch")
	await tap(JOY_BUTTON_DPAD_UP)
	check(not gameplay.flashlight_enabled and not gameplay.reload_weapon(), "garage blocks weapon flashlight and reload")
	var health_before: float = gameplay.health
	gameplay.explode(world.player.global_position, 4, 90, world.player)
	check(is_equal_approx(gameplay.health, health_before), "garage rejects player-origin explosion")
	gameplay.stars = 1
	send_button(JOY_BUTTON_B, true)
	check(not gameplay.police_surrendering(), "garage blocks gameplay surrender input")
	send_button(JOY_BUTTON_B, false)
	gameplay.clear_wanted()
	for person in [world.maciota_place.maciota, world.maciota_place.mechanic]:
		var body := person.get_node("ResidentBody") as StaticBody3D
		gameplay._damage(person, 500, world.player)
		gameplay._damage(body, 500, world.player, true)
		check(is_instance_valid(person) and preload("res://gameplay/DamageProtection.gd").is_protected(body) and not person.has_method("receive_damage") and not person.has_method("die"), "%s remains protected with no damage/death routines" % person.name)
	check(state.economy.snapshot().weapons == owned_before, "garage controls preserve all owned weapons and ammunition")
	var snapshot: Dictionary = state.snapshot()
	snapshot.economy.equipped_weapon = "pistol"
	check(state.restore_snapshot(snapshot) and state.equipped_weapon == "fists" and state.economy.snapshot().weapons == owned_before, "garage save restoration holsters and preserves weapon inventory")
	var left: bool = await session.leave_place()
	check(left and state.place_id.is_empty() and gameplay.attack_allowed() and state.equip_weapon("pistol"), "leaving garage restores weapon use")
	state.equip_weapon("fists")
	await tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(state.equipped_weapon != "fists", "controller weapon cycling works again outside garage")
	state.equip_weapon("fists")

func check_skate() -> void:
	var session = world.session
	var skate = session.skate
	await place(SKATE_LAYOUT.ENTRY + Vector3(.8, 0, 0))
	await frames(90)
	check(session.nearest().get("id") == "skate", "real loose skateboard is available")
	await tap(JOY_BUTTON_X)
	check(skate.mounted, "Square mounts the loose skateboard")
	if not skate.mounted: return
	var board = skate.player_board
	await frames(6)
	var heading: float = world.camera.heading
	send_axis(JOY_AXIS_TRIGGER_RIGHT, 1)
	send_axis(JOY_AXIS_RIGHT_X, 1)
	await frames(36)
	send_axis(JOY_AXIS_TRIGGER_RIGHT, 0)
	send_axis(JOY_AXIS_RIGHT_X, 0)
	check(board.speed > .3 and not session.state.can_attack(), "R2 propels skate while combat stays blocked")
	check(absf(world.camera.heading - heading) > .02, "skate propulsion leaves right-stick camera available")
	board.speed = 0
	await frames(5)
	send_button(JOY_BUTTON_A, true)
	check(board.airborne and board.velocity.y > 0, "Cross starts a physical ollie")
	send_button(JOY_BUTTON_A, false)
	send_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	check(board.trick == "flip", "R1 starts kickflip after ollie")
	send_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	await frames(65)
	check(skate.mounted and skate.score >= 100, "kickflip lands and scores without selecting a weapon")
	if not skate.mounted:
		await frames(150)
		return
	send_button(JOY_BUTTON_A, true)
	send_button(JOY_BUTTON_A, false)
	send_button(JOY_BUTTON_LEFT_SHOULDER, true)
	check(board.trick == "shove", "L1 starts shove-it after ollie")
	send_button(JOY_BUTTON_LEFT_SHOULDER, false)
	await frames(65)
	if skate.mounted:
		board.speed = 0
		await tap(JOY_BUTTON_Y)
	check(not skate.controls_locked() and world.player.is_physics_processing(), "Triangle dismount restores pedestrian controls")
	if skate.controls_locked():
		skate._release_board()
		skate._finish_recovery()

func ski_sample(point: Vector3, trigger: int, initial_speed: float) -> float:
	var ski = world.session.mountain_progression
	ski._stop()
	await place(point)
	ski._equip()
	ski.glide = Vector3.FORWARD * initial_speed
	controls.reset_sprint_toggle()
	if trigger >= 0: send_axis(trigger, 1)
	await frames(20)
	var speed: float = ski.glide.length()
	if trigger >= 0: send_axis(trigger, 0)
	return speed

func check_ski() -> void:
	check(world.production.travel("mountain"), "mountain transition starts")
	for index in 900:
		await physics_frame
		if not world.production.travel_busy: break
	check(not world.production.travel_busy and world.session.state.region_id == "mountain", "mountain transition completes")
	if world.production.travel_busy or world.session.state.region_id != "mountain": return
	var session = world.session
	var ski = session.mountain_progression
	session.weather.time_of_day = .5
	ski.data.rental = true
	ski.data.equipment = true
	var start := ACTIVITY.at(Vector2(6600, -3050), "mountain")
	var neutral := await ski_sample(start, -1, 0)
	var pushed := await ski_sample(start, JOY_AXIS_TRIGGER_RIGHT, 0)
	check(ski.skiing and pushed > neutral + .05, "R2 produces more ski propulsion than neutral input")
	check(not session.state.can_attack() and session.state.equipped_weapon == "fists", "ski trigger never activates combat")
	var coast := await ski_sample(start, -1, 8)
	var braked := await ski_sample(start, JOY_AXIS_TRIGGER_LEFT, 8)
	check(ski.skiing and braked < coast - .2, "L2 slows skis compared with the same initial glide")
	ski._stop()
	await place(ACTIVITY.at(Vector2(7100, -4890), "mountain") + Vector3(0, 0, 4))
	check(ski.lift.board() and ski.lift.riding, "real teleferico boards and starts transition")
	if ski.lift.riding:
		check(session.is_transition_blocked(), "lift owns transition lock before input")
		send_button(JOY_BUTTON_X, true)
		check(ski.lift.elapsed >= ski.lift.DURATION, "Square advances lift despite transition lock")
		send_button(JOY_BUTTON_X, false)
		for index in 300:
			await physics_frame
			if not ski.lift.riding: break
		check(not ski.lift.riding and not session.is_transition_blocked() and not world.player.input_locked, "lift arrives and releases all input locks")
		check(ski._flat(world.player.position).distance_to(ACTIVITY.at(Vector2(6880, -3015), "mountain")) < 8, "lift skip reaches actual summit")
		if ski.lift.riding: ski.cancel_attempt()

func finish() -> void:
	for failure in failures: push_error(failure)
	print("DUALSENSE_RUNTIME_RESULT checks=", checks, " failures=", failures.size())
	if is_instance_valid(world): world.queue_free()
	quit(0 if failures.is_empty() else 1)
