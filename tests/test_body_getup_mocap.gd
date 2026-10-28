extends SceneTree
## Levantar do chão com mocap (`BodyGetUp3D`, 28/10/2026) sem o mundo: um pedestre deitado de bruços e de
## costas escolhe o clipe certo, o primeiro quadro do clipe mantém a cabeça para onde ela caiu e o corpo
## termina de pé com a origem embaixo da pelve. Não confere a aparência (isso é a captura
## tests/capture/capture_vehicle_mocap.gd -- --scene=getup).
##   tools/run_godot_locked.sh --headless --path . --script res://tests/test_body_getup_mocap.gd
const GET_UP := preload("res://gameplay/street_physics/BodyGetUp3D.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	check(GET_UP.library() != null, "biblioteca npc_vehicle.res carrega")
	for case in [{"name": "bruços", "pitch": -PI * .5, "clips": ["getup_stomach"]},
			{"name": "costas", "pitch": PI * .5, "clips": ["getup_back", "getup_knocked"]}]:
		var person = ACTOR.new()
		person.identity = 77
		root.add_child(person)
		for frame in 3: await process_frame
		var visual: Node3D = person.visual
		var base: Transform3D = visual.transform
		# Deitado: o visual inteiro tomba em torno de X (a frente do modelo é o -Z do visual), cabeça para -Z.
		visual.transform = Transform3D(Basis(Vector3.RIGHT, float(case.pitch)), Vector3.UP * .15)
		var joints: Dictionary = preload("res://gameplay/MixamoDeath.gd").joints_of(visual)
		check(not joints.is_empty(), case.name + ": rig com as juntas do clipe")
		if joints.is_empty(): continue
		var head_before: Vector3 = joints.Head.global_position - joints.Pelvis.global_position
		head_before.y = 0.0
		var getup = GET_UP.new()
		check(getup.begin(person, visual, 100.0), case.name + ": começa o levantar")
		check(getup.clip_name in case.clips, case.name + ": clipe " + getup.clip_name + " em " + str(case.clips))
		for i in 30: getup.step(1.0 / 60.0)
		var head_after: Vector3 = joints.Head.global_position - joints.Pelvis.global_position
		head_after.y = 0.0
		check(head_before.normalized().dot(head_after.normalized()) > .6, case.name + ": cabeça continua para onde caiu (%.2f)" % head_before.normalized().dot(head_after.normalized()))
		check(absf(visual.rotation.x) < .01 and absf(visual.rotation.z) < .01, case.name + ": visual em pé, só a pelve deitada")
		var guard := 0
		while not getup.step(1.0 / 30.0) and guard < 1200: guard += 1
		check(getup.finished, case.name + ": termina (%d passos)" % guard)
		check(joints.Pelvis.global_position.y - person.global_position.y > .7, case.name + ": pelve na altura de pé (%.2f)" % (joints.Pelvis.global_position.y - person.global_position.y))
		var pelvis_xz: Vector3 = joints.Pelvis.global_position
		getup.finish(base)
		getup.release()
		var offset: Vector3 = pelvis_xz - person.global_position
		offset.y = 0.0
		check(offset.length() < .2, case.name + ": origem embaixo da pelve (%.2f m)" % offset.length())
		person.queue_free()
		await process_frame
	print("BODY_GETUP_MOCAP checks=", checks, " failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
