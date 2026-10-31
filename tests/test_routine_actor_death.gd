extends SceneTree
## O caminho de dano compartilhado precisa terminar para modelos civis diretos e embrulhados.
var failures: Array[String] = []
var checks := 0
var deaths: Dictionary = {}
var actors: Array[Node3D] = []
var world: Node3D

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("ROUTINE_DEATH ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func on_death(_actor: Node3D, id: String) -> void:
	deaths[id] = int(deaths.get(id, 0)) + 1

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var director := preload("res://gameplay/routines_v1/RoutineDirector.gd").new()
	world.add_child(director)
	for id in ["ranger", "logger", "dock_worker", "fisher"]:
		var actor: Node3D
		if id == "dock_worker": actor = preload("res://gameplay/urban_v1/PortWorker.gd").new()
		elif id == "fisher":
			actor = preload("res://gameplay/urban_v1/PortVisitor.gd").new()
			actor.fishing = true
		else: actor = preload("res://gameplay/routines_v1/MountainResident.gd").new()
		actor.configure({"id":id, "kind":"dock_worker" if id == "dock_worker" else "mountain_resident", "role":id, "stationary":true, "position":Vector3(actors.size() * 3, 0, 0)})
		actor.died.connect(on_death.bind(id))
		actor.died.connect(director._port_worker_died.bind(id))
		world.add_child(actor)
		director.actors[id] = actor
		actors.append(actor)
		var body: Node3D = actor.model if id in ["dock_worker", "fisher"] else actor.model.body
		check(body.hand_provider.is_valid(), id + ": living hand pose is installed")
		actor.receive_damage(20.0)
		check(actor.health == 80.0 and not actor.dead and body.hand_provider.is_valid(), id + ": nonlethal damage preserves the hand pose")
		actor.receive_damage(1000.0)
		check(actor.dead and actor.collision_layer == 0 and actor.collision_mask == 0, id + ": fatal damage releases collision")
		check(deaths.get(id, 0) == 1, id + ": death signal completes exactly once")
		check(actor.has_meta("destroyed_cleanup"), id + ": normal corpse cleanup is scheduled")
		check(not body.hand_provider.is_valid() and body.hand_targets == [null, null], id + ": actual articulated hands are released")
		check(not director.actors.has(id) and director.port_respawn.get(id, 0) == 180.0, id + ": director starts respawn cooldown")
		if is_instance_valid(actor.carried_crate): check(not actor.carried_crate.visible, id + ": dead worker releases cargo pose")
		actor.receive_damage(1000.0)
		check(deaths.get(id, 0) == 1, id + ": repeated damage cannot emit a second death")
	if not failures.is_empty(): finish(); return
	await create_timer(12.5).timeout
	for index in actors.size(): check(not is_instance_valid(actors[index]), "corpse %d is freed after the production fade" % index)
	finish()

func finish() -> void:
	world.free()
	print("ROUTINE_DEATH checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
