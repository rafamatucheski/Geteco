extends SceneTree
## Monta a cena do carro do Meshy (`assets/fleet/meshy/citycar.scn`) a partir do GLB de malha única: gira o carro
## para a frente em -Z como a frota, escala, separa as quatro rodas da carroceria e as marca com `wheel_center`
## (convenção dos carros da frota: malha em coordenadas do veículo + posição do eixo na meta).
##
## O GLB do Meshy tem rodas coladas à carroceria (um só componente conexo), então a separação é geométrica: o
## triângulo vira roda se o centroide estiver dentro do cilindro do pneu (raio medido por ajuste de círculo nos
## vértices de borda) e na face externa (|z| > INNER_Z). O interior do pneu e o vão ficam na carroceria.
## Uso: "$GODOT" --path . --script res://tools/build_meshy_car.gd
const SOURCE := "res://assets/fleet/meshy/citycar.glb"
const TARGET := "res://assets/fleet/meshy/citycar.scn"
## Medidas do GLB cru (m do arquivo), ver docs/npc-meshy-carro-20261011.md.
const AXLE_X := 0.636
const WHEEL_RADIUS := 0.17
const GROUND_Y := -0.5044
const INNER_Z := 0.42
const SCALE := 1.6
const MARGIN := 0.012

func _initialize() -> void:
	var packed := load(SOURCE) as PackedScene
	var source := packed.instantiate() as Node3D
	var mesh_node := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var arrays := mesh_node.mesh.surface_get_arrays(0)
	var material := mesh_node.mesh.surface_get_material(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var center_y := GROUND_Y + WHEEL_RADIUS
	var groups := {"Body": [], "Wheel_FL": [], "Wheel_FR": [], "Wheel_RL": [], "Wheel_RR": []}
	for t in indices.size() / 3:
		var a := vertices[indices[t * 3]]
		var b := vertices[indices[t * 3 + 1]]
		var c := vertices[indices[t * 3 + 2]]
		var centroid := (a + b + c) / 3.0
		var group := "Body"
		if absf(centroid.z) > INNER_Z:
			var axle_x := AXLE_X if centroid.x > 0.0 else -AXLE_X
			if Vector2(centroid.x - axle_x, centroid.y - center_y).length() < WHEEL_RADIUS + MARGIN:
				group = "Wheel_%s%s" % ["F" if centroid.x > 0.0 else "R", "L" if centroid.z < 0.0 else "R"]
		groups[group].append(t)
	var root_node := Node3D.new()
	root_node.name = "Vehicle"
	# Gira +90° em Y (x cru, a frente, vai para -Z) e escala; o chão fica em y = 0.
	var bake := Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)) * Basis.from_scale(Vector3.ONE * SCALE), Vector3(0, -GROUND_Y * SCALE, 0))
	for group_name in groups:
		var tris: Array = groups[group_name]
		var out_vertices := PackedVector3Array()
		var out_normals := PackedVector3Array()
		var out_uvs := PackedVector2Array()
		var out_indices := PackedInt32Array()
		var remap := {}
		for t in tris:
			for k in 3:
				var old: int = indices[t * 3 + k]
				if not remap.has(old):
					remap[old] = out_vertices.size()
					out_vertices.append(bake * vertices[old])
					out_normals.append((bake.basis * normals[old]).normalized())
					out_uvs.append(uvs[old])
				out_indices.append(remap[old])
		if out_indices.is_empty(): continue
		var data := []
		data.resize(Mesh.ARRAY_MAX)
		data[Mesh.ARRAY_VERTEX] = out_vertices
		data[Mesh.ARRAY_NORMAL] = out_normals
		data[Mesh.ARRAY_TEX_UV] = out_uvs
		data[Mesh.ARRAY_INDEX] = out_indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
		mesh.surface_set_material(0, material)
		var part := MeshInstance3D.new()
		part.name = group_name
		part.mesh = mesh
		if group_name != "Body":
			var raw_center := Vector3(AXLE_X if group_name.contains("F") else -AXLE_X, center_y, -0.52 if group_name.ends_with("L") else 0.52)
			part.set_meta("wheel_center", bake * raw_center)
		root_node.add_child(part)
		part.owner = root_node
		print("%s: %d triângulos" % [group_name, tris.size()])
	var scene := PackedScene.new()
	scene.pack(root_node)
	print("salvo: ", ResourceSaver.save(scene, TARGET))
	quit()
