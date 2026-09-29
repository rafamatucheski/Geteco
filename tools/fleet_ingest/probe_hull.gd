extends SceneTree
## Diagnóstico de enrolamento (winding) do casco do Aurora: para cada triângulo, a normal
## geométrica (b-a)x(c-a) aponta para fora ou para dentro do carro? Godot só desenha a face
## cujo enrolamento é horário visto de fora, ou seja, (b-a)x(c-a) aponta PARA DENTRO.
func _initialize() -> void:
	var model: Node3D = preload("res://runtime/FleetCatalog.gd").create("aurora_executive")
	var best: MeshInstance3D = null
	var best_n := 0
	for node: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if node.mesh is ArrayMesh and node.mesh.get_surface_count() == 1 and not node.has_meta("wheel_center"):
			var n: int = node.mesh.surface_get_array_len(0)
			if n > best_n: best_n = n; best = node
	var a := best.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: Variant = a[Mesh.ARRAY_INDEX]
	var order := PackedInt32Array()
	if idx != null and (idx as PackedInt32Array).size() > 0: order = idx
	else:
		order.resize(v.size())
		for i in order.size(): order[i] = i
	var stats := {}
	for t in order.size() / 3:
		var p0 := v[order[t*3]]; var p1 := v[order[t*3+1]]; var p2 := v[order[t*3+2]]
		var c := (p0+p1+p2)/3.0
		var g := (p1-p0).cross(p2-p0)
		if g.length_squared() < 1e-10: continue
		g = g.normalized()
		# Região pela normal dominante; "para fora" = mesmo sentido do vetor do centro do casco ao centroide nessa direção.
		var region := ""
		var out := 0.0
		if absf(g.y) >= absf(g.x) and absf(g.y) >= absf(g.z): region = "topo/baixo"; out = g.y * (1.0 if c.y > 0.55 else -1.0)
		elif absf(g.x) >= absf(g.z): region = "flanco"; out = g.x * signf(c.x)
		else: region = "frente/trás"; out = g.z * signf(c.z)
		var key := region + (" GEOM-FORA(descartado)" if out > 0.3 else (" GEOM-DENTRO(desenhado)" if out < -0.3 else " oblíquo"))
		stats[key] = int(stats.get(key, 0)) + 1
	for k in stats: print("WIND ", k, " = ", stats[k])
	quit()
