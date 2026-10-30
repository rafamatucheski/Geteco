extends SceneTree
## Corte de membros no golpe letal forte de katana/machado (KatanaWounds, 29/10).
## Contratos: golpe forte corta o membro mais perto do ponto do golpe nos dois corpos (procedural e
## Meshy com skin), golpe fraco/arma sem fio/vivo/protegido não cortam, o pedaço cai com física, o pool
## é fixo (nenhum nó novo por corte), o limite de pedaços ativos vale e o interruptor desliga.
## Uso: tools/run_godot_locked.sh --headless --path . --script res://tests/test_melee_dismember.gd
const ACTOR := preload("res://scripts/Actor.gd")
const WOUNDS := preload("res://gameplay/KatanaWounds.gd")
const BODY_CATALOG := preload("res://assets/civilians/CivilianBodyCatalog.gd")
class Stage extends Node3D:
	var gameplay = null
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame

func _victim(stage: Node3D, position: Vector3, meshy: bool) -> Node3D:
	var previous := BODY_CATALOG.enabled
	BODY_CATALOG.enabled = meshy
	var victim := ACTOR.new()
	victim.identity = 3
	stage.add_child(victim)
	victim.global_position = position
	BODY_CATALOG.enabled = previous
	return victim

func _joint(actor: Node3D, joint_name: String) -> Node3D:
	for candidate in actor.find_children(joint_name, "MeshInstance3D", true, false):
		if (candidate as Node3D).visible: return candidate
	return actor.find_child(joint_name, true, false) as Node3D

func _active_slot(wounds: Node) -> Dictionary:
	var newest: Dictionary = {}
	for index: int in wounds._order: newest = wounds._slots[index]
	return newest

