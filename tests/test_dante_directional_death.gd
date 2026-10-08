extends SceneTree
## Morte do Dante pelo lado do golpe: frente, trás, esquerda e direita escolhem clipes diferentes,
## e o corpo cai no sentido do empurrão (quadril do Mixamo anda com a queda).
const ACTOR = preload("res://scripts/Actor.gd")
var failures: Array[String] = []
var actor

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("DIRECTIONAL_DEATH ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func frames(n: int) -> void:
	for tick in n: await physics_frame

func run() -> void:
	actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	root.add_child(actor)
	actor.set_physics_process(false)
	await frames(20)
	check(actor.animation != null and actor.animation.has_animation("mixamo/death_left"), "biblioteca mixamo carregada")
	var basis: Basis = actor.skeleton.global_transform.basis
	var front := (basis * Vector3(0, 0, 1)).normalized()
	var left := (basis * Vector3(1, 0, 0)).normalized()
	check(actor._directional_death_clip(front) == "mixamo/death_forward", "golpe pela frente -> cai para frente")
	check(actor._directional_death_clip(-front) == "dying_backwards", "golpe por trás -> cai para trás")
	check(actor._directional_death_clip(left) == "mixamo/death_left", "empurrão para a esquerda do Dante -> cai à esquerda")
	check(actor._directional_death_clip(-left) == "mixamo/death_right", "empurrão para a direita do Dante -> cai à direita")
	check(actor._directional_death_clip(Vector3.ZERO) == "", "sem direção -> sorteio antigo")
	# Queda real pela frente: o quadril deve terminar deslocado no sentido do empurrão.
	var before: Vector3 = actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(actor.hips).origin
	actor.on_player_death(-1, front)
	check(actor.last_death_clip == "mixamo/death_forward", "clipe usado na morte pela frente: " + actor.last_death_clip)
	await create_timer(4.2).timeout
	var after: Vector3 = actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(actor.hips).origin
	var moved := after - before
	check(moved.dot(front) > 0.4, "quadril andou para frente na queda: %.2f m" % moved.dot(front))
	print("DIRECTIONAL_DEATH_RESULT failures=", failures)
	quit(0 if failures.is_empty() else 1)
