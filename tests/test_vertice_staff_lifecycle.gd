extends SceneTree
## Os funcionários de produção precisam sair do registro da empresa quando a limpeza de cadáveres os libera.
var checks := 0
var failures: Array[String] = []
var world: Node

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("VERTICE_STAFF ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func visit(point: Vector3) -> void:
	world.player.teleport(point)
	world.production.region.set_focus(point)
	await frames(30)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for frame in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "production session ready")
	if not failures.is_empty(): finish(); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = 9.0 / 24.0
	var depot = world.session.urban_operations.cargo_handling.depot
	await visit(depot.ORIGIN + Vector3(0, .1, 60))
	check(depot.staff.size() == 10, "all ten authored staff are registered")
	var survivors: Array = depot.staff.duplicate()
	var victims: Array = [depot.staff[0], depot.staff[2]]
	for entry in victims:
		survivors.erase(entry)
		entry.actor.receive_damage(1000.0)
		check(entry.actor.dead and entry.actor.has_meta("destroyed_cleanup"), "fatal damage schedules real corpse cleanup")
		check(depot.staff.has(entry), "corpse stays registered until it leaves the scene")
	await create_timer(12.5).timeout
	for entry in victims:
		check(not is_instance_valid(entry.actor) and not is_instance_valid(entry.model), "cleanup freed actor and child model")
		check(not depot.staff.has(entry), "removed body has no stale company registration")
	check(depot.staff.size() == survivors.size(), "only surviving staff remain")
	# Para a linha de base que falha antes de exercitar outros consumidores obsoletos.
	if not failures.is_empty(): finish(); return
	await visit(depot.ORIGIN + Vector3(0, .1, 250))
	for entry in survivors:
		check(not entry.actor.is_physics_processing() and not entry.model.is_processing(), "distant survivors suspend normally")
	depot.set_region_active(false)
	depot.set_region_active(true)
	await visit(depot.ORIGIN + Vector3(0, .1, 60))
	for entry in survivors:
		check(is_instance_valid(entry.actor) and entry.model.is_processing(), "same surviving actor resumes on return")
	var speaker = survivors[1].actor
	await visit(speaker.global_position + Vector3(1, 0, 0))
	check(depot.nearest_action().get("target", "") == "vertice_staff", "survivor still offers conversation")
	check(depot.perform("vertice_staff"), "survivor conversation still works")
	# A remoção externa (por exemplo coleta de emergência) tem o mesmo limite de posse.
	var removed: Dictionary = survivors[0]
	removed.actor.queue_free()
	await frames(3)
	check(not depot.staff.has(removed), "external removal also unregisters staff")
	check(depot.staff.size() == survivors.size() - 1, "removal does not duplicate or drop other staff")
	finish()

func finish() -> void:
	if is_instance_valid(world): world.free()
	print("VERTICE_STAFF checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
