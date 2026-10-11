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
	CATALOG.override.clear()
	# Catálogo real: cada escalão, nos dois sexos e em vários policiais; o corpo vem do arquivo de `ENTRIES`.
	for tier in 5:
		for index in [0, 1, 2, 3, 4, 5, 7, 8]:
			await _check_catalog_officer(tier, index)
	# Com o catálogo desligado (interruptor de medição/rollback): continua o corpo procedural do kit.
	CATALOG.override.clear()
	CATALOG.enabled = false
	var plain := MODEL.new()
	plain.tier = 0
	root.add_child(plain)
	plain.equip("pistol")
	for i in 6: await process_frame
	_check(plain.body != null and plain.body.get("skeleton") == null, "com o catálogo desligado o policial segue procedural")
	print("POLICIA_MESHY failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _check_tier(tier: int, index := -1, catalog := false) -> void:
	var tag := "escalão %d" % tier if not catalog else "escalão %d/policial %d" % [tier, index]
	var holder := Node3D.new()
	root.add_child(holder)
	var police := MODEL.new()
	police.tier = tier
	police.appearance_index = tier * 2 if index < 0 else index
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
		elif mesh_node.name.begins_with("Equip_") or mesh_node.name.begins_with("Acc_"): continue
		else: others += 1
	_check(skinned == 1, "%s: um único corpo visível (%d)" % [tag, skinned])
	_check(others == 0, "%s: nenhuma malha antiga ainda visível (%d)" % [tag, others])
	var equipment := body.find_children("Equip_*", "MeshInstance3D", true, false)
	# Corpo do catálogo real com equipamento na própria malha (SWAT/FBI/Exército): nada procedural por cima.
	var baked: bool = police._body_equipment_baked
	_check(equipment.size() == (0 if baked else (9 if tier >= 2 else 0)), "%s: equipamento %s (%d)" % [tag, "já na malha" if baked else "tático anexado", equipment.size()])
	_check((police.rappel_harness != null) == (tier >= 2), "%s: ponto de rapel só onde há equipamento" % tag)
	_check(not DEATH.joints_of(body).is_empty(), "%s: juntas das mortes do Mixamo" % tag)
	var skeleton: Skeleton3D = body.skeleton
	# Mira: as duas mãos nos pontos de contato da arma.
	for i in 40: police.update_pose(1.0 / 60.0, true, false, 0.0, 0.0); await process_frame
	var contacts: Array = police.weapon_hand_contacts()
	var right_error: float = body._meshy.palm_position(0).distance_to(contacts[0]) if contacts[0] is Vector3 else 99.0
	_check(right_error < 0.03, "%s: mão do lado -X no cabo ao mirar (%.1f mm)" % [tag, right_error * 1000.0])
	if contacts[1] is Vector3:
		var left_error: float = body._meshy.palm_position(1).distance_to(contacts[1])
		_check(left_error < 0.03, "%s: mão de apoio na arma ao mirar (%.1f mm)" % [tag, left_error * 1000.0])
	# Recarga em andamento: sem erro e mãos continuam finitas.
	for step in 30:
		police.update_pose(1.0 / 60.0, true, true, float(step) / 30.0, 0.0)
		await process_frame
	var hand := _bone_world(skeleton, "RightHand")
	_check(hand.is_finite() and hand.distance_to(police.global_position) < 2.5, "%s: mão estável durante a recarga" % tag)
	holder.queue_free()

## Policial com corpo escolhido pelo catálogo real: se há entrada para o escalão/sexo, o corpo é importado e passa
## nas mesmas verificações; sem entrada (tático feminino), segue o corpo procedural do kit.
func _check_catalog_officer(tier: int, index: int) -> void:
	var probe := MODEL.new()
	probe.tier = tier
	probe.appearance_index = index
	root.add_child(probe)
	for i in 4: await process_frame
	var imported: bool = is_instance_valid(probe.body) and probe.body.get("skeleton") != null
	var female: bool = bool(probe.get_meta("police_appearance", {}).get("woman", false))
	probe.queue_free()
	if not imported:
		_check(female and (tier == 2 or tier == 4), "escalão %d/policial %d: sem corpo no catálogo só para tático feminino" % [tier, index])
		return
	await _check_tier(tier, index, true)
