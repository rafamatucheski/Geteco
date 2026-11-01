extends RefCounted
## Teto translúcido do veículo conduzido (`roof_paint` no lugar, placa `slab` e teto `cut` recortado da
## lataria) e a textura constante do alfa, separados do VehicleInterior em 01/11 (Onda 2 do plano
## de divisão). Tudo estático, como o dono. `g` é o script do VehicleInterior (preload cíclico, como
## CityNightLamps faz com CityChunkDressing): só ROOF_ALPHA continua lá. O dono mantém
## `_roof_alpha_texture` e `_open_roof` como delegações de uma linha com a mesma assinatura.

const g := preload("res://gameplay/VehicleInterior.gd")
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")

static var _roof_texture: ImageTexture
static var _roof_cuts: Dictionary = {}
## Textura constante com o alfa do teto. O alfa vem daqui, e não de `albedo_color.a`, porque
## a repintura do veículo (VehiclePaint.apply) reescreve o albedo com alfa 1.
static func _roof_alpha_texture() -> ImageTexture:
	if _roof_texture == null:
		var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color(1, 1, 1, g.ROOF_ALPHA))
		_roof_texture = ImageTexture.create_from_image(image)
	return _roof_texture

## Variante translúcida do teto de um material (em cache no veículo, pelo material de origem, que é
## da tinta dele): a mesma instância serve ao prewarm e à abertura, então o custo de montar o
## sombreador cai no prewarm. Morre junto com o veículo.
static func _roof_variant(vehicle: Node3D, material: StandardMaterial3D) -> StandardMaterial3D:
	var cache: Dictionary = vehicle.get_meta("interior_variants", {})
	if cache.has(material): return cache[material]
	var variant := material.duplicate() as StandardMaterial3D
	variant.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	variant.albedo_texture = _roof_alpha_texture()
	cache[material] = variant
	vehicle.set_meta("interior_variants", cache)
	return variant

static func _cut_key(part: MeshInstance3D, surface: int, id: String) -> String:
	return "%d:%d:%s" % [part.mesh.get_instance_id(), surface, id]

## Peças do veículo que viram teto translúcido: `roof_paint` (peça de teto própria, muda no
## lugar), `slab` (placa larga de teto com material próprio: ônibus, jipe) e `cut` (o teto é
## parte da lataria: os triângulos de teto saem para uma peça à parte).
static func _roof_candidates(vehicle: Node3D, s: Dictionary) -> Array:
	var found: Array = []
	var to_car := vehicle.global_transform.affine_inverse()
	for part in vehicle.visual.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = part.mesh
		if mesh == null or part.has_meta("wheel_center") or part.name == "Interior" or part.name == "RoofCut" or part.name == "WarmUp": continue
		for surface in mesh.get_surface_count():
			var material: Material = part.material_override if part.material_override != null else part.get_active_material(surface)
			if not material is StandardMaterial3D or material.albedo_texture != null: continue
			var key := ROLES.key(part, surface)
			var box: AABB = (to_car * part.global_transform) * mesh.get_aabb()
			if key == "roof_paint":
				found.append({"part": part, "surface": surface, "material": material, "kind": "roof_paint"})
			elif part.material_override != null and not (material as StandardMaterial3D).emission_enabled \
					and box.position.y >= float(s.roof) - .06 and box.position.y <= float(s.roof) + .12 and box.size.y < .35 and box.size.x >= float(s.hw) * 1.2 and box.size.z >= .7 and box.size.x * box.size.z >= .9 and box.get_center().z < float(s.rear_top) + .3:
				found.append({"part": part, "surface": surface, "material": material, "kind": "slab"})
			elif key in ["paint", "canvas"] and (part.material_override == null or surface == 0):
				found.append({"part": part, "surface": surface, "material": material, "kind": "cut"})
				break
	return found

