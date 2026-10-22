extends RefCounted
## Cópia na CPU das arrays de malha para quem monta lotes no streaming (fusão por célula, casca de sombra,
## acabamento do chão). `surface_get_arrays` não tem cópia na CPU: o RenderingDevice lê o buffer de volta da
## placa e espera a GPU terminar todos os quadros em voo. Medido em 16/10: ~0,4 ms por leitura com a cena
## parada e ~20 ms quando a GPU está ocupada (editor, ponte); no release a fatia de 176 ms de
## chunk.cell_merge na ponte caiu exatamente numa dessas esperas (o mesmo ponto teve 142 ms de render na outra
## rodada: a leitura só transformou em espera do thread principal o que a GPU já estava fazendo).
## Na travessia o streaming fazia ~4.600 leituras; 83% eram BoxMesh/CylinderMesh e 88% destas repetiam os
## mesmos parâmetros, e outras ~1.300 eram da mesma malha em outro trecho. Primitiva entra pela chave dos
## parâmetros (a geometria só depende deles) e ArrayMesh pela própria malha (referência fraca), entre trechos.
##
## As arrays devolvidas são compartilhadas: quem altera precisa duplicar.
const PRIMITIVE_CLASSES := ["BoxMesh", "CylinderMesh", "SphereMesh", "PlaneMesh", "QuadMesh", "PrismMesh", "TorusMesh", "CapsuleMesh"]
## Não mudam a geometria.
const PRIMITIVE_SKIP := ["material", "custom_aabb", "resource_name", "resource_path", "resource_local_to_scene", "resource_scene_unique_id", "script"]
const MAX_PRIMITIVES := 2048
## Malha própria do trecho guardada entre trechos: teto em vértices (~30 MB no pior formato), depois recomeça.
const MAX_MESH_VERTICES := 400000

static var _primitives := {}
static var _primitive_keys := {}
static var _meshes := {}
static var _mesh_vertices := 0
static var reads := 0
static var hits := 0
## Caixa e cilindro reto por escala (22/10): a geometria de um BoxMesh sem subdivisão é a da caixa
## unitária multiplicada pelo tamanho, e a de um CylinderMesh de raio igual em cima e embaixo é a do
## cilindro unitário (raio 1, altura 1) escalado em x/z pelo raio e em y pela altura; normais, UV,
## tangentes e índices não dependem do tamanho. Cada peça de G.box tem tamanho próprio, então a
## chave por parâmetros quase nunca acertava: o quadro da arrancada (~140 caixas) custava 49–54 ms
## e o pátio do Digo 64–70 ms num quadro só, uma leitura da GPU por caixa (estresse de 21–22/10).
## Agora só a forma unitária é lida, uma vez por tipo (prewarm_unit_shapes sob a cortina).
## GETECO_PRIMITIVE_CPU_ARRAYS=0 volta à leitura por parâmetros (A/B).
static var scaled_enabled := OS.get_environment("GETECO_PRIMITIVE_CPU_ARRAYS") != "0"
static var _units := {}
static var scaled := 0

static func arrays_of(mesh: Mesh, surface: int) -> Array:
	if scaled_enabled and surface == 0 and (mesh is BoxMesh or mesh is CylinderMesh):
		var from_unit := _scaled_arrays(mesh as PrimitiveMesh)
		if not from_unit.is_empty(): return from_unit
	return _cached_arrays(mesh, surface)

static func _cached_arrays(mesh: Mesh, surface: int) -> Array:
	if mesh is PrimitiveMesh and mesh.get_class() in PRIMITIVE_CLASSES:
		var key := _primitive_key(mesh as PrimitiveMesh)
		var cached: Variant = _primitives.get(key)
		if cached != null:
			hits += 1
			return cached
		if _primitives.size() >= MAX_PRIMITIVES: _primitives.clear()
		var arrays := mesh.surface_get_arrays(surface)
		reads += 1
		_primitives[key] = arrays
		return arrays
	var id_key := "%d:%d" % [mesh.get_instance_id(), surface]
	var entry: Variant = _meshes.get(id_key)
	# A contagem confere que a malha não ganhou/perdeu superfície ou vértices desde a leitura.
	var length: int = mesh.surface_get_array_len(surface) if mesh is ArrayMesh else -1
	var index_length: int = mesh.surface_get_array_index_len(surface) if mesh is ArrayMesh else -1
	if entry != null and entry.ref.get_ref() == mesh and int(entry.length) == length and int(entry.index_length) == index_length:
		hits += 1
		return entry.arrays
	var arrays := mesh.surface_get_arrays(surface)
	reads += 1
	var vertices: Variant = arrays[Mesh.ARRAY_VERTEX] if arrays.size() > Mesh.ARRAY_VERTEX else null
	var count: int = (vertices as PackedVector3Array).size() if vertices is PackedVector3Array else 0
	if _mesh_vertices + count > MAX_MESH_VERTICES:
		_meshes.clear()
		_mesh_vertices = 0
	_meshes[id_key] = {"ref": weakref(mesh), "arrays": arrays, "length": length, "index_length": index_length}
	_mesh_vertices += count
	return arrays

