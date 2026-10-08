extends SceneTree
## Real mine crew bodies and shared animation clock on a supported physics floor.
## Integration with real weapons/vehicles is covered by Main session validation.
const LIFE := preload("res://world/mining/MiningLife.gd")
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("MINING_WORKERS ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	for station in LAYOUT.worker_stations():
		var floor_body := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(12, .2, 12)
		collider.shape = box
		floor_body.add_child(collider)
		floor_body.position = LAYOUT.world(station.point) - Vector3.UP * .1
		scene.add_child(floor_body)
	var life := LIFE.new()
	scene.add_child(life)
	life.configure(scene)
	life.set_focus(LAYOUT.CENTER + Vector3(0, -28, 0))
	await frames(3)
	check(life._workers.size() == 6, "six authored crew bodies")
	var worker = life._workers[0]
	check(worker.has_method("receive_damage") and worker.is_in_group("v2_damageable"), "miners participate in the production damage contract")
	if not worker.has_method("receive_damage"):
		quit(1)
		return
	var fixture: Node3D = life._work_root.get_node_or_null("Station_sample_breaker")
	var fixture_position: Vector3 = fixture.global_position if fixture != null else Vector3.INF
	worker.receive_damage(NAN)
	worker.receive_damage(-10)
	check(worker.health == 100 and not worker.dead, "invalid damage cannot heal or poison health")
	worker.receive_damage(15)
	check(worker.health == 85 and worker.frightened > 0, "injury interrupts work and triggers retreat")
	var start: Vector3 = worker.global_position
	await frames(70)
	check(worker.global_position.distance_to(start) > .2 and worker.is_on_floor(), "injured miner moves on the real floor")
	check(fixture != null and fixture.global_position.is_equal_approx(fixture_position), "station equipment stays anchored when miner moves")
	worker.receive_damage(1000)
	check(worker.dead and worker.collision_layer == 0 and worker.collision_mask == 0, "fatal damage removes standing body collision")
	var health: float = worker.health
	worker.receive_damage(1000)
	check(worker.health == health, "corpse damage is idempotent")
	await frames(75)
	check(absf(worker.visual.rotation.x) + absf(worker.visual.rotation.z) > .5, "shared death fall remains visible instead of resuming work pose")
	life.suspend()
	await frames(2)
	check(life._workers.is_empty(), "suspension releases crew and physics")
	life.set_focus(LAYOUT.CENTER + Vector3(0, -28, 0))
	await frames(2)
	check(life._workers.size() == 5, "quick return does not resurrect the defeated station")
	life.set_focus(LAYOUT.CENTER + Vector3(500, 0, 0))
	await frames(2)
	life.set_focus(LAYOUT.CENTER)
	check(life._workers.size() == 5, "leaving before cooldown does not replace a worker")
	# Advance only the deadline, not the physics or production admission path.
	life._defeated["sample_breaker"] = Time.get_ticks_msec() / 1000.0 - .01
	life.set_focus(LAYOUT.CENTER)
	check(life._workers.size() == 5 and life._defeated.has("sample_breaker"), "elapsed cooldown cannot respawn a worker near the player")
	life.set_focus(LAYOUT.CENTER + Vector3(500, 0, 0))
	await frames(2)
	life.set_focus(LAYOUT.CENTER)
	await frames(3)
	check(life._workers.size() == 6 and life._defeated.is_empty(), "new shift fills the killed station after cooldown and distant return")
	var live := 0
	for replacement in life._workers:
		if not replacement.dead: live += 1
	# Distant authored stations deliberately sleep, so is_on_floor() is not
	# updated there. The replaced worker is within the live physics radius.
	var replacement = life._work_root.get_node("Miner_sample_breaker")
	check(live == 6 and replacement.is_on_floor() and replacement.health == 100, "replacement is alive and supported without duplicating stations")
	print("MINING_WORKERS_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
