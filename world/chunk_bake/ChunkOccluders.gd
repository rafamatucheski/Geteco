extends RefCounted
## Oclusão por trecho (auditoria Godot 4.7, §4): um OccluderInstance3D com ArrayOccluder3D montado das caixas
## opacas que o ChunkShadowShell já aceita (BoxMesh de gerador estático conhecido, fora do corredor do túnel,
## sem reveal, sem fachada de entrar, sem nada que se mexe). Só caixas grandes entram, maiores primeiro.
##
## Desligado por padrão até o A/B: GETECO_OCCLUSION=1 liga. Com ele ligado, a primeira inserção liga também
## `use_occlusion_culling` no viewport raiz (aqui, e não em ProductionWorld, para que o interruptor desligue
## tudo de uma vez e nenhum outro arquivo precise saber dele).
##
## Por que só caixas: a caixa é sólida no volume inteiro, então o oclusor não tapa o que a malha real deixaria
## ver. Mesmo assim cada caixa encolhe SHRINK por face (a doc pede oclusor um pouco menor que a malha: evita
## sumir objeto rente à parede por imprecisão do buffer de oclusão, que tem resolução baixa).
##
## Cuidado: o jogador e o carro atrás de prédio continuam desenhados pela silhueta (CityLook,
## occluded_silhouette.gdshader). Com a oclusão ligada eles seriam cortados inteiros atrás do oclusor, e a
## silhueta some junto. As GeometryInstance3D da silhueta precisam de `ignore_occlusion_culling = true`
## antes de medir com este interruptor ligado em jogo de verdade.
static var enabled := OS.get_environment("GETECO_OCCLUSION") == "1"
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
const NODE_NAME := "ChunkOccluders"
## Lado maior e lado do meio mínimos (m): parede de 3 × 2 m já tapa uma rua atrás; caixa menor custa raster
## no buffer de oclusão e quase nunca esconde um objeto inteiro.
const MIN_SPAN := 3.0
const MIN_SECOND := 2.0
## Topo abaixo disto é chão (calçada, laje de praça): só tapa o que está embaixo dele, que não é desenhado.
const MIN_TOP := 0.5
## Teto por trecho: a BVH do oclusor é reconstruída a cada inserção, e o custo de raster cresce com os
## triângulos. 12 triângulos por caixa; 192 caixas = 2.304 triângulos.
const MAX_BOXES := 192
const SHRINK := 0.1

## Anota uma caixa candidata (chamado pela casca para cada fonte aceita). `to_chunk` leva a malha para o espaço
## do trecho; o oclusor fica filho do trecho com transformação identidade e nunca se mexe.
static func note_box(boxes: Array, source: MeshInstance3D, to_chunk: Transform3D) -> void:
	if not enabled or not source.mesh is BoxMesh: return
	var world_box: AABB = source.global_transform * source.get_aabb()
	if world_box.end.y < MIN_TOP: return
	var size: Vector3 = (source.mesh as BoxMesh).size
	var scale := to_chunk.basis.get_scale().abs()
	var span := Vector3(size.x * scale.x, size.y * scale.y, size.z * scale.z)
	var dims := [span.x, span.y, span.z]
	dims.sort()
	if float(dims[2]) < MIN_SPAN or float(dims[1]) < MIN_SECOND: return
	# Meia caixa local já encolhida: SHRINK em metros do trecho, convertido para a escala local de cada eixo.
	var half := Vector3(
		maxf(size.x * 0.5 - SHRINK / maxf(scale.x, 0.0001), 0.01),
		maxf(size.y * 0.5 - SHRINK / maxf(scale.y, 0.0001), 0.01),
		maxf(size.z * 0.5 - SHRINK / maxf(scale.z, 0.0001), 0.01))
	boxes.append({"transform": to_chunk, "half": half, "score": float(dims[2]) * float(dims[1])})

## Monta as arrays num trabalhador e insere no trecho no quadro em que ficarem prontas. Não é esperada pela casca.
static func build(chunk: Node3D, boxes: Array) -> void:
	if not enabled or boxes.is_empty() or not _chunk_alive(chunk) or chunk.get_node_or_null(NODE_NAME) != null: return
	# Prédios grandes primeiro: com o teto, sobra o que mais tapa.
	boxes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	if boxes.size() > MAX_BOXES: boxes.resize(MAX_BOXES)
	var reference: WeakRef = weakref(chunk)
	var tree := chunk.get_tree()
	var out := {}
	var task := WorkerThreadPool.add_task(Callable(_script(), "_assemble").bind(boxes, out), false, "chunk occluders")
	# Toda tarefa é esperada até o fim, mesmo se o trecho sumiu (o dicionário de saída é dela).
	while not WorkerThreadPool.is_task_completed(task): await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	var alive: Variant = reference.get_ref()
	if not _chunk_alive(alive) or not out.has("indices") or (alive as Node).get_node_or_null(NODE_NAME) != null: return
	_commit(alive as Node3D, out.vertices, out.indices, boxes.size())

## Conta pura (segura num trabalhador): 8 cantos e 12 triângulos por caixa, no espaço do trecho.
static func _assemble(boxes: Array, out: Dictionary) -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	const CORNERS := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
	const FACES := [0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4,
		3, 7, 6, 3, 6, 2, 0, 4, 7, 0, 7, 3, 1, 2, 6, 1, 6, 5]
	for box: Dictionary in boxes:
		var half: Vector3 = box.half
		var corners := PackedVector3Array()
		for corner: Vector3 in CORNERS: corners.append(corner * half)
		var base := vertices.size()
		var to_chunk: Transform3D = box.transform
		vertices.append_array(to_chunk * corners)
		for index: int in FACES: indices.append(base + index)
	out.vertices = vertices
	out.indices = indices

static func _commit(chunk: Node3D, vertices: PackedVector3Array, indices: PackedInt32Array, count: int) -> void:
	var began := STALL_WORK.begin()
	var occluder := ArrayOccluder3D.new()
	occluder.set_arrays(vertices, indices)
	var instance := OccluderInstance3D.new()
	instance.name = NODE_NAME
	instance.occluder = occluder
	instance.set_meta("world_unit_skip", true)
	instance.set_meta("chunk_occluder_boxes", count)
	# Inserir reconstrói a BVH do oclusor no cenário: o span dá nome ao pico se ele aparecer no log.
	chunk.add_child(instance)
	var root := chunk.get_tree().root
	if not root.use_occlusion_culling: root.use_occlusion_culling = true
	STALL_WORK.finish_slow("chunk.occluders", began, 1000)

static func _chunk_alive(chunk: Variant) -> bool:
	return is_instance_valid(chunk) and (chunk as Node).is_inside_tree() and not GPU_RELEASE.is_retired(chunk)

static var _self_script: Script
static func _script() -> Script:
	if _self_script == null: _self_script = load("res://world/chunk_bake/ChunkOccluders.gd")
	return _self_script