## Chave por parâmetros, guardada por malha (ler a lista de propriedades custa mais que olhar o dicionário).
static func _primitive_key(mesh: PrimitiveMesh) -> String:
	var id := mesh.get_instance_id()
	var known: Variant = _primitive_keys.get(id)
	# Primitiva mudada depois da leitura (tamanho novo) precisa de outra chave: o sinal changed da malha apaga a
	# chave guardada e a próxima leitura refaz pelos parâmetros novos.
	if known != null and known.ref.get_ref() == mesh: return known.key
	var parts := PackedStringArray([mesh.get_class()])
	for property in mesh.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE) or String(property.name) in PRIMITIVE_SKIP: continue
		parts.append("%s=%s" % [property.name, var_to_str(mesh.get(property.name))])
	var key := "|".join(parts)
	if _primitive_keys.size() >= MAX_PRIMITIVES * 4: _primitive_keys.clear()
	_primitive_keys[id] = {"ref": weakref(mesh), "key": key}
	var forget := Callable(_script(), "_forget_primitive").bind(id)
	if not mesh.changed.is_connected(forget): mesh.changed.connect(forget, CONNECT_ONE_SHOT)
	return key

## Arrays da forma unitária escaladas para esta malha; vazio quando a forma não é coberta (subdivisão,
## UV2, faces invertidas, cilindro cônico) e o chamador segue pelo caminho por parâmetros.
static func _scaled_arrays(mesh: PrimitiveMesh) -> Array:
	if mesh.flip_faces or mesh.add_uv2: return []
	var unit_key := ""
	var scale := Vector3.ONE
	if mesh is BoxMesh:
		var box := mesh as BoxMesh
		if box.subdivide_width != 0 or box.subdivide_height != 0 or box.subdivide_depth != 0: return []
		unit_key = "box"
		scale = box.size
	else:
		var cylinder := mesh as CylinderMesh
		if not is_equal_approx(cylinder.top_radius, cylinder.bottom_radius): return []
		unit_key = "cylinder|%d|%d|%s|%s" % [cylinder.radial_segments, cylinder.rings, cylinder.cap_top, cylinder.cap_bottom]
		scale = Vector3(cylinder.top_radius, cylinder.height, cylinder.top_radius)
	var unit: Array = _unit_arrays(unit_key, mesh)
	if unit.is_empty(): return []
	var source: PackedVector3Array = unit[Mesh.ARRAY_VERTEX]
	var vertices := PackedVector3Array()
	vertices.resize(source.size())
	for index in source.size(): vertices[index] = source[index] * scale
	# Cópia rasa: só a posição é nova; normais, UV, tangentes e índices são os da forma unitária.
	var arrays := unit.duplicate()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	scaled += 1
	hits += 1
	return arrays

static func _unit_arrays(unit_key: String, like: PrimitiveMesh) -> Array:
	var cached: Variant = _units.get(unit_key)
	if cached != null: return cached
	var unit: PrimitiveMesh
	if like is BoxMesh:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		unit = box
	else:
		var source := like as CylinderMesh
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.0
		cylinder.bottom_radius = 1.0
		cylinder.height = 1.0
		cylinder.radial_segments = source.radial_segments
		cylinder.rings = source.rings
		cylinder.cap_top = source.cap_top
		cylinder.cap_bottom = source.cap_bottom
		unit = cylinder
	var arrays := _cached_arrays(unit, 0)
	# Renderizador sem malha (headless antigo) devolve vazio: não guarda, cai no caminho por parâmetros.
	if arrays.size() <= Mesh.ARRAY_VERTEX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty(): return []
	_units[unit_key] = arrays
	return arrays

## Formas unitárias mais usadas (G.box, G.cylinder de 10 lados, cilindro padrão) lidas sob a cortina.
static func prewarm_unit_shapes() -> void:
	if not scaled_enabled: return
	_unit_arrays("box", BoxMesh.new())
	for segments in [10, 64]:
		var cylinder := CylinderMesh.new()
		cylinder.radial_segments = segments
		_unit_arrays("cylinder|%d|%d|%s|%s" % [cylinder.radial_segments, cylinder.rings, cylinder.cap_top, cylinder.cap_bottom], cylinder)

static var _self_script: Script
static func _script() -> Script:
	if _self_script == null: _self_script = load("res://world/chunk_bake/MeshArrayCache.gd")
	return _self_script

static func _forget_primitive(id: int) -> void:
	_primitive_keys.erase(id)
