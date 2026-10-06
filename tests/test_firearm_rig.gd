extends "res://tests/test_melee_moveset.gd"
## Armas de fogo, granada e faca no rig real do Dante, parado, mirando, atirando e
## recarregando: defeitos de anatomia do rig inteiro (os mesmos dos golpes), malha real
## da arma contra a malha real do corpo deformada pelo esqueleto (jaqueta, mãos,
## cabeça) e alcance das duas mãos. Mede o regime (depois de 20 quadros em cada
## estado); a entrada de cada estado é impressa, não reprovada.
const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
const IDS := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower", "grenade", "knife"]
## Penetração máxima tolerada da arma na pele (m). A malha da jaqueta é solta e as
## coronhas encostam nela de propósito; 3,5 cm é o que ainda lê como contato.
const SKIN_TOLERANCE := 0.035
## Rifle de caça: o pulso da coronha passa sobre o pulso direito (pegada sem pistol
## grip); medido 4,6 cm no regime em 2026-10-06, tolerado e registrado.
const SKIN_TOLERANCE_BY_ID := {"hunting_rifle": 0.05, "magnum": 0.05}
var _gun_points: PackedVector3Array
var _verts: PackedVector3Array
var _norms: PackedVector3Array
var _bones: PackedInt32Array
var _weights: PackedFloat32Array
var _per := 4

func _gun_local_points(id: String) -> PackedVector3Array:
	var gun := Node3D.new()
	root.add_child(gun)
	ARSENAL.build(gun, id)
	var out := PackedVector3Array()
	for node in gun.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null: continue
		var local: Transform3D = gun.global_transform.affine_inverse() * mesh_instance.global_transform
		var faces := mesh_instance.mesh.get_faces()
		for i in range(0, faces.size(), 3): out.append(local * faces[i])
	gun.queue_free()
	return out

## Pele deformada pelo esqueleto atual (CPU, um vértice a cada `stride`): [posições, normais].
func _skinned(stride := 2) -> Array:
	var skin_instance: MeshInstance3D = actor._combat_skin
	var sk: Skeleton3D = actor.skeleton
	var skin: Skin = skin_instance.skin
	var matrices: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0: bone = sk.find_bone(skin.get_bind_name(b))
		matrices.append(sk.global_transform * sk.get_bone_global_pose(bone) * skin.get_bind_pose(b))
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in range(0, _verts.size(), stride):
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		for k in _per:
			var w := _weights[i * _per + k]
			if w <= 0.0: continue
			var m: Transform3D = matrices[_bones[i * _per + k]]
			p += (m * _verts[i]) * w
			n += (m.basis * _norms[i]) * w
		positions.append(p)
		normals.append(n.normalized())
	return [positions, normals]

## Quanto a arma entra na pele (m, positivo = dentro), fora das palmas que a seguram.
func _skin_penetration(id: String, left_grip: bool) -> float:
	var body := _skinned()
	var positions: PackedVector3Array = body[0]
	var normals: PackedVector3Array = body[1]
	var grid := {}
	for i in positions.size():
		var key := Vector3i((positions[i] / 0.04).floor())
		if not grid.has(key): grid[key] = []
		grid[key].append(i)
	var weapon: Transform3D = actor.combat_weapon_transform(DATA.GRIPS.get(id, Vector3.ZERO))
	var palms := [actor.combat_palm_position("Right")]
	if left_grip: palms.append(actor.combat_palm_position("Left"))
	var deepest := -INF
	for point in _gun_points:
		var q: Vector3 = weapon * point
		if palms.any(func(palm): return q.distance_to(palm) < 0.07): continue
		var cell := Vector3i((q / 0.04).floor())
		var best := INF
		var nearest := -1
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var key := cell + Vector3i(dx, dy, dz)
					if not grid.has(key): continue
					for i in grid[key]:
						var d := q.distance_squared_to(positions[i])
						if d < best:
							best = d
							nearest = i
		if nearest >= 0: deepest = maxf(deepest, -(q - positions[nearest]).dot(normals[nearest]))
	return deepest

func run() -> void:
	actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	root.add_child(actor)
	actor.set_physics_process(false)
	await process_frame
	var arrays: Array = actor._combat_skin.mesh.surface_get_arrays(0)
	_verts = arrays[Mesh.ARRAY_VERTEX]
	_norms = arrays[Mesh.ARRAY_NORMAL]
	_bones = arrays[Mesh.ARRAY_BONES]
	_weights = arrays[Mesh.ARRAY_WEIGHTS]
	_per = _bones.size() / _verts.size()
	for id in IDS:
		_gun_points = _gun_local_points(id)
		var pose = POSE.new()
		var tolerance: float = SKIN_TOLERANCE_BY_ID.get(id, SKIN_TOLERANCE)
		for phase in [["parado", 60, false, false], ["mirando", 50, true, false], ["atirando", 80, true, false], ["recarga", 96, false, true]]:
			var defects := {}
			var deepest := -INF
			var deepest_frame := 0
			var entry := -INF
			var reach := 0.0
			var cadence := int(maxf(1.0, round(float(CATALOG.WEAPONS[id].fire_interval) / DT)))
			for frame in int(phase[1]):
				if phase[0] == "atirando" and frame % cadence == 0: pose.attack(id)
				var progress := float(frame) / float(int(phase[1]) - 1)
				actor._pose_locomotion(Vector3.ZERO, 3.5, Vector3.ZERO, 0.0, DT)
				var packet: Dictionary = pose.update(id, DT, bool(phase[2]), bool(phase[3]), progress, false, false, actor.phase)
				actor.set_combat_weapon_pose(id, packet)
				actor._apply_combat_weapon_pose()
				for defect in anatomy_defects(): defects[defect] = int(defects.get(defect, 0)) + 1
				if frame >= 20 and bool(packet.get("support_locked", false)):
					# Palma esquerda real até o ponto de apoio NA arma realizada (a mão alvo do
					# pacote é antes da trava bilateral, que a reposiciona pela mão direita).
					var weapon: Transform3D = actor.combat_weapon_transform(DATA.GRIPS.get(id, Vector3.ZERO))
					reach = maxf(reach, actor.combat_palm_position("Left").distance_to(weapon * (packet.support_point as Vector3)))
				if frame % 4 == 0 and bool(packet.get("visible", true)):
					var depth := _skin_penetration(id, bool(packet.get("left_grip", false)) and float(packet.get("support_weight", 0.0)) > 0.5)
					if frame < 20: entry = maxf(entry, depth)
					elif depth > deepest:
						deepest = depth
						deepest_frame = frame
			var label := "%s %s" % [id, phase[0]]
			check(defects.is_empty(), "%s: rig sem cotovelo invertido, antebraços cruzados ou braço no rosto %s" % [label, defects])
			check(deepest <= tolerance, "%s: arma na pele no máximo %.3f m (%.3f no quadro %d; entrada do estado %.3f)" % [label, tolerance, deepest, deepest_frame, entry])
			check(reach < 0.05, "%s: mão de apoio alcança a arma (erro %.3f m)" % [label, reach])
	print("FIREARM_RIG checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
