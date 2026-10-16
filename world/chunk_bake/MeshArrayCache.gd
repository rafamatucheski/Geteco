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

static func arrays_of(mesh: Mesh, surface: int) -> Array:
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

static var _self_script: Script
static func _script() -> Script:
	if _self_script == null: _self_script = load("res://world/chunk_bake/MeshArrayCache.gd")
	return _self_script

static func _forget_primitive(id: int) -> void:
	_primitive_keys.erase(id)
