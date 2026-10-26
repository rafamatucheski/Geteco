extends "res://tests/test_vehicle_glass_damage.gd"
const REMNANTS := preload("res://gameplay/vehicle_effects/VehicleGlassRemnants.gd")
const RAIN := preload("res://gameplay/vehicle_effects/VehicleWindshieldRain.gd")

class FixtureCar extends Node3D:
	var visual: Node3D
	var effects: Node

func run() -> void:
	for id in ["union_sedan", "monaliza", "courier_van"]: _vehicle_cycle(id)
	_tangents()
	_unsupported_surface()
	_layer_boundary()
	print("VEHICLE_GLASS_REMNANTS checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _vehicle_cycle(id: String) -> void:
	var car := car_at(id, Vector3.ZERO)
	car.finish_doors()
	var owner := GLASS.owner_for(car, true)
	var ray := ray_for(car, 0)
	check(not ray.is_empty(), id + " vidro alcançável depois do preparo das portas")
	if ray.is_empty(): car.free(); return
	var hit: Dictionary = owner.contact(ray[0], ray[1])
	var part: MeshInstance3D = hit.part
	var surface: int = hit.surface
	var before: Array = INTERIOR.contact_arrays(part.mesh, surface).duplicate(true)
	var indices := GLASS._indices(before)
	var vertices: PackedVector3Array = before[Mesh.ARRAY_VERTEX]
	var removed: Dictionary = {}
	GLASS._flood(hit.triangle, vertices, indices, GLASS._welded(vertices, indices), removed)
	var expected_kept := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		if not removed.has(i): expected_kept.append_array(indices.slice(i, i + 3))
	var other_surfaces: Array = []
	for node: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null: continue
		for index in node.mesh.get_surface_count():
			if node != part or index != surface: other_surfaces.append([node, index, INTERIOR.contact_arrays(node.mesh, index).duplicate(true), node.get_active_material(index)])
	for count in GLASS.BREAK_HITS: owner.shoot(ray[0], ray[1])
	var after: Array = INTERIOR.contact_arrays(part.mesh, surface)
	var final_indices := GLASS._indices(after)
	var start: int = part.mesh.get_meta("glass_remnant_starts", {}).get(surface, -1)
	check(start == expected_kept.size() and final_indices.size() > start, id + " fragmentos existem somente depois dos triângulos preservados")
	check(final_indices.slice(0, expected_kept.size()) == expected_kept and (after[Mesh.ARRAY_VERTEX] as PackedVector3Array).slice(0, vertices.size()) == vertices,
		id + " outras janelas da mesma superfície preservam todos os vértices e triângulos")
	var untouched := true
	for row in other_surfaces:
		if INTERIOR.contact_arrays(row[0].mesh, row[1]) != row[2] or row[0].get_active_material(row[1]) != row[3]: untouched = false
	check(untouched, id + " superfícies de pintura e demais peças não são alteradas")
	var geometry: Dictionary = RAIN.geometry_for(car)
	var rain_vertices: PackedVector3Array = geometry.glass.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var saved: Array = JSON.parse_string(JSON.stringify(car.snapshot_glass()))
	car.restore_glass(saved)
	var restored: Array = INTERIOR.contact_arrays(part.mesh, surface)
	check(restored == after, id + " JSON/save restaura exatamente os mesmos atributos dos fragmentos")
	check(RAIN.geometry_for(car).glass.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == rain_vertices, id + " água permanece exatamente sobre o mesmo vidro após restore")
	car.restore_glass([])
	check(INTERIOR.contact_arrays(part.mesh, surface) == before, id + " reparo recupera a superfície original inteira")
	car.restore_glass(saved)
	check(INTERIOR.contact_arrays(part.mesh, surface) == after, id + " reparar e reaplicar save produz os mesmos fragmentos")
	var fresh := car_at(id, Vector3(24, 0, 0))
	fresh.finish_doors()
	fresh.restore_glass(saved)
	var fresh_rain: PackedVector3Array = RAIN.geometry_for(fresh).glass.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var max_error := 0.0
	if fresh_rain.size() == rain_vertices.size():
		for i in fresh_rain.size(): max_error = maxf(max_error, fresh_rain[i].distance_to(rain_vertices[i]))
	else: max_error = INF
	var fresh_part: MeshInstance3D = fresh.visual.get_node_or_null(car.visual.get_path_to(part))
	check(fresh_part != null and INTERIOR.contact_arrays(fresh_part.mesh, surface) == after, id + " veículo novo restaura atributos locais exatamente idênticos")
	# O overlay converte global→carro: deslocar 24 m arredonda floats em até 0,8 µm
	# neste fixture. O teste do fragmento acima exige igualdade exata nos dados locais.
	check(max_error < .00001, id + " água acompanha o novo veículo com erro inferior a 10 µm (%.9f m)" % max_error)
	car.free()
	fresh.free()

func _layer_boundary() -> void:
	var car := FixtureCar.new()
	car.visual = Node3D.new()
	car.add_child(car.visual)
	root.add_child(car)
	var source := _quad()
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	for depth in [.02, .04]:
		var layer := _quad(Vector3(0,0,depth))
		var offset := vertices.size()
		vertices.append_array(layer[Mesh.ARRAY_VERTEX])
		normals.append_array(PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD]))
		for index in layer[Mesh.ARRAY_INDEX]: indices.append(index + offset)
	source[Mesh.ARRAY_VERTEX] = vertices
	source[Mesh.ARRAY_NORMAL] = normals
	source[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source)
	mesh.surface_set_material(0, StandardMaterial3D.new())
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.set_meta("fixture_surface_material_keys", ["glass"])
	car.visual.add_child(part)
	var owner := GLASS.owner_for(car, true)
	owner.records.append({"point": [.5,.5,0], "direction": [0,0,-1]})
	owner._reapply_part(part)
	check(owner._cracks.get(part, []).size() == 1, "faces próximas da mesma janela recebem uma marca por tiro")
	for hit in GLASS.BREAK_HITS - 1: owner.records.append(owner.records[0].duplicate(true))
	owner._reapply_part(part)
	var result := GLASS._indices(INTERIOR.contact_arrays(part.mesh, 0))
	var start: int = part.mesh.get_meta("glass_remnant_starts", {}).get(0, -1)
	check(start == 6 and result.slice(0, 6) == PackedInt32Array([8,9,10,8,10,11]), "face interna a 2 cm quebra junto; painel separado a 4 cm permanece intacto")
	car.free()

