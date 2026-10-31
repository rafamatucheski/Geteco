extends "res://tests/test_seated_driver.gd"
## Regressão: um tornozelo ajustado ainda pode pôr o sapato visível abaixo do chassi.
## O deck original autoral do chassi do Aurora vai de Y=.205..275 em coordenadas do modelo.
const CHASSIS_DECK_TOP := .275

func _initialize() -> void:
	if "--candidate" in OS.get_cmdline_user_args():
		preload("res://runtime/RedesignedFleet.gd")._scenes["aurora_executive"] = load("res://artifacts/car-fleet-implementation-20261019/candidates/aurora_executive.scn")
	super._initialize()

func selected_ids() -> Array:
	return ["aurora_executive"]

func _check_fit(player, car, s: Dictionary, label: String) -> void:
	super._check_fit(player, car, s, label)
	var carpet_bottom := float(s.floor) - .025
	check(carpet_bottom >= CHASSIS_DECK_TOP - .001, label + " carpet rests above the authored chassis deck")
	var skin: MeshInstance3D = player._combat_skin
	check(skin != null and skin.skin != null and skin.mesh != null, label + " real skinned footwear exists")
	if skin == null or skin.skin == null or skin.mesh == null: return
	var skeleton: Skeleton3D = player.skeleton
	var bone_ids: Array[int] = []
	var matrices: Array[Transform3D] = []
	for bind in skin.skin.get_bind_count():
		var bone := skin.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(skin.skin.get_bind_name(bind))
		check(bone >= 0, label + " footwear bind resolves a real skeleton bone")
		if bone < 0: return
		bone_ids.append(bone)
		matrices.append(skeleton.get_bone_global_pose(bone) * skin.skin.get_bind_pose(bind))
	var bottoms := {"Left":INF, "Right":INF}
	var counts := {"Left":0, "Right":0}
	for surface in skin.mesh.get_surface_count():
		var arrays := skin.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or weights.is_empty(): continue
		var influences := int(weights.size() / vertices.size())
		for vertex in vertices.size():
			var point := Vector3.ZERO
			var side_weights := {"Left":0.0, "Right":0.0}
			for influence in influences:
				var offset := vertex * influences + influence
				var weight := weights[offset]
				if weight <= 0: continue
				var bind := bones[offset]
				point += (matrices[bind] * vertices[vertex]) * weight
				var bone_name := skeleton.get_bone_name(bone_ids[bind])
				for side: String in side_weights:
					if bone_name.begins_with(side) and ("Foot" in bone_name or "Toe" in bone_name): side_weights[side] += weight
			for side: String in side_weights:
				if float(side_weights[side]) <= .25: continue
				var local: Vector3 = car.to_local(skeleton.to_global(point))
				bottoms[side] = minf(float(bottoms[side]), local.y)
				counts[side] += 1
	for side: String in bottoms:
		check(int(counts[side]) > 0, label + " actual " + side + " footwear vertices inspected")
		check(float(bottoms[side]) >= CHASSIS_DECK_TOP - .005, label + " " + side + " shoe stays above chassis: %.4f >= %.4f" % [float(bottoms[side]), CHASSIS_DECK_TOP])
	print("AURORA_CABIN_FLOOR ", JSON.stringify({"chassis_top":CHASSIS_DECK_TOP,"floor":s.floor,"carpet_bottom":carpet_bottom,"shoe_bottoms":bottoms,"foot_vertices":counts}))
