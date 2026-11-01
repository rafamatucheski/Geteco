extends RefCounted
## Cache de registros caros (nós montados uma vez e reaproveitados quando o trecho volta) e aposentadoria
## de trechos (filhos liberados folha a folha em fatias de RETIRE_BUDGET_USEC, ou entregues à
## GpuReleaseQueue na desmontagem), separados do NativeRegion em 01/11 (Onda 2) só para ele caber na
## leitura. As listas CACHED_* moram aqui (ninguém de fora as lê). O estado continua no NativeRegion,
## porque testes, sondas e RetainedRegionPreparation leem `_record_cache`, `_retiring` e
## `_retire_stack` lá; RETIRE_BUDGET_USEC fica junto deles. NativeRegion mantém cada função antiga
## como delegação de uma linha (`_drain_retired_slice` é chamada por testes, `_step_record_build`
## sobrescrita por um deles).
## `g` fica como Node3D, e não como o script do NativeRegion, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: EditableRegion e as subclasses de teste
## sobrescrevem `_build_record`, `_step_record_build`..., e o despacho tem de continuar o de antes.
## Roda na thread principal (streaming e pré-aquecimento), como antes.
const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
const HARBOR_ROUTE_FACTORY := preload("res://world/harbor_route_detail/HarborRouteDetailFactory.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Registros que custam 40-80 ms para montar (a vila e a serraria da montanha): o nó pronto é
## guardado ao liberar o chunk e reaproveitado na próxima visita; o pré-aquecimento monta cada um
## uma vez. Só entra em cache quem ainda não tem pai (não está em uso em outro chunk).
## south_port_ship_detail (cordame e acabamento do Santa Mare): 32-59 ms ao entrar no cais (release, 15/10).
const CACHED_RECORDS := ["mountain_village","mountain_forge","forge_hermit_cabin","sawmill_yard","harbor_public_realm","lake","ship","south_port_ship_detail"]
## A carga do Santa Mare custava 590 ms num quadro ao chegar perto (release, 2026-10-13). Montada uma vez
## no pré-aquecimento e reaproveitada como os registros acima. Paletes e tambores (supplies, 50-87 ms cada)
## e os guindastes do cais (crane, 15-28 ms) pesavam igual na travessia e no porto do release de 15/10;
## são estáticos (sem processo, sem saque, sem luz), como a carga.
const CACHED_PORT_MODELS := ["ship_cargo","supplies","crane"]
## Medido em 8 sessões de release (2026-10-12/13): tudo que montou em 50 ms ou mais num quadro.
## Tipos inteiros quando são poucos registros; dos 66 prédios e 131 props só os medidos, para não
## segurar a cidade inteira na memória nem alongar demais o carregamento.
## harbor_dressing entra porque a grama da Cobra agora é espalhada antes de o nó ser guardado
## (RetainedRegionPreparation cede um quadro) e espera a árvore se for chamada fora dela.
## mountain_jeep_scenery (portais e lombadas da trilha do jipe): 24-32 ms num quadro já jogável, na serra e
## na travessia (release, fase 2 de 16/10); estático, sem processo nem luz.
const CACHED_KINDS_MEASURED := ["container","salvage","mountain_place","harbor_dressing","mountain_jeep_scenery","harbor_route_zone"]
const CACHED_BUILDING_IDS := ["NorthFireStation","BridgeCourtWest","PorchHouse","BridgeQuayHouse","BridgeCourtEast",
	"NorthbankFront0","NorthbankFront1","NorthFrontage2","NorthFrontage3","new_1790432236_682_2325181222"]
## harbor_prop medido a 381 ms (posição do registro no chão, x/z).
const CACHED_PROP_POINTS := [Vector2(391.9375,-247.5)]

func _is_cached_record(record: Dictionary) -> bool:
	var kind := str(record.kind)
	if kind in CACHED_RECORDS or kind in CACHED_KINDS_MEASURED: return true
	if kind == "building" and record.get("data") is Dictionary:
		return str(record.data.get("id","")) in CACHED_BUILDING_IDS or g._is_static_editor_skyline(record.data)
	if kind == "harbor_prop" and record.get("position") is Vector3:
		var at := Vector2(record.position.x, record.position.z)
		return CACHED_PROP_POINTS.any(func(point: Vector2): return point.distance_to(at) < 0.5)
	return str(record.kind) == "south_port_model" and str(record.get("model_kind","")) in CACHED_PORT_MODELS

## Prédios urbanos do editor de mundo (urban_infill/slab/deco...): 28-31 ms cada num quadro no release de
## 30/10 dirigindo no Harbor (new_1790426877_636_2342363314 31 ms, new_1790432139_406_2568146191 29 ms,
## new_1790426066_503_97028106 28 ms). O custo é a geometria procedural do UrbanSkylineBuilding.build()
## (janela por janela, andar por andar, juntadas por material) dentro do _ready, inteira no quadro.
## São estáticos (sem porta, placa de venda, luz ou processo), como new_1790432236_682_2325181222 já em
## CACHED_BUILDING_IDS: montados uma vez sob a cortina (RetainedRegionPreparation) e reaproveitados.
## Fica de fora quem o editor transforma em prédio de serviço (editor_service: porta/entrada própria).
func _is_static_editor_skyline(data: Dictionary) -> bool:
	if not data.has("editor_id") or data.has("editor_service"): return false
	return str(data.get("kind","")) in preload("res://world/urban_detail/UrbanSkylineCatalog.gd").TYPES

func _record_cache_key(record: Dictionary) -> String:
	var key := "%s|%s|%s"%[g.region_id,str(record.kind),str(record.get("position",Vector3.ZERO))]
	# Prédios guardam id e posição em `data`: sem isto todos caíam na chave (0, 0, 0) e um reaproveitaria
	# os nós de outro.
	if record.get("data") is Dictionary:
		key += "|%s|%s"%[str(record.data.get("id","")),str(record.data.get("position",""))]
		# Lugares da serra guardam a posição em exterior_position, e as três entradas do abrigo dos
		# lenhadores dividem o id (access_id distingue): sem isto a terceira reaproveitava os nós da
		# primeira, montados no lugar dela, e a porta da terceira ficava num terreno vazio.
		if record.data.has("access_id") or record.data.has("exterior_position"):
			key += "|%s|%s"%[str(record.data.get("access_id","")),str(record.data.get("exterior_position",""))]
	var pieces: Array = [record.get("editor_piece_only", []), record.get("editor_piece_exclude", []), record.get("editor_piece_ids", [])]
	if pieces.any(func(ids): return not ids.is_empty()):
		key += "|pieces=" + JSON.stringify(pieces).sha256_text()
	return key

func _build_record_cached(chunk: Node3D, record: Dictionary) -> void:
	if not g._is_cached_record(record):
		g._build_record(chunk,record)
		return
	var key: String = g._record_cache_key(record)
	if g._record_cache.has(key):
		var nodes: Array = g._record_cache[key]
		var usable := not nodes.is_empty()
		for node in nodes:
			if not is_instance_valid(node) or node.get_parent() != null: usable = false
		if usable:
			for node in nodes: chunk.add_child(node)
			return
		# Entrada substituída: limpar só restos detached, nunca o grupo ativo.
		for node in nodes:
			if is_instance_valid(node) and node.get_parent() == null: node.free()
	var before := chunk.get_child_count()
	g._build_record(chunk,record)
	var built: Array = []
	for index in range(before,chunk.get_child_count()):
		var node := chunk.get_child(index)
		node.set_meta("record_cache_key",key)
		built.append(node)
	g._record_cache[key] = built

## Um registro caro também precisa ceder o quadro; limitar só a fila não limita seu construtor.
## O nó completo passa pelo mesmo editor/cache, sem publicar móveis ou colisões pela metade.
func _step_record_build(chunk: Node3D, record: Dictionary, job: Dictionary, budget_usec: float) -> bool:
	if str(record.kind) != "harbor_route_zone":
		g._build_record_cached(chunk, record)
		return true
	var cached: Array = g._record_cache.get(g._record_cache_key(record), [])
	if not cached.is_empty() and cached.all(func(node): return is_instance_valid(node) and node.get_parent() == null):
		g._cancel_record_build(job)
		g._build_record_cached(chunk, record)
		return true
	if not job.has("route_zone"):
		job.route_zone = HARBOR_ROUTE_FACTORY.begin_zone(str(record.zone_id))
	if job.route_zone.is_empty():
		job.erase("route_zone")
		return true
	var began := STALL_WORK.begin()
	var done: bool = HARBOR_ROUTE_FACTORY.step_zone(job.route_zone, budget_usec)
	STALL_WORK.finish_slow("stream.harbor.route_zone_step", began, 2000)
	if not done: return false
	var prepared: Dictionary = record.duplicate()
	prepared["prepared_route_zone"] = job.route_zone.root
	g._build_record_cached(chunk, prepared)
	job.erase("route_zone")
	return true

func _cancel_record_build(job: Dictionary) -> void:
	if job.has("route_zone"):
		HARBOR_ROUTE_FACTORY.cancel_zone(job.route_zone)
		job.erase("route_zone")

## Tira do chunk os nós em cache antes de liberá-lo, para que sobrevivam.
func _detach_cached_records(chunk: Node3D) -> void:
	if not is_instance_valid(chunk): return
	for child in chunk.get_children():
		if not child.has_meta("record_cache_key"): continue
		var key: String = child.get_meta("record_cache_key")
		# Grupo superseded segue a liberação normal do chunk, sem virar órfão.
		if g._record_cache.get(key, []).has(child):
			preload("res://world/chunk_bake/ChunkCellMerge.gd").restore_sources(child)
			chunk.remove_child(child)

func _retire_chunk(chunk: Node3D) -> void:
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion(): return
	if chunk.has_meta("warm_tunnel_key") and g._warm_tunnel_chunks.size() < g.MAX_WARM_TUNNEL_CHUNKS:
		g._keep_warm_tunnel_chunk(chunk)
		return
	var stall_began := STALL_WORK.begin()
	g._detach_cached_records(chunk)
	STALL_WORK.finish("retire.detach_cached_records", stall_began, {"region": g.region_id})
	stall_began = STALL_WORK.begin()
	# O descarte folha a folha se espalha por quadros. Rigs aposentados precisam parar de animar
	# antes de uma junta ser liberada enquanto o modelo ainda existe na árvore de cena.
	chunk.process_mode = Node.PROCESS_MODE_DISABLED
	chunk.hide()
	# Fusão e casca de sombra em andamento param ao ver a marca (o trecho continua na árvore escondido).
	chunk.set_meta(GPU_RELEASE.RETIRED_META, true)
	g._retiring.append(chunk)
	STALL_WORK.finish("retire.hide_and_enqueue", stall_began, {"region": g.region_id})

func _drain_retired() -> void:
	if g._retiring.is_empty():
		g._cleanup_retired_chairlifts_if_idle()
		return
	var stall_began := STALL_WORK.begin()
	var queued_before: int = g._retiring.size()
	var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT) if STALL_WORK.session_enabled else 0.0
	g._drain_retired_slice()
	g._cleanup_retired_chairlifts_if_idle()
	STALL_WORK.finish("retire.drain", stall_began, {"region": g.region_id, "budget_ms": g.RETIRE_BUDGET_USEC / 1000.0, "queued_before": queued_before, "queued_after": g._retiring.size(), "stack_after":g._retire_stack.size(),
		"nodes_removed_during_slice":nodes_before - Performance.get_monitor(Performance.OBJECT_NODE_COUNT) if STALL_WORK.session_enabled else 0.0,
		"destruction_scope":"synchronous_slice; queued_chunk_deletion_runs_later"})

