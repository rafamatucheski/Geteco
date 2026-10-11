extends SceneTree
## Separa um GLB de carro (malha única do Meshy) em componentes conectados e imprime a caixa de cada um, para saber se as
## rodas vêm soltas da carroceria. Uso: "$GODOT" --path . --script res://tests/diagnostics/car_components.gd -- --glb=res://...
func _initialize() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--glb="): path = arg.substr(6)
	var root_node := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(root_node)
	for node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var transform := mesh_node.global_transform
		for s in mesh_node.mesh.get_surface_count():
			var arrays := mesh_node.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			print("malha %s superfície %d: %d vértices, %d triângulos" % [mesh_node.name, s, vertices.size(), indices.size() / 3])
			var parent := PackedInt32Array()
			parent.resize(vertices.size())
			for i in vertices.size(): parent[i] = i
			var find := func(x: int) -> int:
				while parent[x] != x:
					parent[x] = parent[parent[x]]
					x = parent[x]
				return x
			# Vértices na mesma posição (costuras de UV) contam como o mesmo ponto.
			var welded := {}
			for i in vertices.size():
				var key := Vector3i((vertices[i] * 2000.0).round())
				if welded.has(key): parent[find.call(i)] = find.call(welded[key])
				else: welded[key] = i
			for t in indices.size() / 3:
				var a: int = find.call(indices[t * 3])
				for k in 2:
					var b: int = find.call(indices[t * 3 + 1 + k])
					if a != b: parent[b] = a
			var groups := {}
			for t in indices.size() / 3:
				var r: int = find.call(indices[t * 3])
				if not groups.has(r): groups[r] = {"tris": 0, "box": AABB(transform * vertices[indices[t * 3]], Vector3.ZERO)}
				groups[r].tris += 1
				for k in 3: groups[r].box = groups[r].box.expand(transform * vertices[indices[t * 3 + k]])
			var list := groups.values()
			list.sort_custom(func(x, y): return x.tris > y.tris)
			print("componentes: %d" % list.size())
			for g in list.slice(0, 12): print("  %6d tri  centro %s  tamanho %s" % [g.tris, str(g.box.get_center().snapped(Vector3(.01, .01, .01))), str(g.box.size.snapped(Vector3(.01, .01, .01)))])
	quit()
