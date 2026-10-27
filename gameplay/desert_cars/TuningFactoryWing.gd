extends RefCounted
## Tira a asa de fábrica quando o carro recebe um aerofólio de oficina. A asa vem fundida
## na malha assada da carroceria, mas como peças soltas (sem vértice em comum com a lata):
## some só o componente conexo que cabe inteiro na caixa do carro e sobe acima da tampa.
## A malha recortada é por instância; a frota compartilhada nunca muda.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const ROOF := preload("res://gameplay/desert_cars/TuningSunroof.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const REST_MESH_META := "body_dents_rest_mesh"
var model: Node3D
var box := AABB()
var reach := 0.0
var hidden := false
## Malha original → recortada (null quando não havia asa nela) e o caminho de volta.
var _stripped := {}
var _sources := {}
var removed_triangles := 0

func bind(source: Node3D, car_id: String) -> void:
	model = source
	var row: Array = TUNING.FACTORY_WING_BOX.get(car_id,[])
	if row.is_empty(): return
	box = AABB(row[0],row[1]-row[0]).grow(.005)
	reach = float(row[2])

func has_wing() -> bool:
	return box.size != Vector3.ZERO

## Idempotente: só troca a malha da peça quando o estado pedido muda.
func set_hidden(value: bool) -> void:
	if not has_wing(): return
	var changed := false
	var vehicle: Node = model.get_parent()
	if value and vehicle is CharacterBody3D and vehicle.has_method("finish_doors"): vehicle.finish_doors()
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.has_meta("wheel_center") or in_kit(part,model): continue
		# Com amassado, a peça mostra a malha deformada; o estado está na malha em repouso.
		var base: Mesh = part.get_meta(REST_MESH_META,part.mesh)
		if value and not _sources.has(base):
			# Só malha assada que encosta na caixa; luzes e primitivas do equipamento ficam.
			if not base is ArrayMesh or not (ROOF.relative_transform(part,model)*base.get_aabb()).intersects(box): continue
			var stripped: Mesh = _strip(part,base)
			if stripped == null: continue
			part.mesh = stripped
			changed = true
		elif not value and _sources.has(base):
			part.mesh = _sources[base]
			changed = true
	hidden = value
	# Igual ao teto solar: o amassado adota a nova malha em repouso e reaplica os registros.
	if changed and vehicle is CharacterBody3D and is_instance_valid(vehicle.get("body_dents")):
		vehicle.body_dents.geometry_changed()

func _strip(part: MeshInstance3D, source: Mesh) -> Mesh:
	if _stripped.has(source): return _stripped[source]
	var began := STALL_WORK.begin()
	var xf := ROOF.relative_transform(part,model)
	var result := ArrayMesh.new()
	var any := false
	for surface in source.get_surface_count():
		var arrays := MESH_ARRAYS.arrays_of(source,surface)
		if arrays.is_empty() or source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			_stripped[source] = null
			return null
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size(): indices.append(i)
		var drop := _wing_triangles(vertices,indices,xf)
		var copy: Array = arrays.duplicate()
		if not drop.is_empty():
			any = true
			var kept := PackedInt32Array()
			for t in indices.size()/3:
				if drop.has(t): continue
				kept.append(indices[t*3]); kept.append(indices[t*3+1]); kept.append(indices[t*3+2])
			# A pintura e o dano trocam material por índice de superfície: a contagem fica.
			if kept.is_empty(): kept = PackedInt32Array([0,0,0])
			copy[Mesh.ARRAY_INDEX] = kept
			removed_triangles += drop.size()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,copy)
		result.surface_set_material(result.get_surface_count()-1,source.surface_get_material(surface))
	var stripped: Mesh = result if any else null
	_stripped[source] = stripped
	if stripped != null: _sources[stripped] = source
	STALL_WORK.finish_slow("tuning_factory_wing",began,4000)
	return stripped

## Componentes conexos por posição soldada (1 mm); devolve os triângulos da asa.
func _wing_triangles(vertices: PackedVector3Array, indices: PackedInt32Array, xf: Transform3D) -> Dictionary:
	var parent := {}
	var keys: Array[Vector3i] = []
	keys.resize(vertices.size())
	var world: Array[Vector3] = []
	world.resize(vertices.size())
	var any_inside := false
	for i in vertices.size():
		var p: Vector3 = xf*vertices[i]
		world[i] = p
		keys[i] = Vector3i(roundi(p.x*1000.0),roundi(p.y*1000.0),roundi(p.z*1000.0))
		if box.has_point(p): any_inside = true
	if not any_inside: return {}
	for i in range(0,indices.size(),3):
		var a := _root(parent,keys[indices[i]])
		for j in [1,2]:
			var b := _root(parent,keys[indices[i+j]])
			if a != b: parent[b] = a
	var groups := {}
	for i in range(0,indices.size(),3):
		# Triângulo degenerado (o que segura uma superfície esvaziada) não é peça.
		if indices[i] == indices[i+1] and indices[i] == indices[i+2]: continue
		var r := _root(parent,keys[indices[i]])
		if not groups.has(r): groups[r] = {"inside":true,"top":-INF,"tris":[]}
		var g: Dictionary = groups[r]
		g.tris.append(i/3)
		for j in 3:
			var p: Vector3 = world[indices[i+j]]
			if not box.has_point(p): g.inside = false
			g.top = maxf(g.top,p.y)
	var drop := {}
	for g in groups.values():
		# Fica: o que sai da caixa (lata, tampa) e o que não sobe acima dela (frisos da tampa).
		if not g.inside or g.top < reach: continue
		for t in g.tris: drop[t] = true
	return drop

## Peça montada pelo próprio tuning (aerofólio, saias...): os filhos têm nome automático,
## então vale o nome do nó do kit acima deles.
static func in_kit(node: Node, ancestor: Node) -> bool:
	while node != null and node != ancestor:
		if str(node.name).begins_with("Tuning"): return true
		node = node.get_parent()
	return false

static func _root(parent: Dictionary, key: Vector3i) -> Vector3i:
	var r := key
	while parent.has(r) and parent[r] != r: r = parent[r]
	# Encurta o caminho para as próximas buscas.
	var cursor := key
	while parent.has(cursor) and parent[cursor] != r:
		var next: Vector3i = parent[cursor]
		parent[cursor] = r
		cursor = next
	return r