## Teto translúcido no veículo conduzido: da câmera a 45° o teto opaco escondia o motorista e
## o interior inteiro. Peças de teto próprias (`roof_paint`) ficam translúcidas no lugar; nos
## cascos em que o teto é parte da lataria, os triângulos de teto viram uma peça à parte
## (malha em cache por arquétipo) com a mesma tinta.
static func _open_roof(vehicle: Node3D, s: Dictionary) -> void:
	var view: Dictionary = vehicle.get_meta("interior_view")
	var id := str(vehicle.get("archetype"))
	var to_car := vehicle.global_transform.affine_inverse()
	view["added_paint"] = []
	var paint = vehicle.get("_paint")
	for candidate in _roof_candidates(vehicle, s):
		var part: MeshInstance3D = candidate.part
		var surface: int = candidate.surface
		var material: StandardMaterial3D = candidate.material
		match str(candidate.kind):
			"roof_paint":
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_texture = _roof_alpha_texture()
				view.alpha_materials.append(material)
			"slab":
				var slab := _roof_variant(vehicle, material)
				view.slabs.append([part, part.material_override])
				part.material_override = slab
				view.alpha_materials.append(slab)
				if paint != null and material in paint.materials:
					paint.materials.append(slab)
					view.added_paint.append(slab)
					if material in paint.roof_materials: paint.roof_materials.append(slab)
			"cut":
				var mesh: Mesh = part.mesh
				var cut := _cut_roof(part, surface, to_car * part.global_transform, s, _cut_key(part, surface, id))
				if cut.is_empty(): continue
				var roof := MeshInstance3D.new()
				roof.name = "RoofCut"
				roof.mesh = cut.roof
				roof.transform = part.transform
				var tinted := _roof_variant(vehicle, material)
				roof.material_override = tinted
				roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				part.get_parent().add_child(roof, true)
				view.parts.append([part, mesh])
				view.roofs.append(roof)
				part.mesh = cut.body
				# A repintura passa a valer também para o teto recortado.
				if paint != null:
					paint.materials.append(tinted)
					view.added_paint.append(tinted)

## Separa os triângulos de teto (voltados para cima, na altura do teto, sobre a cabine) da
## superfície de pintura. Devolve {body, roof} ou {} se não houver teto ali.
static func _cut_roof(part: MeshInstance3D, surface: int, xf: Transform3D, s: Dictionary, key: String) -> Dictionary:
	if _roof_cuts.has(key): return _roof_cuts[key]
	var mesh: Mesh = part.mesh
	# Só malhas de importação: as primitivas (caixa, cilindro) não têm superfícies editáveis.
	if not mesh is ArrayMesh:
		_roof_cuts[key] = {}
		return {}
	var arrays := MESH_ARRAYS.arrays_of(mesh, surface).duplicate()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null: normals = arrays[Mesh.ARRAY_NORMAL]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
	else:
		indices.resize(vertices.size())
		for i in indices.size(): indices[i] = i
	var y_min := float(s.roof) - .12
	var z0 := float(s.wz1) - .25
	var z1 := float(s.rear_top) + .25
	var half := float(s.hw) + .06
	var roof_indices := PackedInt32Array()
	var body_indices := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		var a: Vector3 = xf * vertices[indices[i]]
		var b: Vector3 = xf * vertices[indices[i + 1]]
		var c: Vector3 = xf * vertices[indices[i + 2]]
		var center := (a + b + c) / 3.0
		var up := 0.0
		if normals.size() == vertices.size():
			up = (xf.basis * (normals[indices[i]] + normals[indices[i + 1]] + normals[indices[i + 2]])).normalized().y
		else:
			up = absf((b - a).cross(c - a).normalized().y)
		var triangle := PackedInt32Array([indices[i], indices[i + 1], indices[i + 2]])
		if center.y >= y_min and up > .55 and center.z >= z0 and center.z <= z1 and absf(center.x) <= half:
			roof_indices.append_array(triangle)
		else:
			body_indices.append_array(triangle)
	if roof_indices.size() < 6 or body_indices.size() < 6:
		_roof_cuts[key] = {}
		return {}
	var body := ArrayMesh.new()
	for j in mesh.get_surface_count():
		# A superfície cortada já foi lida acima: cada leitura de malha volta da GPU e trava o quadro.
		var other: Array = arrays.duplicate() if j == surface else MESH_ARRAYS.arrays_of(mesh, j)
		if j == surface: other[Mesh.ARRAY_INDEX] = body_indices
		body.add_surface_from_arrays(mesh.surface_get_primitive_type(j), other)
		body.surface_set_material(j, mesh.surface_get_material(j))
	var roof := ArrayMesh.new()
	arrays[Mesh.ARRAY_INDEX] = roof_indices
	roof.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var result := {"body": body, "roof": roof}
	_roof_cuts[key] = result
	return result
