extends SceneTree
## Finite smoke of the three new special thresholds in the real session.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const FIRE := preload("res://gameplay/emergency/Fire.gd")
var world
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(50).timeout.connect(func(): push_error("SPECIAL6 timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("SPECIAL6 ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for _i in count: await physics_frame

func until(predicate: Callable, count := 360) -> bool:
	for _i in count:
		if predicate.call(): return true
		await physics_frame
	return false

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_dispatch",true)
	root.add_child(world)
	if not await until(func(): return world.session != null and world.session.ready_for_play,1800): quit(1); return
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	# Resource sharing must not share incident intensity or live node ownership.
	var first = FIRE.new()
	var second = FIRE.new()
	first._ensure_visuals()
	second._ensure_visuals()
	first.intensity = .2
	second.intensity = 1.0
	first._apply_intensity()
	second._apply_intensity()
	check(first.flames != second.flames and first.flames.process_material == second.flames.process_material and first.flames.amount_ratio < second.flames.amount_ratio,"cached fire shares resources, independent live intensity")
	first.free()
	second.free()
	var car = world.driving.car
	var region = world.production.region
	region._suspend_chunk_vehicles(region._cell(car.global_position))
	check(car.get_meta("awaiting_ground",false) and not car.is_physics_processing() and is_zero_approx(car.velocity.y),"chunk retirement suspends car before floor removal")
	check(await until(func(): return car.is_physics_processing() and not car.has_meta("awaiting_ground"),120),"supported car resumes through normal population tick")
	for id in ["harbor_sewer","santa_mare_hold","mountain_mystery_cave"]:
		await access(id)
	print("SPECIAL6_RESULT checks=",checks," failures=",failures.size())
	world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)

func access(id: String) -> void:
	var session = world.session
	var helper = session.special_place_entrance
	var definition := PLACES.get_definition(id)
	var door: Vector3 = helper._door(id)
	world.player.automatic_direction = Vector3.ZERO
	world.production._update_physical_residency(door)
	world.production._commit_logical_region(definition.region)
	world.player.teleport(door+Vector3(0,.08,2))
	await frames(30)
	check(session.nearest().get("id","") != "enter" and session.state.place_id.is_empty(),id+" proximity has no E and does not transfer")
	if id != "mountain_mystery_cave":
		check(is_instance_valid(helper.hatch) and helper.hatch.open_amount > .95,id+" actual hatch opens nearby")
	world.player.automatic_direction = Vector3.FORWARD
	var entered := await until(func(): return session.state.place_id == id)
	world.player.automatic_direction = Vector3.ZERO
	check(entered,id+" walking enters")
	if not entered:
		print("SPECIAL6_POSITION ",id," player=",world.player.global_position," door=",door," busy=",helper.busy)
		return
	await until(func(): return not helper.busy and not session.is_transition_blocked())
	check(not world.player.input_locked and session.position_clear(world.player.global_position+Vector3.UP*.04),id+" spawn clear and control released")
	var exit: Vector3 = session.room.exit_position
	world.player.teleport(exit+Vector3(0,.08,-1.5))
	await frames(3)
	world.player.automatic_direction = Vector3.BACK
	var left := await until(func(): return session.state.place_id.is_empty())
	world.player.automatic_direction = Vector3.ZERO
	check(left,id+" walking exits")
	if not left: return
	await until(func(): return not helper.busy)
	await frames(5)
	check(not world.player.input_locked and not world.camera._store_focus_active and session.position_clear(world.player.global_position+Vector3.UP*.04),id+" clear return with control and camera released")
