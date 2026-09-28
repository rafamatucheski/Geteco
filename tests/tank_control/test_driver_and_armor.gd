extends SceneTree
## Main + real boarding, input, cannon and vehicle persistence. No user saves.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const FLEET_STATE := preload("res://runtime/FleetState.gd")
const CRUSH := preload("res://gameplay/street_physics/HeavyVehicleCrush.gd")
var world: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("TANK_DRIVER PASS " if ok else "TANK_DRIVER FAIL ")+label)
	if not ok: failures.append(label)
func settle(frames := 5) -> void:
	for index in frames: await physics_frame

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(120).timeout.connect(func(): push_error("TANK_DRIVER timeout"); quit(2))
	seed(28092026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for index in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play and world.production.no_save,"real Main ready without saves")
	if not failures.is_empty(): quit(1); return
	world.gameplay.set_physics_process(false)
	world.gameplay.police_air.set_physics_process(false)
	world.dispatch.set_physics_process(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var tank := VEHICLE.new()
	tank.archetype = "army_tank"
	tank.vehicle_id = "tank_control_test"
	world.add_child(tank)
	tank.set_physics_process(false)
	var spot := Vector3.INF
	for candidate in world.dispatch.router.spawn_candidates(world.player.global_position,12.0,95.0,14.0):
		world.production.region.prepare_collision_at(candidate.point)
		await settle(2)
		if not world.dispatch._space_clear(Vector3(7.3,3.5,12),candidate.point,candidate.yaw,world.dispatch.no_exclusions): continue
		spot = candidate.point
		tank.place(spot,candidate.yaw)
		break
	check(spot.is_finite(),"tank and door placed on a physically clear road")
	if not spot.is_finite(): world.free(); quit(1); return
	world.production.region.set_focus(spot)
	check(tank.max_health >= 3000,"armor has greater durability than ordinary vehicles")
	tank.receive_damage(100)
	check(is_equal_approx(tank.max_health-tank.health,40.0),"armor absorbs 60 percent of incoming damage")
	tank.receive_damage(-100)
	tank.receive_damage(NAN)
	check(is_equal_approx(tank.max_health-tank.health,40.0),"invalid damage cannot heal or poison health")
	tank.restore_health(1488.0)
	var snapshot := FLEET_STATE.capture(tank,"harbor")
	check(FLEET_STATE.validate(snapshot),"damaged armored vehicle produces a valid save")
	world.driving.car = tank
	world.session.state.world_state.vehicles = [snapshot]
	tank.repair()
	world.production._restore_player_vehicle()
	check(is_equal_approx(tank.health,1488.0),"real load restores exact health without applying armor twice")
	tank.repair()
	check(is_equal_approx(tank.health,3000.0),"repair restores full armor")
	var compact := VEHICLE.new()
	compact.archetype = "sport_coupe"
	world.add_child(compact)
	compact.set_physics_process(false)
	compact.position = spot+Vector3(20,0,20)
	CRUSH.apply_saved(compact,0.26)
	var crushed := FLEET_STATE.capture(compact,"harbor")
	check(FLEET_STATE.validate(crushed) and is_equal_approx(crushed.heavy_crush_ratio,0.26),"crushed hull survives snapshot")
	for invalid in [-1.0,0.0,0.8,2.0,NAN,"broken"]:
		crushed.heavy_crush_ratio = invalid
		check(not FLEET_STATE.validate(crushed),"malformed crushed state rejected: "+str(invalid))
	compact.repair()
	check(not compact.has_meta("heavy_crush_ratio") and compact.shape.shape is BoxShape3D,"repair restores the physical hull")
	compact.queue_free()
	world.player.teleport(tank.driver_door_anchor(-1))
	world.player.input_locked = false
	await settle(3)
	check(world.driving.interact(),"player can board the tank through its actual door")
	for index in 240:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active(): break
	check(world.driving.occupied and world.driving.car == tank and not tank.input_locked,"boarding animation transfers tank control")
	var driver := tank.get_node("TankDriverControls")
	check(driver.active_gameplay() == world.gameplay,"cannon controls activate only for the seated player")
	var controls := root.get_node("GameInput")
	check(InputMap.action_get_events("tank_fire").any(func(event): return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT),"default mouse click fires cannon")
	check(InputMap.action_get_events("tank_fire").any(func(event): return event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B),"gamepad fire is separate from accelerator")
	controls.touch_aim = Vector2.RIGHT
	await settle(120)
	check(tank.tank_cannon.is_aligned(world.gameplay.aim_point,.10),"turret follows independent aim while chassis stays still")
	var before: int = tank.tank_cannon.shot_count
	Input.action_press("tank_fire")
	await settle(8)
	Input.action_release("tank_fire")
	check(tank.tank_cannon.shot_count == before+1,"held fire launches one shell and respects reload")
	check(not tank.tank_cannon.shells.is_empty() or tank.tank_cannon.impact_count > 0,"input launches a real moving shell")
	world.session.state.place_id = "maciota"
	check(driver.active_gameplay() == null,"garage disables cannon input")
	tank.tank_cannon.cooldown = 0
	check(not tank.tank_cannon.fire(world.gameplay,false),"garage blocks cannon even via direct fire API")
	world.session.state.place_id = ""
	tank.input_locked = true
	check(driver.active_gameplay() == null,"boarding or scripted input lock blocks cannon")
	tank.input_locked = false
	controls.remapping = true
	check(driver.active_gameplay() == null,"binding editor cannot fire cannon")
	controls.remapping = false
	paused = true
	check(driver.active_gameplay() == null,"pause blocks cannon")
	paused = false
	controls.touch_aim = Vector2.ZERO
	check(world.driving.leave(),"player can leave tank normally")
	# Truck boarding uses a 2.5s body tween followed by door closing.
	for index in 240:
		await physics_frame
		if not world.driving.is_body_transition_active(): break
	check(driver.active_gameplay() == null and not world.driving.occupied,"cannon deactivates after exit")
	world.queue_free()
	await settle(8)
	print("TANK_DRIVER checks=%d failures=%s" % [checks,failures])
	quit(0 if failures.is_empty() else 1)
