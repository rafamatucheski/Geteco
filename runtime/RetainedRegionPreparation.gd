extends RefCounted
## Guarda somente modelos cujos nos construidos sobrevivem a preparacao.
## Reaproveita caches prontos sem remontar/percorre-los, e agrupa trabalho curto
## no mesmo quadro. O streamer continua dono da geometria descartavel.
const PREPARE_BUDGET_USEC := 2000.0

static func run(region: Node3D) -> void:
	var slice_started := Time.get_ticks_usec()
	for key in region.records:
		if region.chunks.has(key): continue
		var warm_chunks: Variant = region.get("_warm_tunnel_chunks")
		if warm_chunks is Dictionary and is_instance_valid(warm_chunks.get(key)): continue
		for record in region.records[key]:
			if Time.get_ticks_usec() - slice_started >= PREPARE_BUDGET_USEC:
				await region.get_tree().process_frame
				if not _live(region): return
				slice_started = Time.get_ticks_usec()
			# _is_cached_record inclui a carga do navio (CACHED_PORT_MODELS), não só CACHED_RECORDS.
			if not region._is_cached_record(record): continue
			if _has_detached_record(region, record): continue
			var temporary := Node3D.new()
			temporary.name = "RetainedModelPreparation"
			region.add_child(temporary)
			var job := {}
			while not region._step_record_build(temporary, record, job, maxf(1.0, PREPARE_BUDGET_USEC - (Time.get_ticks_usec() - slice_started))):
				await region.get_tree().process_frame
				if not _live(region) or not is_instance_valid(temporary):
					_cancel_record_job(region, job)
					_release_temporary(region, temporary)
					return
				slice_started = Time.get_ticks_usec()
			# Um quadro ainda na árvore para quem tem trabalho adiado na montagem (a grama da Cobra custava
			# 192 ms num call_deferred ao vivo): roda aqui, atrás da cortina, antes de guardar o nó. Só
			# esse tipo: um quadro por registro somou ~8 s no carregamento do editor.
			if str(record.kind) == "harbor_dressing":
				await region.get_tree().process_frame
				if not _live(region) or not is_instance_valid(temporary):
					_release_temporary(region, temporary)
					return
				slice_started = Time.get_ticks_usec()
			region._hold_file_resources(temporary)
			region._suspend_chunk_mechanisms(temporary)
			region._detach_cached_records(temporary)
			temporary.free()
	# O porto prepara o corte do tunel e preserva seus trechos para o uso real.
	# A propria regiao limita a retencao e evita repetir o primer.
	if str(region.region_id) == "harbor": await region.prime_tunnel_corridor()

static func _live(region: Node3D) -> bool:
	return is_instance_valid(region) and region.is_inside_tree() and not region.is_queued_for_deletion()

## A chave atual ja inclui os recortes/IDs do editor. Sem marca permanente: se
## um no sumir ou a chave mudar, a preparacao passa outra vez pelo construtor.
static func _has_detached_record(region: Node3D, record: Dictionary) -> bool:
	var key: String = region._record_cache_key(record)
	var nodes: Array = region._record_cache.get(key, [])
	if nodes.is_empty(): return false
	for node in nodes:
		if not is_instance_valid(node) or node.get_parent() != null: return false
	return true

static func _cancel_record_job(region: Node3D, job: Dictionary) -> void:
	if is_instance_valid(region):
		region._cancel_record_build(job)
	elif job.has("route_zone"):
		preload("res://world/harbor_route_detail/HarborRouteDetailFactory.gd").cancel_zone(job.route_zone)
		job.erase("route_zone")

## Uma regiao removida da arvore pode voltar no mesmo jogo. Nao deixar o
## container temporario com o modelo parentado: isso impediria o reuso do cache.
static func _release_temporary(region: Node3D, temporary: Node3D) -> void:
	if not is_instance_valid(temporary): return
	if is_instance_valid(region): region._detach_cached_records(temporary)
	temporary.free()
