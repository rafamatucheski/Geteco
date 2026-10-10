extends SceneTree
## Contrato do corpo único do mecânico (MeshyRigBody): sem corpo duplicado, esqueleto leve, altura, pés
## no chão ao andar, mãos no alvo, sentar, juntas que a queda e as mortes do Mixamo procuram, e as
## medidas padrão do CivilianModel intactas para os demais NPCs. Não mede desempenho.
const MECHANIC := preload("res://assets/maciota/MechanicModel.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
const DEATH := preload("res://gameplay/MixamoDeath.gd")
var failures: Array[String] = []

func _check(ok: bool, label: String) -> bool:
	print("MESHY_MECHANIC ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func _initialize() -> void:
	_run.call_deferred()

func _bone_world(skeleton: Skeleton3D, short_name: String) -> Vector3:
	var index := skeleton.find_bone("mixamorig_" + short_name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin

func _run() -> void:
	# Regressão da refatoração: um CivilianModel comum mantém as medidas do kit.
	var plain := CIVILIAN.new()
	root.add_child(plain)
	await process_frame
	_check(is_equal_approx(plain.thigh_len, KIT.THIGH) and is_equal_approx(plain.shin_len, KIT.SHIN) and is_equal_approx(plain.upper_arm_len, KIT.UPPER_ARM)
		and is_equal_approx(plain.forearm_len, KIT.FOREARM) and is_equal_approx(plain.ankle_height, KIT.ANKLE_HEIGHT) and is_equal_approx(plain.pelvis_y, CIVILIAN.PELVIS_Y),
		"CivilianModel comum mantém as medidas do kit")
	plain.queue_free()

	var walker := Node3D.new()
	root.add_child(walker)
	var mechanic := MECHANIC.new() as Node3D
	walker.add_child(mechanic)
	for i in 10: await process_frame
	var body: Node3D = mechanic.body
	var skeleton: Skeleton3D = body.skeleton
	# Um só corpo visível, sem geometria escondida.
	var meshes: Array[MeshInstance3D] = []
	for node in mechanic.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null: meshes.append(node)
	_check(meshes.size() == 1, "existe uma única malha em todo o mecânico (%d)" % meshes.size())
	_check(meshes.size() == 1 and meshes[0].is_visible_in_tree() and meshes[0].skeleton != NodePath(), "a malha única é visível e usa o esqueleto")
	_check(mechanic.find_children("*", "AnimationPlayer", true, false).is_empty(), "nenhum AnimationPlayer sobrando")
	_check(mechanic.get_node_or_null("RigBody") == null, "sem RigBody antigo")
	var triangles := 0
	if meshes.size() == 1:
		for s in meshes[0].mesh.get_surface_count(): triangles += meshes[0].mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	_check(triangles == 4092, "4.092 triângulos (%d)" % triangles)
	_check(skeleton.get_bone_count() == 24, "esqueleto podado com 24 ossos (%d)" % skeleton.get_bone_count())
	_check(not DEATH.joints_of(body).is_empty(), "as 13 juntas das mortes do Mixamo existem")
	_check(mechanic.limbs.is_empty() and not mechanic.has_method("part"), "contrato antigo (limbs/part) sem geometria")
	var aabb: AABB = meshes[0].global_transform * meshes[0].get_aabb()
	_check(absf(aabb.size.y - 1.76) < 0.03, "altura de 1,76 m (%.3f)" % aabb.size.y)

	# Em pé: pontas dos pés no chão.
	var toe_left := _bone_world(skeleton, "LeftToeBase").y
	var toe_right := _bone_world(skeleton, "RightToeBase").y
	_check(toe_left > -0.01 and toe_left < 0.07 and toe_right > -0.01 and toe_right < 0.07, "em pé, pés no chão (%.3f / %.3f)" % [toe_left, toe_right])

	# Andando a 1,4 m/s: sempre um pé apoiado e sem deslizar muito.
	var slip_total := 0.0
	var slip_count := 0
	var min_ground := 1.0
	var max_toe := 0.0
	var last_z := {"L": INF, "R": INF}
	var last_t := 0
	for frame in 150:
		walker.position.z += 1.4 / 60.0
		await physics_frame
		await process_frame
		var tl := _bone_world(skeleton, "LeftToeBase")
		var tr := _bone_world(skeleton, "RightToeBase")
		if frame > 40:
			min_ground = minf(min_ground, minf(tl.y, tr.y))
			max_toe = maxf(max_toe, maxf(tl.y, tr.y))
		# Pé de apoio = o mais baixo; sua velocidade no mundo deve ser quase nula.
		var lower_key := "L" if tl.y < tr.y else "R"
		var lower: Vector3 = tl if lower_key == "L" else tr
		var now := Time.get_ticks_usec()
		if frame > 40 and last_z[lower_key] != INF and lower.y < 0.05:
			slip_total += absf(lower.z - float(last_z[lower_key])) * 60.0
			slip_count += 1
		last_z[lower_key] = lower.z
		last_z["L" if lower_key == "R" else "R"] = INF
		last_t = now
	var mean_slip := slip_total / maxf(float(slip_count), 1.0)
	_check(min_ground < 0.05, "andando, sempre há um pé no chão (mais baixo %.3f)" % min_ground)
	_check(max_toe < 0.45, "o pé de balanço sobe menos de 45 cm (%.3f)" % max_toe)
	_check(slip_count > 20 and mean_slip < 0.45, "pé de apoio desliza pouco: %.2f m/s em %d quadros" % [mean_slip, slip_count])

	# Mãos num alvo (arma, maca).
	var target_left := mechanic.to_global(Vector3(-0.2, 1.15, 0.42))
	var target_right := mechanic.to_global(Vector3(0.2, 1.15, 0.42))
	body.hand_provider = func() -> Array: return [target_left, target_right]
	for i in 20: await process_frame
	var hand_a := _bone_world(skeleton, "RightHand") # lado -X do corpo
	var hand_b := _bone_world(skeleton, "LeftHand")
	var reach_error := maxf(hand_a.distance_to(target_left), hand_b.distance_to(target_right))
	_check(reach_error < 0.12, "as duas mãos chegam ao alvo (erro %.3f m)" % reach_error)
	body.hand_provider = Callable()
	body.hand_targets = [null, null]

	# Sentar: a bacia desce.
	var hips_before := _bone_world(skeleton, "Hips").y
	body.sit_amount = 1.0
	for i in 30: await process_frame
	var hips_after := _bone_world(skeleton, "Hips").y
	_check(hips_after < hips_before - 0.25, "sentado, a bacia desce (%.2f → %.2f)" % [hips_before, hips_after])

	# Nenhum osso fora de lugar: a pele não explode.
	var farthest := 0.0
	for index in skeleton.get_bone_count(): farthest = maxf(farthest, (skeleton.global_transform * skeleton.get_bone_global_pose(index).origin).distance_to(mechanic.global_position))
	_check(farthest < 2.0, "todos os ossos a menos de 2 m do corpo (%.2f)" % farthest)
	print("MESHY_MECHANIC failures=", failures)
	quit(0 if failures.is_empty() else 1)
