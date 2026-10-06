extends SceneTree
## Golpes corpo a corpo por quadros-chave (`MeleeMoveset`) no rig real do Dante:
## sequência de combo, contato à frente no instante do dano, continuidade das
## articulações, arma sem giro brusco, pés plantados, hit-stop e acentos de recarga.
## Não mede se o golpe "fica bonito" — para isso há `capture/capture_melee_filmstrip.gd`.
const ACTOR = preload("res://scripts/Actor.gd")
const POSE = preload("res://gameplay/WeaponRigPose.gd")
const MOVES = preload("res://gameplay/MeleeMoveset.gd")
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
const DATA = preload("res://gameplay/WeaponPoseData.gd")
const DT := 1.0 / 60.0
const HEAD_RADIUS := 0.14
var failures: Array[String] = []
var checks := 0
var actor

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("MELEE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func step(pose, id: String, reloading := false, progress := 0.0) -> Dictionary:
	actor._pose_locomotion(Vector3.ZERO, 3.5, Vector3.ZERO, 0.0, DT)
	var packet: Dictionary = pose.update(id, DT, true, reloading, progress, false, false, actor.phase)
	actor.set_combat_weapon_pose(id, packet)
	actor._apply_combat_weapon_pose()
	return packet

func foot(side: String) -> Vector3:
	return actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor._combat_bones[side + "Foot"]).origin)

## Folga entre a arma (eixo do cabo à ponta, com o raio do barril/lâmina) e a
## cabeça do Dante (esfera sobre o osso Head que cobre cabelo e barba: a malha da
## cabeça mede ±0,12 m em X e 0,25 m em altura). Negativo = atravessa.
func head_clearance(id: String) -> float:
	var sk: Skeleton3D = actor.skeleton
	var base: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone("Head")).origin)
	var top: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone("head_end")).origin)
	var center := base.lerp(top, 0.4)
	var weapon: Transform3D = actor.combat_weapon_transform(DATA.GRIPS[id])
	var a: Vector3 = weapon * Vector3(0, 0, 0.17)
	var b: Vector3 = weapon * Vector3(0, 0, -0.50)
	var nearest := Geometry3D.get_closest_point_to_segment(center, a, b)
	var radius := 0.045 if id == "bat" else 0.06 # barril do taco; cabeça do machado
	return center.distance_to(nearest) - HEAD_RADIUS - radius

