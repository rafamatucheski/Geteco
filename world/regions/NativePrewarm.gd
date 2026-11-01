extends RefCounted
## Pré-aquecimento das células sob a cortina (prewarm, prewarm_incremental), o corredor do túnel
## mantido aquecido e a retenção dos recursos de arquivo dos trechos aquecidos, separados do
## NativeRegion em 01/11 (Onda 1). O estado (_warm_tunnel_chunks, _tunnel_corridor_primed,
## _held_resources, chunks, build_jobs) continua no NativeRegion, que mantém cada função antiga como
## delegação de uma linha; as que esperam quadro (`await`) delegam com `await`. Roda na thread
## principal, como antes.
## `g` fica como Node3D, e não como o script do NativeRegion, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: EditableRegion e as subclasses de
## teste sobrescrevem funções do dono (`_hold_file_resources`, `_build_record`, `_run_build_job`...),
## e o despacho tem de continuar o de antes.
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const TUNNEL_CUTAWAY := preload("res://world/urban_detail/TunnelCutaway.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Constrói e descarta uma vez cada célula com conteúdo, sob a cortina de
## carregamento: texturas/malhas procedurais geradas na primeira aparição
## (acabamento urbano até 226 ms, porto sul 399 ms) ficam em cache e não
## travam a direção. Células já carregadas são preservadas.
func prewarm() -> void:
	for key in g.records.keys():
		if g.chunks.has(key): continue
		g._build_chunk(key)
		var chunk: Node3D = g.chunks[key]
		g._hold_file_resources(chunk)
		g._suspend_chunk_mechanisms(chunk)
		g._detach_cached_records(chunk)
		g.chunks.erase(key)
		chunk.free()
	g.chairlifts = g.chairlifts.filter(func(lift): return is_instance_valid(lift))

## Aquece recursos compartilhados usando o orçamento de streaming existente e as células residentes.
## O menu precisa manter desenho/entrada vivos enquanto estas células fora da tela aquecem.
func prewarm_incremental() -> void:
	# Termina primeiro os trabalhos residentes. Senão uma célula de aquecimento fora da tela poderia
	# consumir uma chave residente pendente e depois descartar geometria de que a câmera precisa.
	while not g.is_streaming_idle():
		await g.get_tree().process_frame
	for key in g.records.keys():
		if g.chunks.has(key): continue
		g._build_chunk(key, false, true)
		var chunk: Node3D = g.chunks[key]
		while g.build_jobs.any(func(job): return job.key == key):
			await g.get_tree().process_frame
		if g.region_id == "harbor": TUNNEL_CUTAWAY.prime(chunk, g, Rect2(key.x*g.CELL,key.y*g.CELL,g.CELL,g.CELL))
		g._hold_file_resources(chunk)
		g._suspend_chunk_mechanisms(chunk)
		g._detach_cached_records(chunk)
		g.chunks.erase(key)
		chunk.queue_free()
		await g.get_tree().process_frame
	g.chairlifts = g.chairlifts.filter(func(lift): return is_instance_valid(lift))

func prime_tunnel_corridor() -> void:
	if g._tunnel_corridor_primed: return
	var began := STALL_WORK.begin()
	while not g.is_streaming_idle():
		await g.get_tree().process_frame
	var reach: Rect2 = TUNNEL_CUTAWAY.corridor_rect()
	var primed_chunks := 0
	var keys: Array[Vector2i] = []
	for x in range(floori(reach.position.x/g.CELL), ceili(reach.end.x/g.CELL)):
		for z in range(floori(reach.position.y/g.CELL), ceili(reach.end.y/g.CELL)):
			keys.append(Vector2i(x,z))
	for key in keys:
		var rect := Rect2(key.x*g.CELL,key.y*g.CELL,g.CELL,g.CELL)
		if g.chunks.has(key): continue
		g._build_chunk(key, false, true)
		var chunk: Node3D = g.chunks[key]
		while g.build_jobs.any(func(job): return job.key == key):
			await g.get_tree().process_frame
			if not g.is_inside_tree() or g.is_queued_for_deletion(): return
		TUNNEL_CUTAWAY.prime(chunk, g, rect)
		g._hold_file_resources(chunk)
		g._suspend_chunk_mechanisms(chunk)
		g.chunks.erase(key)
		if g._warm_tunnel_chunks.size() < g.MAX_WARM_TUNNEL_CHUNKS:
			chunk.set_meta("warm_tunnel_key", key)
			g._keep_warm_tunnel_chunk(chunk)
		else:
			g._detach_cached_records(chunk)
			chunk.queue_free()
		primed_chunks += 1
		await g.get_tree().process_frame
	g._tunnel_corridor_primed = true
	STALL_WORK.finish("tunnel.cutaway.prime_corridor", began, {"chunks": primed_chunks})

func _keep_warm_tunnel_chunk(chunk: Node3D) -> void:
	chunk.set_meta("warm_tunnel_process_mode", chunk.process_mode)
	chunk.process_mode = Node.PROCESS_MODE_DISABLED
	chunk.hide()
	g._warm_tunnel_chunks[chunk.get_meta("warm_tunnel_key")] = chunk

## Recursos vindos de arquivo (scripts, malhas, materiais, fontes) usados pelo chunk
## pré-aquecido. Sem referência viva eles saíam do cache ao descartar o chunk e a
## primeira visita real relia do disco. Recursos procedurais (sem caminho) não entram.
func _hold_file_resources(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		g._hold_resource(node.get_script())
		# Modelo instanciado de .tscn: as malhas embutidas vivem enquanto a cena vive.
		if not node.scene_file_path.is_empty() and not g._held_resources.has(node.scene_file_path):
			g._held_resources[node.scene_file_path] = load(node.scene_file_path)
		if node is MeshInstance3D:
			g._hold_resource(node.mesh)
			g._hold_resource(node.material_override)
		elif node is Label3D:
			g._hold_resource(node.font)
		for child in node.get_children(): stack.append(child)

func _hold_resource(resource: Variant) -> void:
	if resource is Resource and not (resource as Resource).resource_path.is_empty() and not (resource as Resource).resource_path.contains("::"):
		g._held_resources[(resource as Resource).resource_path] = resource
