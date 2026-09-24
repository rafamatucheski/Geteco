extends SceneTree
## Production-connected shot -> perception -> flight -> routine resumption.
## Requires --no-save --skip-arrival and uses the director owned by ProductionWorld.

var world: Node
var director: Node
var witness: CharacterBody3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	print(("SHOT_RESUME PASS " if ok else "SHOT_RESUME FAIL ") + label + ((" | " + detail) if not detail.is_empty() else ""))
	if not ok:
		failures.append(label)
		push_error(label + ((" | " + detail) if not detail.is_empty() else ""))

func frames(count: int) -> void:
	for _index in count:
		await physics_frame

func wait_until(predicate: Callable, maximum_frames: int) -> bool:
	for _index in maximum_frames:
		if predicate.call(): return true
		await physics_frame
	return false

func ground(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 4.0, point - Vector3.UP * 4.0, 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else point

func aim_direction(direction: Vector3) -> void:
	var flat := direction.normalized()
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y = 0.0
	down.y = 0.0
	root.get_node("GameInput").touch_aim = Vector2(flat.dot(right.normalized()), flat.dot(down.normalized()))
	await frames(3)

func real_shot() -> void:
	Input.action_press("fire")
	await frames(2)
	Input.action_release("fire")
	await frames(2)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-save" not in args or "--skip-arrival" not in args:
		push_error("SHOT_RESUME validator refuses to run without --no-save --skip-arrival")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play and world.production.ready_for_play, 900):
		push_error("Production session did not become ready")
		quit(1)
		return
	check(world.production.no_save, "sessão produtiva está em --no-save")
	director = world.production.civilian_reactions
	check(is_instance_valid(director) and director.gameplay == world.gameplay, "ProductionWorld possui o diretor conectado ao Gameplay real")
	# Population streaming begins after session readiness. Wait for the real
	# producer instead of treating the first ready frame as an empty fixture.
	await wait_until(func():
		return world.people.any(func(person): return is_instance_valid(person) and person.route.size() > 1 and not person.controlled_automatically)
	, 360)
	for person in world.people:
		if is_instance_valid(person) and person.route.size() > 1 and not person.controlled_automatically:
			witness = person
			break
	check(is_instance_valid(witness), "população produtiva fornece testemunha com rotina")
	if not is_instance_valid(witness):
		quit(1)
		return
	var direction := Vector3.RIGHT
	var side := Vector3(0.0, 0.0, 1.0)
	witness.teleport(ground(world.player.global_position + side * 4.0) + Vector3.UP * 0.08)
	witness.controlled_automatically = false
	var route_before: PackedVector3Array = witness.route.duplicate()
	var speed_before: float = witness.speed
	var witness_id := witness.get_instance_id()
	world.session.state.economy.grant_reward("shot_resume_weapon", 1000)
	world.session.state.grant_weapon("pistol")
	world.session.state.equip_weapon("pistol")
	await frames(4)
	await aim_direction(direction)
	var ammo_before: int = int(world.session.state.get_ammo("pistol").magazine)
	await real_shot()
	check(int(world.session.state.get_ammo("pistol").magazine) == ammo_before - 1, "entrada fire produz disparo real e consome munição")
	check(await wait_until(func(): return director.reactors.has(witness_id), 90), "diretor produtivo percebe o tiro")
	check(witness.controlled_automatically and witness.speed >= 5.0, "testemunha entra em fuga")
	var flight_start := witness.global_position
	await frames(90)
	check(witness.global_position.distance_to(flight_start) > 2.0, "fuga desloca a testemunha", "distance=%.2f" % witness.global_position.distance_to(flight_start))
	check(await wait_until(func(): return not director.reactors.has(witness_id), 1200), "pânico e recuperação terminam sem intervenção")
	check(not witness.controlled_automatically and is_equal_approx(witness.speed, speed_before) and witness.route == route_before,
		"retomada devolve velocidade e rota originais",
		"speed=%.2f expected=%.2f route=%d expected_route=%d" % [witness.speed, speed_before, witness.route.size(), route_before.size()])
	var resumed_start := witness.global_position
	await frames(90)
	check(witness.global_position.distance_to(resumed_start) > 0.25, "rotina civil volta a mover a testemunha", "distance=%.2f" % witness.global_position.distance_to(resumed_start))
	print("CIVILIAN_SHOT_RESUME_ACCEPTANCE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
