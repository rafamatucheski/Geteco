extends SceneTree
## Integrated locomotion-to-rest acceptance. Requires --no-save --skip-arrival.

var world: Node
var player: Node
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	print(("IDLE PASS " if ok else "IDLE FAIL ") + label + ((" | " + detail) if not detail.is_empty() else ""))
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

func pose_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(player.skeleton): return result
	for index in player.skeleton.get_bone_count():
		result.append({
			"name": player.skeleton.get_bone_name(index),
			"position": player.skeleton.get_bone_pose_position(index),
			"rotation": player.skeleton.get_bone_pose_rotation(index)
		})
	return result

func pose_difference(reference: Array[Dictionary], actual: Array[Dictionary]) -> Dictionary:
	var max_position := 0.0
	var max_angle := 0.0
	var worst := ""
	for index in mini(reference.size(), actual.size()):
		var position_delta: float = reference[index].position.distance_to(actual[index].position)
		var angle_delta: float = reference[index].rotation.angle_to(actual[index].rotation)
		if position_delta > max_position or angle_delta > max_angle:
			worst = str(reference[index].name)
		max_position = maxf(max_position, position_delta)
		max_angle = maxf(max_angle, angle_delta)
	return {"position": max_position, "angle": max_angle, "bone": worst}

func exercise(label: String, sprinting: bool, reference: Array[Dictionary]) -> void:
	var start: Vector3 = player.global_position
	Input.action_press("move_right")
	if sprinting: Input.action_press("sprint")
	await frames(20)
	Input.action_release("move_right")
	if sprinting: Input.action_release("sprint")
	var moved: float = player.global_position.distance_to(start)
	await frames(45)
	var settled_start: Vector3 = player.global_position
	await frames(6)
	var idle_drift: float = player.global_position.distance_to(settled_start)
	var difference := pose_difference(reference, pose_snapshot())
	check(moved > (1.2 if sprinting else 0.6), label + " desloca Dante por entrada real", "distance=%.3f" % moved)
	check(idle_drift < 0.01, label + " cessa deslocamento ao soltar", "drift=%.4f" % idle_drift)
	check(float(player.get("_locomotion_weight")) <= 0.01 and float(difference.angle) < 0.10 and float(difference.position) < 0.04,
		label + " retorna à pose de repouso",
		"weight=%.4f phase=%.4f pose_angle=%.4f pose_position=%.4f bone=%s animation=%s" % [player.get("_locomotion_weight"), player.phase, difference.angle, difference.position, difference.bone, player.animation.current_animation])

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-save" not in args or "--skip-arrival" not in args:
		push_error("IDLE validator refuses to run without --no-save --skip-arrival")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play, 900):
		push_error("Production session did not become ready")
		quit(1)
		return
	player = world.player
	check(world.production.no_save, "sessão produtiva está em --no-save")
	await frames(30)
	var reference := pose_snapshot()
	check(not reference.is_empty(), "rig produtivo de Dante está disponível")
	await exercise("caminhar e parar", false, reference)
	await exercise("correr e parar", true, reference)
	print("DANTE_IDLE_ACCEPTANCE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