func _drain_retired_slice() -> void:
	var began := Time.get_ticks_usec()
	while not g._retiring.is_empty():
		var chunk: Node3D = g._retiring[0]
		if not is_instance_valid(chunk):
			g._retiring.pop_front()
			g._retire_stack.clear()
			continue
		if g._retire_stack.is_empty(): g._retire_stack.append(chunk)
		# Só libera folhas: poucos filhos diretos não limitam o tamanho da
		# subárvore (um wrapper pode conter um prédio inteiro).
		while not g._retire_stack.is_empty():
			var top: Node = g._retire_stack.back()
			if not is_instance_valid(top):
				g._retire_stack.pop_back()
				continue
			var count := top.get_child_count()
			if count == 0:
				g._retire_stack.pop_back()
				if top != chunk:
					top.get_parent().remove_child(top)
					# Dona única de malha vai para a fila de vídeo: soltar centenas de buffers juntos
					# prende a thread principal no driver (emenda da ponte, 16/10).
					if not GPU_RELEASE.adopt_detached_leaf(top): top.free()
			else:
				var last := top.get_child(count-1)
				if last.get_child_count() > 0: g._retire_stack.append(last)
				else:
					top.remove_child(last)
					if not GPU_RELEASE.adopt_detached_leaf(last): last.free()
			if Time.get_ticks_usec()-began >= g.RETIRE_BUDGET_USEC: return
		chunk.queue_free()
		g._retiring.pop_front()

