extends RefCounted
## Passo 5 (piso das quadras virado para cima) separado do CityChunkDressing em 01/11 (Onda 1).
## Lê malha só por MeshArrayCache, como antes.
## Tudo estático, como o dono, que mantém _face_ground_up e _face_ground_up_step como delegação
## de uma linha. Não lê nada do dono (sem preload de volta).

const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")

## O piso das quadras é gerado com triângulos em sentido anti-horário vistos
## de cima: a câmera vê o VERSO, e o Godot inverte a normal do verso. O chão
## das quadras apontava para baixo — zero de sol, zero de sombra (medido: a
## máscara de contribuição do sol era preta em todo o piso de lajota/grama), e
## os prédios pareciam colados. Refaz a malha com a ordem dos triângulos
## invertida (a face da frente passa a olhar para cima); a malha corrigida é
## compartilhada por instância de malha original.
static var _ground_meshes := {}
static func _face_ground_up(chunk: Node3D) -> void:
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		_face_ground_mesh(node as MeshInstance3D)


## Passo 5 fatiado. Cada piso candidato pede surface_get_arrays, que espera a GPU
## terminar os quadros em voo (MeshArrayCache): no release de 16/10 o passo
## inteiro num quadro deu 185 ms logo depois do jogo ficar jogável (travessia_1,
## no desembarque). No editor, a travessia leu 602 pisos em 99 trechos (~6 por
## trecho) e nenhum estava virado para baixo: o passo vale como garantia, mas não
## pode concentrar as leituras num quadro.
const FACE_GROUND_BUDGET_USEC := 2000

static func _face_ground_up_step(state: Dictionary) -> bool:
	var chunk: Node3D = state.chunk
	if not state.has("ground_nodes"):
		state.ground_nodes = chunk.find_children("*", "MeshInstance3D", true, false)
		state.ground_index = 0
	var nodes: Array = state.ground_nodes
	var began := Time.get_ticks_usec()
	while int(state.ground_index) < nodes.size():
		var node: Variant = nodes[int(state.ground_index)]
		state.ground_index = int(state.ground_index) + 1
		# Entre um quadro e outro um registro pode ter saído do trecho (volta ao cache de registros).
		if is_instance_valid(node) and chunk.is_ancestor_of(node): _face_ground_mesh(node as MeshInstance3D)
		if Time.get_ticks_usec() - began >= FACE_GROUND_BUDGET_USEC: return false
	state.erase("ground_nodes")
	state.erase("ground_index")
	return true


static func _face_ground_mesh(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null or not mesh.mesh is ArrayMesh: return
	var box := mesh.global_transform * mesh.get_aabb()
	if box.size.y > 0.4 or box.end.y > 0.3 or maxf(box.size.x, box.size.z) < 3.0: return
	if not _faces_down(mesh.mesh): return
	var key := mesh.mesh.get_instance_id()
	if not _ground_meshes.has(key): _ground_meshes[key] = _flipped(mesh.mesh)
	# A malha original fica (escondida): a colisão do piso é gerada dela
	# depois deste passo e precisa continuar igual à que os testes de via
	# conferem. Só o desenho usa a cópia invertida.
	var visual := MeshInstance3D.new()
	visual.name = String(mesh.name) + "_Lit"
	visual.mesh = _ground_meshes[key]
	visual.material_override = mesh.material_override
	visual.cast_shadow = mesh.cast_shadow
	visual.layers = mesh.layers
	mesh.add_sibling(visual)
	visual.transform = mesh.transform
	mesh.visible = false


static func _flipped(source: ArrayMesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := MESH_ARRAYS.arrays_of(source, surface).duplicate()
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices != null and indices.size() > 0:
			var flipped := PackedInt32Array(indices)
			for i in range(0, flipped.size() - 2, 3):
				var t := flipped[i + 1]
				flipped[i + 1] = flipped[i + 2]
				flipped[i + 2] = t
			arrays[Mesh.ARRAY_INDEX] = flipped
		else:
			for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
				var data = arrays[channel]
				if data == null or data.size() == 0: continue
				var stride: int = data.size() / (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var copy = data.duplicate()
				for tri in range(0, (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() - 2, 3):
					for k in stride:
						copy[(tri + 1) * stride + k] = data[(tri + 2) * stride + k]
						copy[(tri + 2) * stride + k] = data[(tri + 1) * stride + k]
				arrays[channel] = copy
		var normals = arrays[Mesh.ARRAY_NORMAL]
		if normals != null and normals.size() > 0:
			var up := PackedVector3Array()
			up.resize(normals.size())
			up.fill(Vector3.UP)
			arrays[Mesh.ARRAY_NORMAL] = up
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, source.surface_get_material(surface))
	return result


## Resposta por malha: piso compartilhado entre trechos (registro em cache) não lê de novo da GPU.
static var _faces_down_by_mesh := {}

static func _faces_down(array_mesh: ArrayMesh) -> bool:
	var id := array_mesh.get_instance_id()
	var known: Variant = _faces_down_by_mesh.get(id)
	if known != null and known.ref.get_ref() == array_mesh: return known.down
	if _faces_down_by_mesh.size() > 4096: _faces_down_by_mesh.clear()
	var down := _faces_down_read(array_mesh)
	_faces_down_by_mesh[id] = {"ref": weakref(array_mesh), "down": down}
	return down

static func _faces_down_read(array_mesh: ArrayMesh) -> bool:
	var arrays := MESH_ARRAYS.arrays_of(array_mesh, 0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var up := 0.0
	var count := 0
	var step := 3
	var total: int = indices.size() if indices != null and indices.size() > 0 else vertices.size()
	for i in range(0, mini(total, 90), step):
		var a: Vector3; var b: Vector3; var c: Vector3
		if indices != null and indices.size() > 0:
			a = vertices[indices[i]]; b = vertices[indices[i + 1]]; c = vertices[indices[i + 2]]
		else:
			a = vertices[i]; b = vertices[i + 1]; c = vertices[i + 2]
		# Frente no Godot = horário visto de fora: normal geométrica (b-a)x(c-a)
		# aponta para TRÁS da face da frente.
		up += (b - a).cross(c - a).y
		count += 1
	return count > 0 and up > 0.0
