extends SceneTree
## Contrato dirigido da regressão em que Dante congelava no último quadro da
## passada. Exercita deslocamento real, bloqueio físico e camadas de combate.

const ACTOR := preload("res://scripts/Actor.gd")
const POSE := preload("res://gameplay/WeaponRigPose.gd")
var failures: Array[String] = []
var checks := 0
var actor

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	print(("CASE PASS " if ok else "CASE FAIL ") + label + ((" | " + detail) if detail != "" else ""))
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func floor_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, 0.2, 30)
	collision.shape = shape
	collision.position.y = -0.1
	body.add_child(collision)
	return body

func wall_at(point: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 2.0, 5.0)
	collision.shape = shape
	collision.position.y = 1.0
	body.add_child(collision)
	body.position = point
	return body

func pose_error(a: Array, b: Array) -> float:
	var error := 0.0
	for bone in mini(a.size(), b.size()):
		error = maxf(error, (a[bone][0] as Vector3).distance_to(b[bone][0] as Vector3))
		# Repouso vivo: só a coluna baixa respira (amplitude autoral 0,009 rad).
		# Os demais ossos continuam obrigados a voltar à pose, sem passada presa.
		if actor.skeleton.get_bone_name(bone) == "Spine02":
			var breath := (a[bone][1] as Quaternion).angle_to(b[bone][1] as Quaternion)
			if breath > 0.011: error = maxf(error, breath)
			continue
		error = maxf(error, (a[bone][1] as Quaternion).angle_to(b[bone][1] as Quaternion))
	return error

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(floor_body())
	actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	stage.add_child(actor)
	await frames(3)
	check(actor._idle_pose.size() == actor.skeleton.get_bone_count(), "repouso simétrico é cacheado para todo o esqueleto")
	check(actor.animation.current_animation == "Walking" and actor._locomotion_weight == 0.0, "inicia em repouso sem usar a T-pose", "anim=%s weight=%.3f" % [actor.animation.current_animation, actor._locomotion_weight])
	var right_arm: int = actor.skeleton.find_bone("RightArm")
	var right_hand: int = actor.skeleton.find_bone("RightHand")
	var left_foot: int = actor.skeleton.find_bone("LeftFoot")
	var right_foot: int = actor.skeleton.find_bone("RightFoot")
	var shoulder_y: float = actor.skeleton.get_bone_global_pose(right_arm).origin.y
	var hand_y: float = actor.skeleton.get_bone_global_pose(right_hand).origin.y
	var foot_delta: Vector3 = actor.skeleton.get_bone_global_pose(left_foot).origin - actor.skeleton.get_bone_global_pose(right_foot).origin
	check(hand_y < shoulder_y - 0.25 and absf(foot_delta.z) < 0.10, "postura livre tem braço baixo e pés alinhados", "hand=%.3f shoulder=%.3f foot_z=%.3f" % [hand_y, shoulder_y, foot_delta.z])

	actor.speed = 3.5
	actor.automatic_direction = Vector3.RIGHT
	var walk_start: Vector3 = actor.global_position
	await frames(18)
	check(actor.global_position.distance_to(walk_start) > 0.7 and actor._locomotion_weight > 0.99 and actor._run_weight < 0.01, "caminhada entra suavemente e acompanha deslocamento real", "move=%.3f weight=%.3f" % [actor.global_position.distance_to(walk_start), actor._locomotion_weight])
	actor.automatic_direction = Vector3.ZERO
	await frames(12)
	check(actor._locomotion_weight == 0.0 and pose_error(actor._capture_pose(), actor._idle_pose) < 0.002, "caminhada converge ao repouso sem congelar a passada", "weight=%.3f error=%.5f" % [actor._locomotion_weight, pose_error(actor._capture_pose(), actor._idle_pose)])

	actor.speed = 6.5
	actor.automatic_direction = Vector3.LEFT
	await frames(18)
	check(actor._locomotion_weight > 0.99 and actor._run_weight > 0.99, "corrida entra pela mesma transição", "move=%.3f run=%.3f" % [actor._locomotion_weight, actor._run_weight])
	actor.automatic_direction = Vector3.ZERO
	await frames(16)
	check(actor._locomotion_weight == 0.0 and actor._run_weight == 0.0 and pose_error(actor._capture_pose(), actor._idle_pose) < 0.002, "corrida converge ao mesmo repouso", "move=%.3f run=%.3f" % [actor._locomotion_weight, actor._run_weight])

	actor.speed = 3.5
	var wall := wall_at(actor.global_position + Vector3.RIGHT * 1.1)
	stage.add_child(wall)
	actor.automatic_direction = Vector3.RIGHT
	await frames(45)
	check(actor._locomotion_weight == 0.0 and actor.get_slide_collision_count() > 0, "parede usa velocidade real e encerra a passada", "weight=%.3f collisions=%d" % [actor._locomotion_weight, actor.get_slide_collision_count()])
	actor.automatic_direction = Vector3.ZERO
	wall.queue_free()
	await frames(2)
	actor.automatic_direction = Vector3.LEFT
	await frames(12)
	actor.automatic_direction = Vector3.ZERO
	await frames(12)
	check(actor._locomotion_weight == 0.0 and pose_error(actor._capture_pose(), actor._idle_pose) < 0.002, "interrupção de movimento automático termina em repouso")

	var weapon_pose := POSE.new()
	var frame: Dictionary
	for tick in 20: frame = weapon_pose.update("pistol", 1.0 / 60.0, true, false, 0.0, false, false, 0.0)
	actor.combat_facing = 0.0
	actor.combat_stance = "gun"
	actor.set_combat_weapon_pose("pistol", frame)
	await frames(2)
	check(actor._locomotion_weight == 0.0 and not actor.combat_weapon_pose.is_empty(), "mira parada preserva repouso e postura de arma")
	var palm_before: Vector3 = actor.combat_palm_position("Right")
	weapon_pose.attack("pistol")
	for tick in 3: frame = weapon_pose.update("pistol", 1.0 / 60.0, true, false, 0.0, false, false, 0.0)
	actor.set_combat_weapon_pose("pistol", frame)
	await frames(2)
	check(actor.combat_palm_position("Right").distance_to(palm_before) > 0.002, "recuo continua alterando a empunhadura sobre o repouso")

	actor.combat_weapon_pose = {}
	actor.combat_weapon_id = ""
	actor.combat_stance = ""
	actor.combat_clip = "Attack"
	actor.combat_clip_time = 0.7
	await frames(2)
	check(actor._combat_weight > 0.0, "golpe entra pela camada de combate")
	actor.combat_clip = ""
	await frames(45) # Inclui os dois passos do giro iniciado pela mira.
	check(actor._combat_weight == 0.0 and actor.animation.current_animation == "Walking" and pose_error(actor._capture_pose(), actor._idle_pose) < 0.002, "golpe termina no repouso, não no último passo", "combat=%.3f anim=%s" % [actor._combat_weight, actor.animation.current_animation])

	print("ACTOR_LOCOMOTION_IDLE checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
