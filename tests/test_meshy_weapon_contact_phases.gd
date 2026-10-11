extends SceneTree
## Mede o centro da palma apresentada contra a arma real, incluindo orientação e distância ao punho.
const MODEL := preload("res://gameplay/PoliceModel.gd")
const CATALOG := preload("res://gameplay/PoliceBodyCatalog.gd")
const POSES := preload("res://gameplay/WeaponPoseData.gd")
const SOURCES := ["patrol_m", "patrol_heavy", "patrol_f", "suit_m", "suit_f", "tactical_gray", "tactical_black"]
const LIMIT_MM := 30.0
var failures: Array[String] = []
var results: Array[Dictionary] = []

class Owner extends Node3D:
	var dead := false
	var is_player := false

func _initialize() -> void:
	Engine.max_fps = 60
	create_timer(120.0).timeout.connect(func(): push_error("Contatos excederam o prazo"); quit(3))
	_run.call_deferred()

func _hand(body: Node3D, side: int) -> Vector3:
	return body._meshy.palm_position(side)

func _run() -> void:
	CATALOG.enabled = true
	for source in SOURCES:
		CATALOG.override[2] = "res://assets/civilians/meshy/police/%s.glb" % source
		for weapon in ["smg", "m4a1"]:
			var police := MODEL.new()
			police.tier = 2
			police.appearance_index = 2
			root.add_child(police)
			police.equip(weapon)
			for step in 8: await process_frame
			if source == "suit_m":
				if not police.body.palm_grip_enabled or police.body.mesh_node.get_blend_shape_count() != 2:
					failures.append("terno não carregou calibração de palma e as duas formas de pega")
			for state in ["aim", "recoil", "reload", "run"]:
				if state == "run":
					# A transição para corrida demora; medir só os primeiros 24 quadros não cobria a pose plena.
					for warmup in 60:
						police.position.z -= 4.5 / 60.0
						police.update_pose(1.0 / 60.0, false, false, 0.0, 0.0)
						await process_frame
						await create_timer(0.0).timeout
					if police.body._run_w < .95:
						failures.append("%s/%s: corrida não estabilizou (%.3f)" % [source, weapon, police.body._run_w])
				var right_mm := 0.0
				var left_mm := 0.0
				for step in 24:
					if state == "recoil" and step % 6 == 0: police.attack()
					if state == "run": police.position.z -= 4.5 / 60.0
					police.update_pose(1.0 / 60.0, state != "run", state == "reload", float(step) / 23.0, 0.0)
					await process_frame
					await create_timer(0.0).timeout
					# Deixa a física/pose produtiva atualizar: não reposiciona ossos para satisfazer a asserção.
					var grip: Vector3 = police.weapon.global_transform * POSES.GRIPS[weapon]
					var support: Vector3 = police.weapon.global_transform * POSES.SUPPORT_GRIPS[weapon]
					if state == "reload": support = police.weapon_hand_contacts()[1]
					var right_sample := _hand(police.body, 0).distance_to(grip) * 1000.0
					var left_sample := _hand(police.body, 1).distance_to(support) * 1000.0
					if not is_finite(right_sample) or not is_finite(left_sample):
						push_error("Palma inválida em %s/%s/%s" % [source, weapon, state])
						quit(1)
						return
					right_mm = maxf(right_mm, right_sample)
					left_mm = maxf(left_mm, left_sample)
				var row := {"body": source, "weapon": weapon, "state": state, "right_mm": right_mm, "left_mm": left_mm}
				results.append(row)
				var ok := is_finite(right_mm) and is_finite(left_mm) and right_mm < LIMIT_MM and left_mm < LIMIT_MM
				print("MESHY_CONTATO ", "PASS " if ok else "FAIL ", JSON.stringify(row))
				if not ok: failures.append("%s/%s/%s" % [source, weapon, state])
			police.queue_free()
			await process_frame
	# Ao morrer e soltar a arma, a mão deve voltar a seguir a queda, sem orientação presa à mira anterior.
	CATALOG.override[2] = "res://assets/civilians/meshy/police/suit_m.glb"
	var owner := Owner.new()
	root.add_child(owner)
	var falling := MODEL.new()
	falling.tier = 2
	owner.add_child(falling)
	falling.equip("m4a1")
	for step in 30:
		falling.update_pose(1.0 / 60.0, true, false, 0.0, 0.0)
		await process_frame
	owner.dead = true
	if not preload("res://gameplay/MixamoDeath.gd").play(owner, falling, Vector3.RIGHT): failures.append("queda de policial armado não iniciou")
	for step in 20: await process_frame
	if falling.body.mesh_node.get_blend_shape_value(0) > .01 or falling.body.mesh_node.get_blend_shape_value(1) > .01:
		failures.append("mão permaneceu fechada na pega da arma após morrer")
	if falling.body._meshy._hand_frames != [null, null]: failures.append("orientação da arma permaneceu sobre a queda")
	owner.queue_free()
	await process_frame
	CATALOG.override.clear()
	var output_dir := "res://evidence/npc-meshy/hands-review-20261011"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var report := FileAccess.open(output_dir + "/weapon-contacts.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"limit_mm": LIMIT_MM, "results": results, "failures": failures}, "\t"))
	print("MESHY_CONTATO failures=", failures)
	quit(0 if failures.is_empty() else 1)
