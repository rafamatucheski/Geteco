extends SceneTree
## Os clipes da UAL (biblioteca "ual") chegam ao Actor do jogador e passam pela camada
## de combate: entram com mistura, mudam a pose e devolvem o repouso ao terminar.
const ACTOR := preload("res://scripts/Actor.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	print(("CASE PASS " if ok else "CASE FAIL ") + label + ((" | " + detail) if detail != "" else ""))
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	shape.shape = box
	shape.position.y = -0.1
	floor.add_child(shape)
	stage.add_child(floor)
	var actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	stage.add_child(actor)
	await frames(3)
	for clip in ["ual/Pistol_Shoot", "ual/Pistol_Reload", "ual/Pistol_Idle", "ual/Punch_Jab", "ual/Sitting_Idle", "ual/Death01"]:
		check(actor.animation.has_animation(clip), "clipe " + clip + " existe no jogador")
	var idle: Array = actor._idle_pose.duplicate(true)
	for clip in ["ual/Pistol_Shoot", "ual/Pistol_Reload", "ual/Death01"]:
		actor.combat_clip = clip
		actor.combat_clip_time = 0.4
		await frames(12)
		var moved := 0.0
		var now: Array = actor._capture_pose()
		for bone in mini(idle.size(), now.size()):
			moved = maxf(moved, (idle[bone][1] as Quaternion).angle_to(now[bone][1] as Quaternion))
		check(actor._combat_weight >= 1.0 and moved > 0.3, clip + " domina o corpo e muda a pose", "peso=%.2f maior giro=%.2f rad" % [actor._combat_weight, moved])
		actor.combat_clip = ""
		await frames(30)
		check(actor._combat_weight == 0.0, clip + " solta o corpo ao terminar")
	print("UAL_CLIPS_ACTOR checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
