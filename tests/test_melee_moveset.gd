extends SceneTree
## Golpes corpo a corpo por quadros-chave (`MeleeMoveset`) no rig real do Dante:
## sequência de combo, contato à frente no instante do dano, continuidade das
## articulações, arma sem giro brusco, pés plantados, hit-stop, acentos de recarga e
## defeitos de anatomia do rig inteiro (cotovelo virado para cima, antebraços
## cruzados, braço na frente do rosto).
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

## Folga entre a arma e o corpo, por parte: tronco (cápsula da coluna Spine02 →
## pescoço, raio 0,14 m: a jaqueta mede ±0,18 m de lado e 0,28 m de fundo), braços
## (ombro → cotovelo, 0,05 m) e antebraços (0,04 m); mais ~1,5 cm do cabo. Ignora
## o trecho do cabo dentro das mãos (8 cm de cada palma), que é a pegada.
## Negativo = a arma entra no corpo. Devolve [folga, parte].
func body_clearance(id: String) -> Array:
	var sk: Skeleton3D = actor.skeleton
	var bone := func(name: String) -> Vector3: return sk.to_global(sk.get_bone_global_pose(sk.find_bone(name)).origin)
	var parts := [["tronco", bone.call("Spine02"), bone.call("neck"), 0.155]]
	for side in ["Right", "Left"]:
		var label := "braço dir." if side == "Right" else "braço esq."
		parts.append([label, bone.call(side + "Arm"), bone.call(side + "ForeArm"), 0.065])
		parts.append(["ante" + label, bone.call(side + "ForeArm"), bone.call(side + "Hand"), 0.055])
	var weapon: Transform3D = actor.combat_weapon_transform(DATA.GRIPS[id])
	var palms := [actor.combat_palm_position("Right"), actor.combat_palm_position("Left")]
	var gap := INF
	var where := ""
	for i in 68:
		var point: Vector3 = weapon * Vector3(0, 0, 0.17 - float(i) * 0.01)
		if palms.any(func(palm): return point.distance_to(palm) < 0.08): continue
		for part in parts:
			var d: float = point.distance_to(Geometry3D.get_closest_point_to_segment(point, part[1], part[2])) - float(part[3])
			if d < gap:
				gap = d
				where = part[0]
	return [gap, where]

## Ossos no espaço do Actor (−Z é a frente).
func bone_local(name: String) -> Vector3:
	var sk: Skeleton3D = actor.skeleton
	return actor.visual.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone(name)).origin))