## Desmontagem da região (22/10): os trechos em descarte ficavam como filhos escondidos da região, que sai
## da árvore e para de rodar o _process que os liberava. Na volta (a serra perto da ponte remonta o porto a
## cada aproximação) ~2.400 nós de trechos velhos reentravam com ela: mount.add_child 7,8 ms. Antes de a
## região sair, cada um vai inteiro para a fila de vídeo (GpuReleaseQueue), que libera aos poucos fora da
## árvore. Os trechos do túnel guardados de propósito ficam. GETECO_RETIRE_HANDOFF=0 desliga.
func hand_off_retiring() -> int:
	if OS.get_environment("GETECO_RETIRE_HANDOFF") == "0": return 0
	var handed := 0
	for chunk in g._retiring:
		if not is_instance_valid(chunk) or chunk.is_queued_for_deletion(): continue
		if chunk.get_parent() == g: g.remove_child(chunk)
		# A fila recusa subárvore já marcada; a marca volta na mesma chamada.
		chunk.remove_meta(GPU_RELEASE.RETIRED_META)
		GPU_RELEASE.retire_detached_subtree(chunk)
		handed += 1
	g._retiring.clear()
	g._retire_stack.clear()
	g._cleanup_retired_chairlifts_if_idle()
	return handed

func _cleanup_retired_chairlifts_if_idle() -> void:
	if g._retiring.is_empty() and g._chairlift_cleanup_pending:
		g.chairlifts = g.chairlifts.filter(func(lift): return is_instance_valid(lift) and not lift.is_queued_for_deletion())
		g._chairlift_cleanup_pending = false