func _quad(offset := Vector3.ZERO) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([offset, offset + Vector3.RIGHT, offset + Vector3(1,1,0), offset + Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	return arrays

func _tangents() -> void:
	var source := _quad()
	source[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1,0,0,1, .8,.6,0,-1, 1,0,0,1, .8,.6,0,-1])
	var result := REMNANTS.build(source, PackedInt32Array(), {0: true, 3: true}, Basis.IDENTITY, [])
	var normals: PackedVector3Array = result[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = result[Mesh.ARRAY_TANGENT]
	var valid := true
	for i in range(4, normals.size()):
		var tangent := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
		if absf(tangent.length() - 1.0) > .00001 or absf(tangent.dot(normals[i])) > .00001 or absf(tangents[i * 4 + 3]) != 1.0: valid = false
	check(valid and normals.size() > 4, "tangentes dos fragmentos mantêm direção unitária, ortogonal e orientação ±1")
	check(source == _with_tangents(), "helper não altera arrays originais compartilhadas")

func _with_tangents() -> Array:
	var source := _quad()
	source[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1,0,0,1, .8,.6,0,-1, 1,0,0,1, .8,.6,0,-1])
	return source

func _unsupported_surface() -> void:
	var car := FixtureCar.new()
	car.visual = Node3D.new()
	car.add_child(car.visual)
	root.add_child(car)
	var source := _quad()
	source[Mesh.ARRAY_BONES] = PackedInt32Array([0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0])
	source[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad(Vector3(3,0,0)))
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.set_meta("fixture_surface_material_keys", ["glass", "glass"])
	for i in 2: mesh.surface_set_material(i, StandardMaterial3D.new())
	car.visual.add_child(part)
	var original := INTERIOR.contact_arrays(mesh, 0).duplicate(true)
	var owner := GLASS.owner_for(car, true)
	for x in [.5, 3.5]:
		for hit in GLASS.BREAK_HITS: owner.records.append({"point": [x,.5,0], "direction": [0,0,-1]})
	owner._reapply_part(part)
	check(part.mesh != mesh and GLASS._hidden(part, 0) and not GLASS._hidden(part, 1), "superfície incompatível fica oculta enquanto outro painel conserva fragmentos")
	check(INTERIOR.contact_arrays(part.mesh, 0) == original, "fallback conserva buffers válidos da superfície oculta ao reconstruir outra")
	car.free()