func run() -> void:
	actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	root.add_child(actor)
	actor.set_physics_process(false)
	await process_frame
	for id in ["fists", "knuckles", "bat", "axe"]:
		var pose = POSE.new()
		for i in 40: step(pose, id)
		var feet := {"Left": foot("Left"), "Right": foot("Right")}
		var hips_rest: Vector3 = actor.skeleton.get_bone_global_pose(actor.hips).origin
		var hips_travel := 0.0
		var torso_turn := 0.0
		var count: int = MOVES.moves(id).size()
		var cadence := float(CATALOG.WEAPONS[id].fire_interval)
		var contact := float(POSE.MELEE_CONTACT[id])
		var steps: Array[int] = []
		var heavy: Array[bool] = []
		var previous: Array = actor._capture_pose()
		var max_joint := 0.0
		var max_weapon := 0.0
		var last_basis: Basis = actor.combat_weapon_transform(DATA.GRIPS.get(id, Vector3.ZERO)).basis.orthonormalized()
		var foot_drift := 0.0
		var head_gap := INF
		var grip_gap := 0.0
		var grip_note := ""
		var head_note := ""
		var reach_ok := true
		var reach_note := ""
		for press in count + 1:
			pose.attack(id)
			steps.append(pose.combo_step)
			heavy.append(pose.heavy_attack())
			var frames := int(ceil(cadence / DT))
			for frame in frames:
				var packet := step(pose, id)
				var now: Array = actor._capture_pose()
				for bone in now.size():
					max_joint = maxf(max_joint, rad_to_deg((previous[bone][1] as Quaternion).angle_to(now[bone][1])))
				previous = now
				if id in ["bat", "axe"]:
					var basis: Basis = actor.combat_weapon_transform(DATA.GRIPS[id]).basis.orthonormalized()
					max_weapon = maxf(max_weapon, rad_to_deg(basis.get_rotation_quaternion().angle_to(last_basis.get_rotation_quaternion())))
					last_basis = basis
				for side in feet: foot_drift = maxf(foot_drift, (foot(side) - (feet[side] as Vector3)).length())
				if id in ["bat", "axe"]:
					var gap := head_clearance(id)
					# Mão de apoio dentro do cabo: distância da palma real ao eixo do cabo.
					var weapon: Transform3D = actor.combat_weapon_transform(DATA.GRIPS[id])
					var off_axis := Geometry3D.get_closest_point_to_segment(actor.combat_palm_position("Left"), weapon * Vector3(0, 0, 0.17), weapon * Vector3(0, 0, -0.30)).distance_to(actor.combat_palm_position("Left"))
					if off_axis > grip_gap:
						grip_gap = off_axis
						grip_note = "golpe %d t=%.2f s" % [pose.combo_step, pose.action_age]
					if gap < head_gap:
						head_gap = gap
						head_note = "golpe %d t=%.2f s" % [pose.combo_step, pose.action_age]
				hips_travel = maxf(hips_travel, actor.skeleton.get_bone_global_pose(actor.hips).origin.distance_to(hips_rest))
				torso_turn = maxf(torso_turn, absf(float(packet.get("torso_yaw", 0.0))))
				if absf(pose.action_age - contact) < DT * 0.5:
					# No instante do dano a ponta do golpe está à frente do peito.
					var forward: float
					if id in ["bat", "axe"]:
						var head: Vector3 = actor.combat_weapon_transform(DATA.GRIPS[id]) * Vector3(0, 0, -0.42)
						forward = -(actor.visual.to_local(head)).z
					else:
						var side := "Left" if pose.punch_left else "Right"
						forward = -(actor.visual.to_local(actor.combat_palm_position(side))).z
					if forward < (0.70 if id in ["bat", "axe"] else 0.42):
						reach_ok = false
						reach_note += " golpe%d=%.2f" % [press, forward]
				if bool(packet.get("melee_action", false)) == false and pose.action_age < contact: reach_ok = false
		var expected: Array[int] = []
		for press in count + 1: expected.append(press % count)
		check(steps == expected, "%s: sequência do combo %s" % [id, steps])
		check(heavy[count - 1] and not heavy[0] and not heavy[count], "%s: só o último golpe é o pesado %s" % [id, heavy])
		check(reach_ok, "%s: golpe à frente do corpo no contato%s" % [id, reach_note])
		check(max_joint < 35.0, "%s: articulação ≤ 35°/quadro (%.1f°)" % [id, max_joint])
		if id in ["bat", "axe"]: check(max_weapon < 50.0, "%s: arma sem giro brusco (%.1f°/quadro)" % [id, max_weapon])
		check(foot_drift < 0.03, "%s: pés plantados durante a sequência (%.3f m)" % [id, foot_drift])
		if id in ["bat", "axe"]: check(grip_gap < 0.035, "%s: mão de apoio no cabo (afastamento máximo %.3f m em %s)" % [id, grip_gap, grip_note])
		if id in ["bat", "axe"]: check(head_gap > 0.0, "%s: arma não atravessa a cabeça (folga mínima %.3f m em %s)" % [id, head_gap, head_note])
		# O corpo entra no golpe: peso/joelhos movem o quadril e o tronco gira.
		check(hips_travel > 0.03 and torso_turn > 0.4, "%s: quadril desloca %.3f m e tronco gira %.2f rad" % [id, hips_travel, torso_turn])
		# Parado além da janela, a sequência recomeça.
		for i in int(ceil((float(MOVES.CHAIN[id]) + 0.1) / DT)): step(pose, id)
		pose.attack(id)
		check(pose.combo_step == 0, "%s: pausa reinicia a sequência" % id)
		# Hit-stop: o relógio do golpe para no impacto e depois segue.
		for i in int(ceil(contact / DT)): step(pose, id)
		var age: float = pose.action_age
		pose.impact(id)
		for i in 2: step(pose, id)
		check(is_equal_approx(pose.action_age, age), "%s: hit-stop congela o golpe" % id)
		for i in 8: step(pose, id)
		check(pose.action_age > age + 0.05, "%s: golpe retoma depois do hit-stop" % id)
	# Recarga: acentos só nos instantes da linha do tempo, e ferrolho com retorno de mola.
	var reload = POSE.new()
	var quiet: Vector3 = reload.reload_targets("pistol", 0.30).kick
	var seat: Vector3 = reload.reload_targets("pistol", 0.46).kick
	check(quiet.length() < 0.0005 and seat.y > 0.008, "pistola: tranco no encaixe do carregador (%.4f) e nada fora (%.4f)" % [seat.y, quiet.length()])
	var pull := reload._rack(0.66 + 0.15 * POSE.RACK_PULL * 0.5, 0.66, 0.81)
	var release := reload._rack(0.66 + 0.15 * (POSE.RACK_PULL + (1.0 - POSE.RACK_PULL) * 0.5), 0.66, 0.81)
	check(pull > 0.6 and release < 0.6 and is_zero_approx(reload._rack(0.81, 0.66, 0.81)), "ferrolho puxa devagar e volta de estalo (%.2f → %.2f)" % [pull, release])
	print("MELEE_MOVESET checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
