extends SceneTree
## Mede os clipes da espada e escudo no Dante: instante de maior velocidade da ponta da espada em cada
## golpe (vira o "pico" de Gameplay.SHIELD_ATTACKS) e para onde a lâmina e o escudo apontam parados,
## no espaço do corpo (frente = −Z do visual, que no dante.glb é +Z do modelo girado). Só imprime.
## Cópias de Gameplay.HAND_SWORD_HELD e SHIELD_FOREARM_LOCAL: carregar o Gameplay aqui puxaria o jogo inteiro.
const HAND_SWORD_HELD := Transform3D(Vector3(0.4527, 0.8895, -0.0622), Vector3(0.7037, -0.3992, -0.5877), Vector3(-0.5476, 0.2223, -0.8067), Vector3.ZERO)
const SHIELD_FOREARM_LOCAL := Transform3D(Basis(Vector3.UP, PI * .5), Vector3(-0.11, 0.17, 0.0))
const MODEL := preload("res://gameplay/SwordShieldModel.gd")
const CLIPS := ["ss_slash_downward", "ss_slash_cross", "ss_slash_power", "ss_kick", "ss_idle", "ss_walk", "ss_block_idle"]
const FPS := 60.0

func _initialize() -> void:
	var dante: Node3D = (load("res://assets/dante.glb") as PackedScene).instantiate()
	root.add_child(dante)
	var player := dante.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.add_animation_library("mixsword", load("res://assets/dante/mixamo/dante_mixamo_sword.res"))
	var skeleton := dante.find_child("Skeleton3D", true, false) as Skeleton3D
	var right := skeleton.find_bone("RightHand")
	var forearm := skeleton.find_bone("LeftForeArm")
	var hips := skeleton.find_bone("Hips")
	for clip_name in CLIPS:
		var clip: String = "mixsword/" + str(clip_name)
		if not player.has_animation(clip):
			print("SEM ", clip)
			continue
		var animation: Animation = player.get_animation(clip)
		var length := animation.length
		var previous := Vector3.INF
		var peak := 0.0
		var peak_time := 0.0
		var frames := int(ceil(length * FPS))
		for f in frames + 1:
			var time := minf(f / FPS, length)
			_pose(skeleton, animation, time)
			var hand := _chain(skeleton, right) * HAND_SWORD_HELD
			var tip := hand * MODEL.TIP
			if previous.is_finite():
				var speed := tip.distance_to(previous) * FPS
				if speed > peak:
					peak = speed
					peak_time = time
			previous = tip
		_pose(skeleton, animation, 0.0)
		var hand0 := _chain(skeleton, right) * HAND_SWORD_HELD
		var blade := (hand0 * MODEL.TIP - hand0.origin).normalized()
		var shield := _chain(skeleton, forearm) * SHIELD_FOREARM_LOCAL
		var face := -shield.basis.z.normalized()
		var hip := _chain(skeleton, hips).origin
		# No modelo do dante.glb a frente do corpo é +Z (o Actor gira o modelo em PI).
		print("CLIPE %s len=%.2f pico=%.2f s (%.1f m/s) lâmina0=(%.2f, %.2f, %.2f) escudo_face=(%.2f, %.2f, %.2f) escudo_pos=(%.2f, %.2f, %.2f)" % [clip_name, length, peak_time, peak, blade.x, blade.y, blade.z, face.x, face.y, face.z, shield.origin.x - hip.x, shield.origin.y, shield.origin.z - hip.z])
	# Pegada nova: no ss_idle, a ponta (−Z da arma) vai para a frente do corpo (+Z no dante.glb), um
	# pouco erguida. Gira a pegada atual em torno do próprio eixo da mão até lá e imprime o Transform3D.
	var idle: Animation = player.get_animation("mixsword/ss_idle")
	_pose(skeleton, idle, 0.0)
	var hand_global := _chain(skeleton, right).basis.orthonormalized()
	var want_global := Vector3(0, .35, .94).normalized()
	var want_local := (hand_global * HAND_SWORD_HELD.basis.orthonormalized()).inverse() * want_global
	var turn := Basis(Quaternion(Vector3(0, 0, -1), want_local.normalized()))
	var fixed := Transform3D(HAND_SWORD_HELD.basis.orthonormalized() * turn, Vector3.ZERO)
	var check := (hand_global * fixed.basis) * Vector3(0, 0, -1)
	print("PEGADA_NOVA ", var_to_str(fixed).replace("
", " "), " ponta_idle=", check)
	quit(0)

func _pose(skeleton: Skeleton3D, animation: Animation, time: float) -> void:
	for i in skeleton.get_bone_count(): skeleton.set_bone_pose(i, skeleton.get_bone_rest(i))
	for t in animation.get_track_count():
		var path := str(animation.track_get_path(t))
		var bone := skeleton.find_bone(path.get_slice(":", path.get_slice_count(":") - 1))
		if bone < 0: continue
		match animation.track_get_type(t):
			Animation.TYPE_ROTATION_3D: skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(t, time))
			Animation.TYPE_POSITION_3D: skeleton.set_bone_pose_position(bone, animation.position_track_interpolate(t, time))

## Pose global pela cadeia de pais (o cache de get_bone_global_pose fica velho fora do quadro).
func _chain(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var result := skeleton.get_bone_pose(bone)
	var parent := skeleton.get_bone_parent(bone)
	while parent >= 0:
		result = skeleton.get_bone_pose(parent) * result
		parent = skeleton.get_bone_parent(parent)
	return result