## Defeitos de anatomia do quadro atual (lista vazia = nenhum). São os que o usuário
## apontou nas tiras de quadros: braço "de baixo para cima", braços cruzados e braço
## tampando o rosto. Os limites são geométricos, não estéticos:
## - cotovelo para cima: o cotovelo sai da linha ombro–pulso mais de 2 cm, numa
##   direção com componente vertical > 0,5 (dobra invertida), sem estar atrás do ombro;
## - antebraços cruzados: os dois antebraços a menos de 7 cm um do outro fora dos
##   8 cm junto aos pulsos (onde as mãos se encontram no cabo);
## - mão acima da cabeça: o pulso acima do topo da cabeça (menos 3 cm);
## - braço na frente do rosto: algum ponto do braço até 30 cm à frente da cabeça,
##   a menos de 10 cm do centro dela de lado e entre o queixo e a testa. Soco
##   esticado na altura do queixo (mais de 30 cm à frente) não conta.
func anatomy_defects() -> Array[String]:
	var found: Array[String] = []
	for side in ["Right", "Left"]:
		var shoulder := bone_local(side + "Arm")
		var elbow := bone_local(side + "ForeArm")
		var wrist := bone_local(side + "Hand")
		var bend := elbow - Geometry3D.get_closest_point_to_segment_uncapped(elbow, shoulder, wrist)
		# Atrás do ombro (braço indo para trás na passada de corrida) o cotovelo sobe
		# naturalmente com a mão no quadril; só reprova à frente ou ao lado do corpo.
		if bend.length() > 0.02 and bend.normalized().y > 0.5 and elbow.z < shoulder.z + 0.05: found.append("cotovelo para cima " + side)
	var re := bone_local("RightForeArm")
	var rw := bone_local("RightHand")
	var le := bone_local("LeftForeArm")
	var lw := bone_local("LeftHand")
	var closest := Geometry3D.get_closest_points_between_segments(re, rw, le, lw)
	if closest[0].distance_to(closest[1]) < 0.07 and closest[0].distance_to(rw) > 0.08 and closest[1].distance_to(lw) > 0.08:
		found.append("antebraços cruzados")
	var head := bone_local("Head").lerp(bone_local("head_end"), 0.4)
	# Mão acima do topo da cabeça: nenhuma pose do jogo pede isso (a machadada pesada
	# para na orelha); aparecia com o tronco tombado entre os punhos.
	for side in ["Right", "Left"]:
		if bone_local(side + "Hand").y > bone_local("head_end").y - 0.03: found.append("mão acima da cabeça " + side)
	for side in ["Right", "Left"]:
		for segment in [[side + "Arm", side + "ForeArm"], [side + "ForeArm", side + "Hand"]]:
			var a := bone_local(segment[0])
			var b := bone_local(segment[1])
			for i in 11:
				var p := a.lerp(b, float(i) / 10.0)
				if p.z < head.z - 0.06 and p.z > head.z - 0.30 and absf(p.x - head.x) < 0.10 and p.y > head.y - 0.13 and p.y < head.y + 0.15:
					found.append("braço na frente do rosto " + side)
					break
	return found

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
		var edge_notes: Array[String] = []
		var edge_ok := true
		var last_head := Vector3.INF
		var arm_gap := INF
		var arm_note := ""
		var grip_gap := 0.0
		var grip_note := ""
		var head_note := ""
		var reach_ok := true
		var reach_note := ""
		var anatomy := {}
		for defect in anatomy_defects(): anatomy["prontidão: " + defect] = int(anatomy.get("prontidão: " + defect, 0)) + 1
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
				for defect in anatomy_defects():
					var key := "golpe %d: %s" % [pose.combo_step, defect]
					anatomy[key] = int(anatomy.get(key, 0)) + 1
				if id in ["bat", "axe"]:
					var basis: Basis = actor.combat_weapon_transform(DATA.GRIPS[id]).basis.orthonormalized()
					max_weapon = maxf(max_weapon, rad_to_deg(basis.get_rotation_quaternion().angle_to(last_basis.get_rotation_quaternion())))
					last_basis = basis
				for side in feet: foot_drift = maxf(foot_drift, (foot(side) - (feet[side] as Vector3)).length())
				if id in ["bat", "axe"]:
					var gap := head_clearance(id)
					var body := body_clearance(id)
					if float(body[0]) < arm_gap:
						arm_gap = float(body[0])
						arm_note = "%s, golpe %d t=%.2f s" % [body[1], pose.combo_step, pose.action_age]
					# Mão de apoio dentro do cabo do fim da preparação em diante (carregando, a
					# esquerda fica solta): distância da palma real ao eixo do cabo.
					var weapon: Transform3D = actor.combat_weapon_transform(DATA.GRIPS[id])
					var off_axis := Geometry3D.get_closest_point_to_segment(actor.combat_palm_position("Left"), weapon * Vector3(0, 0, 0.17), weapon * Vector3(0, 0, -0.30)).distance_to(actor.combat_palm_position("Left"))
					# A esquerda sai do passo e chega ao cabo durante a preparação (0,24 s).
					if float(packet.get("support_weight", 0.0)) >= 0.999 and pose.action_age >= 0.22 and off_axis > grip_gap:
						grip_gap = off_axis
						grip_note = "golpe %d t=%.2f s" % [pose.combo_step, pose.action_age]
					if gap < head_gap:
						head_gap = gap
						head_note = "golpe %d t=%.2f s" % [pose.combo_step, pose.action_age]
				hips_travel = maxf(hips_travel, actor.skeleton.get_bone_global_pose(actor.hips).origin.distance_to(hips_rest))
				torso_turn = maxf(torso_turn, absf(float(packet.get("torso_yaw", 0.0))))
				if id == "axe":
					# Fio do machado (+X do modelo) na frente do movimento no contato.
					var axe_frame: Transform3D = actor.combat_weapon_transform(DATA.GRIPS.axe)
					var head_now: Vector3 = axe_frame * Vector3(0, 0, -0.45)
					if absf(pose.action_age - contact) < DT * 0.5 and last_head != Vector3.INF:
						var leading := (axe_frame.basis * Vector3.RIGHT).normalized().dot((head_now - last_head).normalized())
						edge_notes.append("golpe%d=%.2f" % [pose.combo_step, leading])
						if leading < 0.5: edge_ok = false
					last_head = head_now
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
		if id == "axe": check(edge_ok and edge_notes.size() >= count, "axe: fio da lâmina na frente do golpe no contato (%s)" % ", ".join(edge_notes))
		var anatomy_notes: Array[String] = []
		for key in anatomy: anatomy_notes.append("%s ×%d" % [key, anatomy[key]])
		check(anatomy.is_empty(), "%s: rig sem cotovelo invertido, antebraços cruzados ou braço no rosto (%s)" % [id, ", ".join(anatomy_notes) if not anatomy.is_empty() else "nenhum quadro"])
		check(foot_drift < 0.03, "%s: pés plantados durante a sequência (%.3f m)" % [id, foot_drift])
		if id in ["bat", "axe"]:
			# Carregando parado (antes do primeiro golpe e depois da sequência).
			var still := POSE.new()
			for i in 60: step(still, id)
			var still_gap := body_clearance(id)
			check(anatomy_defects().is_empty(), "%s: carregando, rig sem defeito de anatomia %s" % [id, anatomy_defects()])
			check(float(still_gap[0]) > 0.0, "%s: carregando, a arma não entra no corpo (folga %.3f m, %s)" % [id, still_gap[0], still_gap[1]])
			check(arm_gap > 0.0, "%s: no golpe, a arma não entra no corpo (folga mínima %.3f m: %s)" % [id, arm_gap, arm_note])
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
