extends SceneTree
## PoliceModel com corpo importado do Meshy (via PoliceBodyCatalog.override, com um corpo qualquer do catálogo de
## pedestres como substituto): um só corpo visível, as duas mãos chegam à arma na mira e na recarga, equipamento
## tático anexado às juntas nos escalões que o têm e ponto de rapel presente. Não mede desempenho.
const MODEL := preload("res://gameplay/PoliceModel.gd")
const CATALOG := preload("res://gameplay/PoliceBodyCatalog.gd")
const DEATH := preload("res://gameplay/MixamoDeath.gd")
const SOURCE := "res://assets/civilians/meshy/pedestrians/m_medium_a.glb"
const WEAPONS := ["pistol", "smg", "m4a1", "m4a1", "m4a1"]
var failures: Array[String] = []

func _check(ok: bool, label: String) -> bool:
	print("POLICIA_MESHY ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func _initialize() -> void:
	_run.call_deferred()

func _bone_world(skeleton: Skeleton3D, short_name: String) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_" + short_name)).origin

func _run() -> void:
	for tier in 5:
		CATALOG.override[tier] = SOURCE
	for tier in 5:
		await _check_tier(tier)
	# Sem override e sem entradas no catálogo: continua o corpo procedural do kit.
	CATALOG.override.clear()
	var plain := MODEL.new()
	plain.tier = 0
	root.add_child(plain)
	plain.equip("pistol")
	for i in 6: await process_frame
	_check(plain.body != null and plain.body.get("skeleton") == null, "sem corpo no catálogo o policial segue procedural")
	print("POLICIA_MESHY failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _check_tier(tier: int) -> void:
	var tag := "escalão %d" % tier
	var holder := Node3D.new()
	root.add_child(holder)
	var police := MODEL.new()
	police.tier = tier
	police.appearance_index = tier * 2
	holder.add_child(police)
	police.equip(WEAPONS[tier])
	for i in 8: await process_frame
	var body: Node3D = police.body
	_check(is_instance_valid(body) and body.get("skeleton") != null, "%s: corpo importado instalado" % tag)
	if not is_instance_valid(body) or body.get("skeleton") == null: return
	var skinned := 0
	var others := 0
	for node in police.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or not mesh_node.is_visible_in_tree(): continue
		if police.weapon != null and police.weapon.is_ancestor_of(mesh_node): continue
		if mesh_node == police.muzzle_flash_3d: continue
		if mesh_node.skeleton != NodePath(): skinned += 1
		elif mesh_node.name.begins_with("Equip_"): continue
		else: others += 1
	_check(skinned == 1, "%s: um único corpo visível (%d)" % [tag, skinned])
	_check(others == 0, "%s: nenhuma malha antiga ainda visível (%d)" % [tag, others])
	var equipment := body.find_children("Equip_*", "MeshInstance3D", true, false)
	_check(equipment.size() == (9 if tier >= 2 else 0), "%s: equipamento tático anexado (%d)" % [tag, equipment.size()])
	_check((police.rappel_harness != null) == (tier >= 2), "%s: ponto de rapel só onde há equipamento" % tag)
	_check(not DEATH.joints_of(body).is_empty(), "%s: juntas das mortes do Mixamo" % tag)
	var skeleton: Skeleton3D = body.skeleton
	# Mira: as duas mãos nos pontos de contato da arma.
	for i in 40: police.update_pose(1.0 / 60.0, true, false, 0.0, 0.0); await process_frame
	var contacts: Array = police.weapon_hand_contacts()
	var right_error := _bone_world(skeleton, "RightHand").distance_to(contacts[0]) if contacts[0] is Vector3 else 99.0
	_check(right_error < 0.2, "%s: mão do lado -X no cabo ao mirar (%.3f m)" % [tag, right_error])
	if contacts[1] is Vector3:
		var left_error := _bone_world(skeleton, "LeftHand").distance_to(contacts[1])
		_check(left_error < 0.2, "%s: mão de apoio na arma ao mirar (%.3f m)" % [tag, left_error])
	# Recarga em andamento: sem erro e mãos continuam finitas.
	for step in 30:
		police.update_pose(1.0 / 60.0, true, true, float(step) / 30.0, 0.0)
		await process_frame
	var hand := _bone_world(skeleton, "RightHand")
	_check(hand.is_finite() and hand.distance_to(police.global_position) < 2.5, "%s: mão estável durante a recarga" % tag)
	holder.queue_free()