func run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(80, 0.2, 80)
	collider.shape = box; collider.position.y = -0.1
	floor.add_child(collider); stage.add_child(floor)
	var wounds := WOUNDS.new(); stage.add_child(wounds)
	await frames(2)
	var nodes_before := wounds.find_children("*", "", true, false).size()
	var toward := Vector3.FORWARD

	# Regras de golpe forte.
	check(WOUNDS.is_strong_cut("katana", 45.0, false) and WOUNDS.is_strong_cut("axe", 52.0, false), "full katana and axe hits are strong cuts")
	check(not WOUNDS.is_strong_cut("katana", 20.0, false), "reduced katana hit is weak")
	check(WOUNDS.is_strong_cut("axe", 20.0, true), "heavy combo finisher is strong even with low damage")
	check(not WOUNDS.is_strong_cut("bat", 80.0, true) and not WOUNDS.is_strong_cut("knife", 60.0, true), "blunt and short blades never sever")
	check(WOUNDS.is_strong_cut("sword_shield", 52.0, false), "full ice sword hit is a strong cut")

	# Corpo procedural.
	var victim := _victim(stage, Vector3(0, 0, -2), false)
	await frames(3)
	var head := _joint(victim, "Head")
	check(head is MeshInstance3D and (head as MeshInstance3D).mesh != null, "procedural victim has a meshed head joint")
	var head_point := WOUNDS.cut_point(victim, "katana", 0, toward)
	check(not wounds.try_sever(victim, "katana", 45.0, false, head_point, toward), "living target keeps every limb")
	victim.receive_damage(500, null)
	check(victim.dead, "procedural victim dies")
	check(not wounds.try_sever(victim, "katana", 20.0, false, head_point, toward), "weak lethal hit does not sever")
	check(not wounds.try_sever(victim, "bat", 60.0, true, head_point, toward), "bat does not sever")
	check(wounds.part_count() == 0 and head.visible, "weak hits leave the body intact")
	var head_start := head.global_position
	check(wounds.try_sever(victim, "katana", 45.0, false, head_point, toward), "strong lethal katana hit severs")
	check(not head.visible, "overhead cut takes the head (nearest bone to the impact)")
	check(_joint(victim, "left_upper_arm").visible and _joint(victim, "left_upper_leg").visible, "other limbs stay on the body")
	var slot := _active_slot(wounds)
	var shown := 0
	for part: MeshInstance3D in slot.meshes:
		if part.visible and part.mesh != null: shown += 1
	check(shown >= 1 and (slot.body as RigidBody3D).visible, "detached piece shows the body's own meshes")
	check((slot.meshes[0] as MeshInstance3D).mesh == (head as MeshInstance3D).mesh, "piece reuses the source mesh resource (no new mesh/material per piece)")
	check(not wounds._sever_joint(victim, head, toward), "the same head cannot be detached twice")
	var arm := _joint(victim, "left_upper_arm")
	var health_after_death: float = victim.health
	check(wounds.try_sever(victim, "axe", 52.0, false, WOUNDS._joint_center(arm), toward), "a deliberate second cut can detach another limb")
	check(not arm.visible and victim.get_meta("melee_removed_limbs", []).size() == 2, "each removed region has its own ledger entry")
	check(victim.health == health_after_death, "postmortem separation does not reapply damage")
	check(victim in wounds.candidates_near(victim.global_position, 4.0), "recent corpse remains targetable without a live collider")
	await frames(70)
	var piece := slot.body as RigidBody3D
	check(piece.global_position.y < head_start.y - 0.5 and piece.global_position.y > -0.4, "piece falls with physics and rests on the ground (y=%.2f)" % piece.global_position.y)
	for joint_name: String in WOUNDS.LIMBS:
		var remaining := wounds._visible_joint(victim, joint_name)
		if remaining != null: wounds._sever_joint(victim, remaining, toward)
	check(victim.get_meta("melee_removed_limbs", []).size() == WOUNDS.LIMBS.size() and not wounds.can_sever(victim), "body stops offering cuts after all its regions are gone (head, arms, legs, waist)")
	check(not wounds.try_sever(victim, "katana", 45.0, true, head_point, toward), "an exhausted body never generates duplicate pieces")

	# Machado nas pernas, outro corpo procedural.
	var second := _victim(stage, Vector3(3, 0, -2), false)
	await frames(3)
	second.receive_damage(500, null)
	var leg_point := WOUNDS.cut_point(second, "katana", 2, toward)
	check(wounds.try_sever(second, "katana", 45.0, false, leg_point, toward), "low katana cut severs")
	check(not _joint(second, "left_upper_leg").visible or not _joint(second, "right_upper_leg").visible, "low cut takes a leg")
	check(_joint(second, "Head").visible, "low cut keeps the head")

	# Corpo Meshy com skin.
	if BODY_CATALOG.available().is_empty():
		print("SKIP Meshy body: no GLB entries in this checkout")
	else:
		var meshy := _victim(stage, Vector3(-3, 0, -2), true)
		await frames(3)
		var model: Node = null
		for node in meshy.find_children("*", "Node3D", true, false):
			if "skeleton" in node and "mesh_node" in node: model = node; break
		var skeleton: Skeleton3D = model.skeleton if model != null else null
		check(is_instance_valid(skeleton), "Meshy victim has an imported skeleton")
		if is_instance_valid(skeleton):
			meshy.receive_damage(500, null)
			var arm_point := WOUNDS.cut_point(meshy, "axe", 1, toward)
			check(wounds.try_sever(meshy, "axe", 52.0, false, arm_point, toward), "axe severs the Meshy body")
			var cut: Dictionary = _active_slot(wounds)
			var bone := int(cut.bone)
			check(bone >= 0 and skeleton.get_bone_name(bone).ends_with("Arm"), "horizontal axe cut picks an arm bone (%s)" % (skeleton.get_bone_name(bone) if bone >= 0 else "-"))
			check(bone >= 0 and skeleton.get_bone_pose_scale(bone).x < 0.01, "severed bone collapses on the corpse")
			var skin_mesh := cut.skin_mesh as MeshInstance3D
			check(skin_mesh.mesh == model.mesh_node.mesh and skin_mesh.skin == model.mesh_node.skin and (cut.skeleton as Skeleton3D).visible, "Meshy piece reuses the body's mesh and skin")
			var piece_skeleton := cut.skeleton as Skeleton3D
			var hips := piece_skeleton.find_bone(skeleton.get_bone_name(0))
			check(piece_skeleton.get_bone_pose_scale(hips).x < 0.01 and piece_skeleton.get_bone_pose_scale(bone).x > 0.5, "Meshy piece keeps only the limb chain posed")
			var leg := wounds._visible_joint(meshy, "left_upper_leg")
			check(leg != null and wounds.try_sever(meshy, "axe", 52.0, false, WOUNDS._joint_center(leg), toward), "second Meshy cut detaches a different chain")
			var next_piece: Dictionary = _active_slot(wounds)
			var next_skeleton := next_piece.skeleton as Skeleton3D
			check(skeleton.get_bone_pose_scale(bone).x < 0.01 and next_skeleton.get_bone_pose_scale(bone).x < 0.01, "previous arm stays missing on corpse and is absent from new leg piece")

	var protected := _victim(stage, Vector3(0, 0, 7), false)
	await frames(2)
	protected.receive_damage(500, null)
	protected.set_meta("invulnerable", true)
	wounds.register_defeated(protected)
	check(not wounds.try_sever(protected, "axe", 52.0, true, protected.global_position + Vector3.UP, toward), "protected body never severs even if another system marked it dead")
	check(protected not in wounds.candidates_near(protected.global_position, 4.0), "protected body never enters corpse targeting")

	# Limite de pedaços ativos e pool fixo.
	for i in 9:
		var extra := _victim(stage, Vector3(-8 + i * 2, 0, -6), false)
		await frames(2)
		extra.receive_damage(500, null)
		wounds.try_sever(extra, "axe", 52.0, true, WOUNDS.cut_point(extra, "axe", 2, toward), toward)
	check(wounds.part_count() <= WOUNDS.MAX_PARTS and wounds.part_count() == WOUNDS.MAX_PARTS, "active pieces stay at the fixed limit (%d)" % wounds.part_count())
	check(wounds.pool_size() == WOUNDS.MAX_PARTS and wounds.find_children("*", "", true, false).size() == nodes_before, "cutting reuses the pool without creating nodes")

	# Interruptor.
	WOUNDS.enabled = false
	var off := _victim(stage, Vector3(0, 0, 4), false)
	await frames(2)
	off.receive_damage(500, null)
	check(not wounds.try_sever(off, "katana", 45.0, true, WOUNDS.cut_point(off, "katana", 0, toward), toward), "GETECO_MELEE_DISMEMBER=0 disables cutting")
	WOUNDS.enabled = true

	wounds.clear()
	check(wounds.part_count() == 0, "clear parks every piece")
	check(wounds._recent_bodies.is_empty(), "clear discards corpse targets on transition")
	stage.queue_free(); await process_frame
	print("MELEE_DISMEMBER checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
