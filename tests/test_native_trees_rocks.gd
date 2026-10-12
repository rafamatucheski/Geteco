extends SceneTree
## Sanidade geométrica das árvores e pedras nativas: normais para fora, contagem de triângulos e
## colisão coerente com a malha. Não mede aparência nem desempenho.
const PINE := preload("res://world/regions/NativePine.gd")
const ROCK := preload("res://world/regions/NativeRock.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	print(("ok   " if ok else "FAIL ") + label)
	if not ok: failures += 1

func outward_ratio(mesh: ArrayMesh, center_of: Callable, only_above := -1.0) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var good := 0
	var total := 0
	for i in verts.size():
		# Só o tronco (acima das raízes, que saem na horizontal).
		if only_above >= 0.0 and verts[i].y < only_above: continue
		total += 1
		if normals[i].dot(verts[i] - center_of.call(verts[i])) > 0.0: good += 1
	return float(good) / maxf(1.0, total)

func _init() -> void:
	for variant in ROCK.variant_count():
		var mesh := ROCK.mesh(variant, 1)
		var ratio := outward_ratio(mesh, func(_v): return Vector3(0, 0.1, 0))
		check(ratio > 0.9, "pedra %d: normais para fora (%.2f)" % [variant, ratio])
		check(ROCK.hull(variant).size() == 42, "pedra %d: casco com 42 vértices" % variant)
		print("     triângulos: ", mesh.get_faces().size() / 3)
	for variant in 8:
		for snowy in [false, true]:
			var node: Node3D = PINE.create(variant, snowy)
			var tris := 0
			var top := 0.0
			for child in node.get_children():
				var mesh: ArrayMesh = (child as MeshInstance3D).mesh
				tris += mesh.get_faces().size() / 3
				top = maxf(top, mesh.get_aabb().end.y)
			check(node.get_child_count() >= 1 and tris > 0, "árvore %d neve=%s: %d triângulos, topo %.1f m" % [variant, snowy, tris, top])
			if variant == 0 and not snowy:
				var bark: ArrayMesh = (node.get_child(0) as MeshInstance3D).mesh
				var ratio := outward_ratio(bark, func(v): return Vector3(0, v.y, 0), 1.0)
				check(ratio > 0.9, "casca: normais para fora (%.2f)" % ratio)
			node.free()
	print("RESULT failures=", failures)
	quit(1 if failures > 0 else 0)
