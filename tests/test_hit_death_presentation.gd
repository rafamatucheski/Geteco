extends SceneTree
## Ferimento articulado e queda direcional na integração real do Actor civil.

const ACTOR := preload("res://scripts/Actor.gd")
var failures: Array[String] = []
var checks := 0

class Stage extends Node3D:
	var gameplay: Node = null

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func make_actor(stage: Stage, position: Vector3) -> Node3D:
	var actor := ACTOR.new()
	actor.global_position = position
	stage.add_child(actor)
	actor.set_physics_process(false)
	return actor

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	var source := Node3D.new()
	stage.add_child(source)
	var civil := make_actor(stage, Vector3.ZERO)
	await process_frame
	var model: Node3D = civil.visual.get_child(0) as Node3D
	var spine: Node3D = model.get("spine") as Node3D
	var baseline := spine.rotation.z
	source.position = Vector3(-3, 0, 0)
	civil.receive_damage(20.0, source)
	await create_timer(0.075).timeout
	var first_roll := spine.rotation.z - baseline
	check(civil.health == 80.0 and absf(first_roll) > 0.05, "tiro lateral move tronco sem duplicar dano")
	await create_timer(0.42).timeout
	source.position = Vector3(3, 0, 0)
	civil.receive_damage(20.0, source)
	await create_timer(0.075).timeout
	var second_roll := spine.rotation.z - baseline
	check(first_roll * second_roll < 0.0, "lados opostos produzem reações opostas")
	await create_timer(0.42).timeout
	check(absf(spine.rotation.z - baseline) < 0.05, "tronco retorna à locomoção após ferimento")
	civil.set_meta("invulnerable", true)
	var safe_health: float = civil.health
	civil.receive_damage(100.0, source)
	check(civil.health == safe_health and not civil.dead, "proteção impede dano e queda")
	civil.remove_meta("invulnerable")
	for direction in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT]:
		var victim := make_actor(stage, Vector3(10.0 * float(checks), 0, 0))
		await process_frame
		source.global_position = victim.global_position - direction * 3.0
		victim.receive_damage(200.0, source)
		await create_timer(1.25).timeout
		var orientation: Vector3 = victim.visual.rotation
		if direction == Vector3.BACK:
			check(victim.dead and orientation.x > 1.3, "tiro frontal derruba para trás")
		elif direction == Vector3.FORWARD:
			check(victim.dead and orientation.x < -1.3, "tiro pelas costas derruba para frente")
		else:
			check(victim.dead and orientation.z < -1.3, "tiro lateral derruba para o lado")
		check(absf(orientation.y) < 0.2, "queda mantém orientação da vítima")
	stage.queue_free()
	print("HIT_DEATH_PRESENTATION checks=%d failures=%s" % [checks, str(failures)])
	quit(0 if failures.is_empty() else 1)
