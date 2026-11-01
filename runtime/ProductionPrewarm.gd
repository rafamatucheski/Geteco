extends RefCounted
## Pré-aquecimento sob a cortina do ProductionWorld (_prewarm_regions e as filas de desenho/carga, frota:
## cenas retidas, shaders, modelos do despacho e materiais de porta, JIT do roteador), separado em 01/11
## (Onda 2) só para o ProductionWorld.gd caber na leitura; _prewarm_regions, de 172 linhas, virou etapas.
## É componente com estado próprio só no que ninguém de fora lê: `_prewarm_incremental`, `load_lanes`,
## `_early_fleet_paths` e a `static var _retained_lens_variants` moram aqui. As cenas retidas
## (`_fleet_scenes`, `_fleet_extra`, lidas por test_dispatch_model_prewarm), `background_preparation`,
## `_region_cache` e o resto continuam no ProductionWorld, que mantém cada função antiga como delegação
## de uma linha (as que esperam quadro delegam com `await`; _prewarm_regions e _prewarm_dispatch_models
## são chamadas de fora). _trace_cost e _eager_preparation_for_benchmark ficam no dono.
## Roda na thread principal, sob a cortina, como antes; os `await` são os mesmos, na mesma ordem.
## `g` fica como Node, e não como o script do ProductionWorld, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: o despacho continua o de antes. As
## `static var` do dono (TRAFFIC_CAR_TYPES) são lidas por `g.get_script()`.

const PIPELINE_PROBE := preload("res://runtime/PipelineProbe.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

## Prepara o jogo residente e os dados de rota sob a cortina. Mundos nativos
## distantes não montam mais geometria descartável; o I/O de recurso entra na fila depois de jogável.
## Quebrado em etapas em 01/11 (eram 172 linhas numa função): frota, recursos de combate, regiões
## residentes, regiões distantes e grafos de rota, na ordem de antes. Toda saída antecipada das etapas é
## "o mundo saiu da árvore" (inclusive _prepare_geography falso); entre etapas a mesma conferência decide
## se a carga segue. Ela só vem depois de etapa cujo último await já era seguido dessa conferência (ou do
## uso direto do mundo, sem quadro no meio), então quem chegava ao fim antes chega igual.
func _prewarm_regions(curtain: CanvasLayer = null) -> void:
	var incremental := true
	var phase_traced := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	if curtain != null:
		curtain.set_stage(.36, "Carregando veículos…")
		await g.get_tree().process_frame
	PIPELINE_PROBE.stage("world_build")
	await g._hold_fleet_scenes_incremental()
	g._trace_cost("startup:fleet_hold",phase_traced)
	PIPELINE_PROBE.stage("fleet_hold")
	if "--no-prewarm" in OS.get_cmdline_user_args() or g.world.get_meta("skip_prewarm",false): return
	var began := Time.get_ticks_msec()
	# Caixa e cilindros unitários lidos da GPU uma vez, sob a cortina: daí em diante toda fusão de
	# G.box/G.cylinder escala na CPU (MeshArrayCache, GETECO_PRIMITIVE_CPU_ARRAYS).
	preload("res://world/chunk_bake/MeshArrayCache.gd").prewarm_unit_shapes()
	# Recursos da preparação em segundo plano (quase todos shaders) pedidos já, em thread, junto com o
	# resto da carga; recolhidos antes de a cortina sair (BackgroundRegionPreparation.prefetch_collect).
	preload("res://runtime/BackgroundRegionPreparation.gd").prefetch_start()
	await _prewarm_fleet_stage(incremental, curtain)
	await _prewarm_combat_stage(incremental, curtain)
	if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
	await _prewarm_resident_stage(curtain)
	if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
	await _prepare_distant_stage(incremental, curtain)
	if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
	await _prewarm_route_stage(incremental, curtain, began)

## Etapa 1: shaders da frota (lotes desenhados ou compilação escondida) e as variantes de pintura escondidas.
func _prewarm_fleet_stage(incremental: bool, curtain: CanvasLayer) -> void:
	if curtain != null:
		curtain.set_stage(.40, "Compilando shaders do tráfego…")
		await g.get_tree().process_frame
	var phase_traced := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	await g._prewarm_fleet_shaders(incremental, curtain)
	g._trace_cost("startup:fleet_shaders",phase_traced)
	# Pintura suja/molhada/gasta × formatos reais de carro e porta, escondida: compila nos trabalhadores
	# do motor durante o resto da carga (VehicleMaterialVariantPrewarm.start_hidden; sai antes da cortina).
	preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").start_hidden(g.world)

## Etapa 2 (`startup:combat_resources`): danos e marcas de pneu, peças do deserto, filas de desenho e de carga.
## Sai antes do fim só se o mundo saiu da árvore.
func _prewarm_combat_stage(incremental: bool, curtain: CanvasLayer) -> void:
	var phase_traced := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	PIPELINE_PROBE.stage("fleet_shaders")
	var stage_traced := phase_traced
	# As texturas carbonizadas existentes custam ~4.5 ms no primeiro uso. Monta o
	# cache compartilhado delas sob a cortina de carregamento, sem criar fogos nem destroços.
	preload("res://gameplay/vehicle_effects/VehicleDamage.gd")._char(false)
	# O primeiro tiro que muda o desgaste também precisa destes recursos.
	preload("res://gameplay/vehicle_effects/VehicleDamage.gd")._scratches(0)
	preload("res://gameplay/vehicle_effects/VehicleDamage.gd")._dents()
	preload("res://gameplay/vehicle_effects/VehicleTireEffects.gd").prewarm_skid_audio()
	# Variante de shader das marcas de pneu (alfa, sem luz, cor de vértice): compilada sob a cortina e
	# mantida viva pelo material estático, em vez de na primeira derrapagem (163-290 ms no release).
	var mark_primer := MeshInstance3D.new()
	mark_primer.name = "TireMarkPrimer"
	mark_primer.mesh = QuadMesh.new()
	mark_primer.material_override = preload("res://gameplay/vehicle_effects/VehicleTireEffects.gd").mark_material()
	mark_primer.position = Vector3(0, -500, 0)
	g.world.add_child(mark_primer)
	await g.get_tree().process_frame
	if is_instance_valid(mark_primer): mark_primer.queue_free()
	if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
	stage_traced = g._prewarm_mark("damage_marks", stage_traced)
	# Os takes de explosão e a apresentação imutável de fogo eram montados na detonação.
	# Mantém esses recursos limitados prontos, sem criar um incidente vivo.
	if curtain != null:
		curtain.set_stage(.44,"Carregando áudio…")
		await g.get_tree().process_frame
	# Capô aberto do Gol da oficina do Digo, sem ler a GPU quando a oficina entra no streaming do deserto.
	preload("res://world/desert/drag_meet/DesertDigoWorkshop.gd").prewarm_hoods()
	# Fonte e nomes do quadro da arrancada (etapa 15 do chão do deserto: 54 ms no estresse de 21/10).
	preload("res://activities/desert_drag/DesertDragBoardProp.gd").prewarm()
	# Antes das filas: a preparação do deserto (fila resident_regions) monta a oficina com estes prontos.
	stage_traced = g._prewarm_mark("desert_props", stage_traced)
	# Filas da carga (27/10): áudio, modelos das armas e a preparação das regiões residentes esperavam quadros
	# em série (`combat_resources` ~5 s e `resident_prewarm` ~4,9 s a quente, §7.4), enquanto as filas de
	# desenho passam a maior parte do tempo esperando a GPU com o thread principal parado. Agora correm como
	# filas junto com elas. GETECO_LOAD_LANES=0 volta à série. Só com GETECO_PREWARM_PARALLEL ligado.
	_prewarm_incremental = incremental
	load_lanes = OS.get_environment("GETECO_LOAD_LANES") != "0" and OS.get_environment("GETECO_PREWARM_PARALLEL") != "0"
	if not load_lanes:
		await g._prewarm_audio_banks()
		stage_traced = g._prewarm_mark("audio", stage_traced)
	# Pré-aquecimentos de desenho (22/10, 3ª rodada): em série, com o cache frio, cada um esperava sozinho as
	# próprias compilações (combat_resources 31 s no frio, 5 s a quente; a sonda viu 2-8 s por etapa com 3-70
	# pipelines cada). Juntos, todos põem as peças diante da câmera nos mesmos quadros e as compilações correm ao
	# mesmo tempo nos trabalhadores do motor. A Cobra/polícia do tiroteio continua depois dos corpos do Meshy
	# (usa os GLBs já carregados). LIGADO por padrão desde 24/10 (=0 volta à série): na 3ª rodada não houve
	# medição limpa; na 5ª (PC livre, sem Godot externo) o frio ficou 3–5 s mais curto nas 8 rodadas de
	# oeste, serra e deserto e a quente ficou igual em 6 rotas (docs/perf-playthrough-20261021.md §10).
	if OS.get_environment("GETECO_PREWARM_PARALLEL") != "0":
		var lanes: Array = [["local_light_shadow"], ["fire"], ["police_visual"], ["vehicle_variants"], ["bridge_look"],
			["desert_ground_cover"], ["family_variants"], ["painted_facades"], ["wildlife"], ["forge"], ["skate"],
			["meshy_bodies", "spawn_visuals"]]
		if not preload("res://runtime/RainPrewarm.gd").late: lanes.append(["rain"])
		if load_lanes: lanes.append_array([["audio_banks"], ["weapon_templates"], ["resident_regions"]])
		var pending: Array[int] = [lanes.size()]
		for lane in lanes: g._prewarm_lane(lane, pending, curtain)
		if not await g._await_lanes(pending): return
		stage_traced = g._prewarm_mark("parallel_draws", stage_traced)
	else:
		var serial: Array[String] = ["fire", "rain", "police_visual", "vehicle_variants", "bridge_look", "local_light_shadow",
			"desert_ground_cover", "family_variants", "painted_facades", "wildlife", "forge", "skate", "meshy_bodies", "spawn_visuals"]
		if preload("res://runtime/RainPrewarm.gd").late: serial.erase("rain")
		for step in serial:
			await g._draw_prewarm_step(step, curtain)
			if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
			stage_traced = g._prewarm_mark(step, stage_traced)
	if not load_lanes:
		await g._prewarm_weapon_templates()
		if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
	stage_traced = g._prewarm_mark("weapon_templates", stage_traced)
	g._trace_cost("startup:combat_resources",phase_traced)

## Etapa 3 (`startup:resident_prewarm`): regiões já montadas (fora das filas de carga) e a preparação em
## segundo plano. Sai antes do fim só se o mundo saiu da árvore.
func _prewarm_resident_stage(curtain: CanvasLayer) -> void:
	# Um quadro entre as etapas pesadas deixa a tela de carregamento andar; o mundo
	# já está montado e o 'ready_for_play' ainda é falso nesse trecho.
	if curtain != null:
		curtain.set_stage(.46, "Preparando texturas e prédios…")
		await g.get_tree().process_frame
	var phase_traced := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	if not load_lanes: await g._prewarm_resident_regions()
	if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
	g._trace_cost("startup:resident_prewarm",phase_traced)
	PIPELINE_PROBE.stage("resident_prewarm")
	g.background_preparation = preload("res://runtime/BackgroundRegionPreparation.gd").new()
	g.background_preparation.controller = g
	g.add_child(g.background_preparation)
	g.background_preparation.set_process(false)
	if not g._eager_preparation_for_benchmark(): g.background_preparation.enqueue(g.state.region_id)

## Etapa 4: regiões distantes preparadas fora da árvore e guardadas em _region_cache. Sai antes do fim só
## quando _prepare_geography falha, isto é, quando o mundo saiu da árvore.
func _prepare_distant_stage(incremental: bool, curtain: CanvasLayer) -> void:
	for id in ["harbor","mountain","desert"]:
		if g.regions.has(id): continue
		if curtain != null:
			curtain.set_stage(.6 if id == "mountain" else .66, "Preparando " + ("a serra" if id == "mountain" else "o deserto" if id == "desert" else "o porto") + "…")
			await g.get_tree().process_frame
		var detached: Node3D = g._build_region(id)
		if detached == null: continue
		if not await g._prepare_geography(detached): return
		# Aquecer dados/conteudo sem montar uma vizinhanca do spawn que sera descartada.
		detached.initial_prewarm_only = true
		var phase_traced := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
		g.world.add_child(detached)
		g._trace_cost("startup:distant_prepare:"+id,phase_traced)
		phase_traced = Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
		# O pré-aquecimento do deserto prepara só dados compartilhados de terreno/material. Os mundos
		# nativos montavam/descartavam todas as células aqui. Esses montadores procedurais
		# continuam no streaming por proximidade, nunca na fila de recursos em segundo plano.
		if id == "desert" or g._eager_preparation_for_benchmark():
			if incremental: await detached.prewarm_incremental()
			else: detached.prewarm()
		else:
			await preload("res://runtime/RetainedRegionPreparation.gd").run(detached)
		g._trace_cost("startup:distant_prewarm:"+id,phase_traced)
		PIPELINE_PROBE.stage("distant_prewarm:" + id)
		detached.initial_prewarm_only = false
		detached.release_chunks()
		g.world.remove_child(detached)
		g._region_cache[id] = detached
		if not g._eager_preparation_for_benchmark(): g.background_preparation.enqueue(id)

## Etapa 5 (`startup:route_graphs`): grafos de rota de cada combinação de regiões residentes.
func _prewarm_route_stage(incremental: bool, curtain: CanvasLayer, began: int) -> void:
	# Grafos de rota das três combinações residentes, sob a cortina.
	if curtain != null:
		curtain.set_stage(.76, "Traçando rotas do trânsito…")
		await g.get_tree().process_frame
	var live: Dictionary = g.regions.duplicate()
	var all := live.duplicate()
	for id in g._region_cache: all[id] = g._region_cache[id]
	var phase_traced := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	# Serra + deserto (carro deixado na serra, jogador no deserto) faltava: a desmontagem do porto caía nela
	# e refazia o grafo no jogo (routes.configure 40 ms, estresse do deserto de 22/10).
	# GETECO_ROUTE_COMBO_MD=0 volta à lista antiga (A/B).
	var combos: Array = [["harbor"],["mountain"],["desert"],["harbor","mountain"],["harbor","desert"],["mountain","desert"],["harbor","mountain","desert"]]
	if OS.get_environment("GETECO_ROUTE_COMBO_MD") == "0": combos.erase(["mountain","desert"])
	for combo in combos:
		g.regions = {}
		for id in combo:
			if all.has(id): g.regions[id] = all[id]
		if g.regions.size() == combo.size(): g._configure_routes()
		if incremental: await g.get_tree().process_frame
	g.regions = live
	g._configure_routes()
	g.population_layout.configure(g.ambient_roads_cache)
	g._trace_cost("startup:route_graphs",phase_traced)
	PIPELINE_PROBE.stage("route_graphs")
	print("Pré-aquecimento das regiões: ", Time.get_ticks_msec()-began, " ms")

var _prewarm_incremental := false
## Filas de carga junto com as de desenho (GETECO_LOAD_LANES), decidido na etapa de combate e lido na das
## regiões residentes.
var load_lanes := false

func _prewarm_audio_banks() -> void:
	var combat_audio = preload("res://gameplay/CombatAudio.gd")
	await combat_audio.prewarm_reload_banks(g.get_tree())
	await combat_audio.prewarm_gameplay_banks(g.get_tree())
	await preload("res://audio/VehicleCrashAudio.gd").prewarm(g.get_tree())

## Modelos das armas na mão, prontos antes da primeira troca (Gameplay._weapon_template).
func _prewarm_weapon_templates() -> void:
	if OS.get_environment("GETECO_WEAPON_TEMPLATE") == "0": return
	await preload("res://gameplay/ArsenalWeapon3D.gd").warm_templates(g.get_tree(), preload("res://gameplay/WeaponCatalog.gd").WEAPONS.keys())

func _prewarm_resident_regions() -> void:
	if is_instance_valid(g.region) and (g.state.region_id == "desert" or g._eager_preparation_for_benchmark()):
		if _prewarm_incremental: await g.region.prewarm_incremental()
		else: g.region.prewarm()
	elif is_instance_valid(g.region):
		await preload("res://runtime/RetainedRegionPreparation.gd").run(g.region)
	# Vizinhas já montadas (começar na serra monta o porto junto) não passam pelo laço das distantes
	# abaixo: sem isto o porto nunca era preparado e a carga do navio, os prédios e o túnel pesavam
	# ao vivo (release de 2026-10-13, começo na serra).
	for neighbour_id in g.regions.keys():
		var neighbour: Variant = g.regions[neighbour_id]
		if neighbour == g.region or not is_instance_valid(neighbour) or neighbour_id == "desert" or g._eager_preparation_for_benchmark(): continue
		await preload("res://runtime/RetainedRegionPreparation.gd").run(neighbour)
		if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return

func _hold_fleet_scenes() -> void:
	if not g._fleet_scenes.is_empty(): return
	preload("res://gameplay/icecream/IceCreamVan.gd").prewarm()
	# Trânsito e as viaturas do despacho (DispatchRules.ARCHETYPES): nascem e somem igual.
	for id in g.get_script().TRAFFIC_CAR_TYPES+g.TRAFFIC_MOTORCYCLE_TYPES+["police_cruiser","medic_box","rescue_pumper","station_wagon"]:
		var definition: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(id)
		if definition.has("scene"):
			var scene := load(definition.scene)
			if scene != null: g._fleet_scenes.append(scene)

## Preenche os planos de fusão por modelo existentes antes do primeiro despacho.
## O aquecimento de shader de PackedScene cru não roda os decoradores do FleetCatalog.
func _prewarm_dispatch_models() -> void:
	var fleet := preload("res://runtime/FleetCatalog.gd")
	var rules := preload("res://gameplay/dispatch/DispatchRules.gd")
	var traced := Time.get_ticks_usec() if is_instance_valid(g.world) and (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	for id in rules.ARCHETYPES.values():
		var model_traced := Time.get_ticks_usec() if traced else 0
		var model: Node3D = fleet.create(str(id))
		if model != null:
			# Materiais que a porta recortada leva para formatos de vértice novos (FormatPrewarm, desenhados
			# junto com as variantes de pintura). GETECO_FORMAT_PREWARM=0 desliga.
			if preload("res://runtime/FormatPrewarm.gd").enabled():
				var door_materials: Array[Material] = preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").door_materials
				# A viatura do jogo usa o casco de peças soltas (VehiclePanelCatalog): a porta sai dele.
				var sources: Array[Node3D] = [model]
				var panels := preload("res://gameplay/vehicle_effects/VehiclePanelCatalog.gd")
				if panels.supports(str(id)) and OS.get_environment("GETECO_BREAKAWAY_PREWARM") != "0":
					var panel_model := panels.create(str(id))
					if panel_model != null: sources.append(panel_model)
				for source in sources:
					for part in preload("res://gameplay/VehicleDoorBuilder.gd")._parts(source):
						for surface in part.mesh.get_surface_count():
							var material := part.get_active_material(surface)
							if material != null and not material in door_materials: door_materials.append(material)
				for source in sources:
					if source != model: source.free()
			# Arrays da lataria na cópia da CPU (MeshArrayCache), sob a cortina: o preparo da porta da
			# viatura que chega (VehicleDoorBuilder) não lê mais a malha de volta da GPU no jogo.
			if OS.get_environment("GETECO_DOOR_ARRAY_CACHE") != "0":
				for part in preload("res://gameplay/VehicleDoorBuilder.gd")._parts(model):
					for surface in part.mesh.get_surface_count():
						preload("res://world/chunk_bake/MeshArrayCache.gd").arrays_of(part.mesh, surface)
				# A primeira batida de cada viatura lia também as arrays em repouso do amassado (mesma
				# regra de VehicleBodyDents._prepare: sem rodas, interior e corpos com esqueleto).
				for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
					var path := str(model.get_path_to(part)).to_lower()
					if part.mesh == null or part.skeleton != NodePath("") or "wheel" in path or "interior" in path or "rider" in path: continue
					preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd")._rest_arrays(part.mesh)
			model.free()
		g._trace_cost("prewarm_dispatch_model:"+str(id),model_traced)
		await g.get_tree().process_frame
	await g._collect_traffic_door_materials()
	g._trace_cost("startup:dispatch_models",traced)

## Portas dos carros comuns da frota redesenhada (27/10): a folha da porta animada (DriverDoorPresentation)
## leva o material da lataria para o formato da porta e compilava 7 pipelines `surface` num quadro de
## 25–37 ms no oeste e nos sobrados (atlas_crew_pickup, ranch_single, ranch_pickup; sonda de 24–25/10).
## Só as viaturas do despacho entravam em `door_materials`. Um material por assinatura de shader basta:
## o pipeline é por shader × formato, não por instância. GETECO_DOOR_TRAFFIC_PREWARM=0 desliga.
func _collect_traffic_door_materials() -> void:
	if not preload("res://runtime/FormatPrewarm.gd").enabled() or OS.get_environment("GETECO_DOOR_TRAFFIC_PREWARM") == "0": return
	var fleet := preload("res://runtime/FleetCatalog.gd")
	var variants := preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd")
	var door_materials: Array[Material] = variants.door_materials
	var seen := {}
	for material in door_materials: seen[variants.shader_signature(material)] = true
	for id in g.get_script().TRAFFIC_CAR_TYPES:
		if not preload("res://runtime/RedesignedFleet.gd").contains(id): continue
		var began := STALL_WORK.begin()
		var model: Node3D = fleet.create(id)
		if model == null: continue
		for part in preload("res://gameplay/VehicleDoorBuilder.gd")._parts(model):
			for surface in part.mesh.get_surface_count():
				var material := part.get_active_material(surface)
				if material == null: continue
				var signature: String = variants.shader_signature(material)
				if seen.has(signature): continue
				seen[signature] = true
				door_materials.append(material)
		model.free()
		STALL_WORK.finish_slow("startup.traffic_door_materials", began, 4000)
		await g.get_tree().process_frame

func _prewarm_fleet_shaders(_incremental: bool, curtain: CanvasLayer = null) -> void:
	await g._prewarm_dispatch_models()
	var fleet := preload("res://runtime/FleetCatalog.gd")
	var effects := preload("res://gameplay/emergency/EffectsPrewarm.gd")
	# Aquece os modelos de produção decorados e também as cenas-fonte retidas.
	# Uma câmera reserva, não atual, na origem nunca exercitava as passadas de GPU deles.
	# Sob a cortina (runtime/LoadingTurbo.gd) vão 4 modelos por vez, numa grade 2x2 bem dentro do
	# quadro (10 e 13 m à frente, ±2,2 m de lado): as mesmas duas passagens de desenho para cada um,
	# um quarto dos quadros. Era 2,9 s de "Compilando shaders do tráfego" no release de 21/10, um
	# modelo por vez. GETECO_LOADING_TURBO=0 volta a um por vez.
	var batch_size := 4 if preload("res://runtime/LoadingTurbo.gd").active() else 1
	var ids: Array = fleet.all().keys()
	# Cupê, Monaliza, Metro e viatura rodam no jogo com o casco de peças soltas (VehiclePanelCatalog,
	# Vehicle._ready): outra cena, outros materiais de pintura. Sem eles aqui, a pintura suja/molhada desses
	# quatro compilava no jogo (sonda de pipelines, 22/10). GETECO_BREAKAWAY_PREWARM=0 desliga.
	if OS.get_environment("GETECO_BREAKAWAY_PREWARM") != "0":
		for panel_id in preload("res://gameplay/vehicle_effects/VehiclePanelCatalog.gd").IDS: ids.append("breakaway:" + str(panel_id))
	if await g._compile_fleet_hidden(ids, curtain):
		print("startup: dents_rest_prewarm vertices=", preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").fleet_rest_vertices)
		return
	var next := 0
	while next < ids.size():
		var batch: Array[Dictionary] = []
		while batch.size() < batch_size and next < ids.size():
			var id := str(ids[next])
			next += 1
			var created: Node3D = null
			if id.begins_with("breakaway:"):
				id = id.trim_prefix("breakaway:")
				created = preload("res://gameplay/vehicle_effects/VehiclePanelCatalog.gd").create(id)
			else: created = fleet.create(id)
			if created != null: batch.append({"id": id, "model": created})
		if batch.is_empty(): continue
		var camera := g.world.camera as Camera3D
		if DisplayServer.get_name() != "headless" and effects._covered_loading(g.world, curtain) and effects._current_camera(g.world, camera):
			for slot in batch.size():
				var model: Node3D = batch[slot].model
				model.process_mode = Node.PROCESS_MODE_DISABLED
				g.world.add_child(model)
				var row := float(slot / 2)
				var side := 0.0 if batch.size() == 1 else (-2.2 if slot % 2 == 0 else 2.2)
				model.global_position = camera.global_position - camera.global_basis.z * (9.0 + row * 4.0) + camera.global_basis.x * side
			# Lentes apagadas (22/10): VehicleEquipment liga e desliga `emission_enabled` das lentes, outra
			# variante de shader por material de lente; no jogo o equipamento do carro novo compilava duas
			# pipelines no sync do RenderingServer (13–15 ms entre o _process e o desenho, estresse no porto e
			# nos sobrados). Uma cópia de cada modelo com as lentes emissivas apagadas entra no mesmo lote, duas
			# fileiras mais atrás, e passa pelos mesmos dois desenhos; os materiais apagados ficam retidos.
			var dim_copies: Array[Node3D] = []
			if OS.get_environment("GETECO_LENS_VARIANT_PREWARM") != "0":
				for slot in batch.size():
					var copy := (batch[slot].model as Node3D).duplicate(0) as Node3D
					if copy == null: continue
					if g._dim_emissive_lenses(copy) == 0:
						copy.free()
						continue
					copy.process_mode = Node.PROCESS_MODE_DISABLED
					g.world.add_child(copy)
					var row := float(slot / 2) + 2.0
					var side := 0.0 if batch.size() == 1 else (-2.2 if slot % 2 == 0 else 2.2)
					copy.global_position = camera.global_position - camera.global_basis.z * (9.0 + row * 4.0) + camera.global_basis.x * side
					dim_copies.append(copy)
			# Dois desenhos reais, com espera finita quando a janela está minimizada.
			var draws: Array[int] = [0]
			var count_draw := func() -> void: draws[0] += 1
			RenderingServer.frame_post_draw.connect(count_draw)
			for frame in 12:
				await g.get_tree().process_frame
				if not effects._covered_loading(g.world, curtain): break
				if draws[0] >= 2: break
			RenderingServer.frame_post_draw.disconnect(count_draw)
			for copy in dim_copies:
				if is_instance_valid(copy): copy.free()
		for entry in batch:
			var model: Node3D = entry.model
			# Bases de pintura para as variantes de uso/desgaste (desenhadas depois).
			preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").collect(model, str(entry.id))
			# Vidros na CPU para medir a cabine em jogo sem ler a malha da GPU (VehicleInterior.spec).
			preload("res://gameplay/VehicleInterior.gd").cache_glass(model)
			# Lataria em repouso de cada modelo para o 1º amassado (VehicleBodyDents.prewarm_rest).
			preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").prewarm_rest(model)
			model.free()
		await g.get_tree().process_frame
	print("startup: dents_rest_prewarm vertices=", preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").fleet_rest_vertices)

## A frota inteira (e as cópias de lentes apagadas) escondida de uma vez antes dos lotes desenhados
## (22/10, 3ª rodada): com o cache frio cada lote de 4 compilava seus shaders na thread principal, um depois
## do outro (fleet_shaders 7,2 s frio × 2,3 s quente). Escondidas, as pipelines compilam em paralelo nos
## trabalhadores (runtime/HiddenCompile.gd). Com GETECO_FLEET_HIDDEN_ONLY (padrão) os lotes desenhados diante
## da câmera nem acontecem: a pipeline que trava (a "ubershader" da superfície) já ficou pronta escondida, e a
## especialização de cada carro é feita em segundo plano no jogo, sem quadro esperando. Devolve true quando
## fez tudo o que os lotes faziam (bases de pintura, vidros, lataria em repouso). Só com GETECO_HIDDEN_COMPILE=1.
func _compile_fleet_hidden(ids: Array, curtain: CanvasLayer) -> bool:
	if not preload("res://runtime/HiddenCompile.gd").enabled() or DisplayServer.get_name() == "headless": return false
	if not preload("res://gameplay/emergency/EffectsPrewarm.gd")._covered_loading(g.world, curtain): return false
	var hidden_only := OS.get_environment("GETECO_FLEET_HIDDEN_ONLY") != "0"
	var primaries: Array[Dictionary] = []
	var holder := Node3D.new()
	holder.name = "FleetHiddenCompile"
	holder.visible = false
	g.world.add_child(holder)
	var lens_dim := OS.get_environment("GETECO_LENS_VARIANT_PREWARM") != "0"
	var fade_copies := OS.get_environment("GETECO_WRECK_FADE_PREWARM") == "1"
	for raw_id in ids:
		var id := str(raw_id)
		var model: Node3D = null
		if id.begins_with("breakaway:"): model = preload("res://gameplay/vehicle_effects/VehiclePanelCatalog.gd").create(id.trim_prefix("breakaway:"))
		else: model = preload("res://runtime/FleetCatalog.gd").create(id)
		if model == null: continue
		model.process_mode = Node.PROCESS_MODE_DISABLED
		holder.add_child(model)
		primaries.append({"id": id.trim_prefix("breakaway:"), "model": model})
		if lens_dim:
			var copy := model.duplicate(0) as Node3D
			if copy != null:
				if g._dim_emissive_lenses(copy) == 0: copy.free()
				else:
					copy.process_mode = Node.PROCESS_MODE_DISABLED
					holder.add_child(copy)
		# Carcaça sumindo (Vehicle._tick_wreck põe `transparency` em todas as malhas): os materiais do carro
		# no passe alfa. No estresse com cache frio o 1º sumiço compilou 5 pipelines `draw` num quadro de
		# 3,0 s (export D, 22/10). Desligado por padrão (GETECO_WRECK_FADE_PREWARM=1): ganho não medido limpo.
		if fade_copies:
			var faded := model.duplicate(0) as Node3D
			if faded != null:
				for found in faded.find_children("*", "GeometryInstance3D", true, false): (found as GeometryInstance3D).transparency = .5
				faded.process_mode = Node.PROCESS_MODE_DISABLED
				holder.add_child(faded)
	# Insígnia dos carros da Cobra (CobraAppearance.livery/race_livery), posta no carro ao nascer.
	holder.add_child(preload("res://gameplay/urban_v1/CobraAppearance.gd").insignia(1.0))
	await preload("res://runtime/HiddenCompile.gd").settle(g.get_tree())
	if hidden_only:
		for entry in primaries:
			var model: Node3D = entry.model
			if not is_instance_valid(model): continue
			# O mesmo que os lotes desenhados fazem com cada modelo antes de liberá-lo.
			preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").collect(model, str(entry.id))
			preload("res://gameplay/VehicleInterior.gd").cache_glass(model)
			preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").prewarm_rest(model)
	if is_instance_valid(holder): holder.free()
	return hidden_only

## Cópia apagada (sem emissão) de cada material emissivo do modelo, retida por chave de variante.
static var _retained_lens_variants: Dictionary = {}
func _dim_emissive_lenses(model: Node3D) -> int:
	var count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null: continue
		var surfaces: int = 1 if part.material_override != null else part.mesh.get_surface_count()
		for surface in surfaces:
			var original := part.get_active_material(surface) as StandardMaterial3D
			if original == null or not original.emission_enabled: continue
			var dark := original.duplicate() as StandardMaterial3D
			dark.emission_enabled = false
			dark.emission_energy_multiplier = 0.0
			if part.material_override != null: part.material_override = dark
			else: part.set_surface_override_material(surface, dark)
			var key := str(original.get_instance_id())
			if not _retained_lens_variants.has(key): _retained_lens_variants[key] = dark
			count += 1
	return count

func _hold_fleet_scenes_incremental() -> void:
	if not g._fleet_scenes.is_empty(): return
	# Só _hold_fleet_scenes (sem chamadores) pré-aquecia o carro de sorvete: a primeira van no
	# trânsito montava palhaços (26 ms), pintura do teto (11 ms) e teto (3 ms) num quadro
	# (serra, EXE perfinv6 de 17/10); a segunda custava 0,3 ms.
	preload("res://gameplay/icecream/IceCreamVan.gd").prewarm()
	preload("res://runtime/VehicleUsage.gd").prewarm()
	# A 1ª morte fazia load() síncrono da biblioteca Mixamo (auditoria de 19/10, §5).
	preload("res://gameplay/MixamoDeath.gd").prewarm()
	# Mesma regra para o levantar do chão (atropelado, tirado do carro): nada de load() no 1º tombo.
	preload("res://gameplay/street_physics/BodyGetUp3D.gd").prewarm()
	var ids: Array = g.get_script().TRAFFIC_CAR_TYPES + g.TRAFFIC_MOTORCYCLE_TYPES + ["police_cruiser", "medic_box", "rescue_pumper", "station_wagon"]
	ids.append(str(g.starting_vehicle().get("archetype", "sport_coupe")))
	for record in g.state.world_state.get("garage_rewards", {}).get("vehicles", {}).values():
		ids.append(str(record.get("archetype", "")))
	var paths: Array[String] = []
	for id in ids:
		var definition: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(id)
		var path := str(definition.get("scene", ""))
		if path.is_empty() or path in paths: continue
		paths.append(path)
	await g._retain_fleet_paths(paths, g._fleet_scenes)
	await g._request_remaining_fleet_scenes(paths)

## Cenas da frota pedidas em thread logo no começo da carga (22/10): "Carregando veículos…" esperava
## 2 cenas por vez, com um quadro entre os pares (2,0 s no oeste a 3440x1440), depois de "Montando o
## porto" (5,7 s de trabalho no thread principal). Pedidas no início, a leitura e a montagem dos recursos
## correm nos trabalhadores durante a montagem do porto; a etapa só recolhe. GETECO_FLEET_EARLY=0 desliga.
var _early_fleet_paths: Dictionary = {}
func _request_fleet_scenes_early() -> void:
	if OS.get_environment("GETECO_FLEET_EARLY") == "0" or DisplayServer.get_name() == "headless": return
	var fleet := preload("res://runtime/FleetCatalog.gd")
	for id in fleet.all().keys():
		var path := str(fleet.spec(str(id)).get("scene", ""))
		if path.is_empty() or _early_fleet_paths.has(path) or ResourceLoader.has_cached(path): continue
		if ResourceLoader.load_threaded_request(path) == OK: _early_fleet_paths[path] = true

func _retain_fleet_paths(paths: Array[String], retained: Array[Resource]) -> void:
	# O renderizador dummy headless não consegue alocar esses RIDs de malha em paralelo.
	# Ele ainda carrega/retém os recursos reais, em sequência, para os testes de contrato.
	if DisplayServer.get_name() == "headless":
		for path in paths:
			var resource := load(path)
			if resource != null: retained.append(resource)
			await g.get_tree().process_frame
		return
	# Limita a pressão de alocação/envio de recursos em vez de inundar o pool de
	# workers com todos os veículos de uma vez. Mantém um quadro entre pedidos concluídos.
	var requested: Array[String] = []
	for path in paths:
		requested.append(path)
		if requested.size() < 2 and path != paths.back(): continue
		var early_pair := true
		for pending_path in requested:
			# Já pedida no começo (_request_fleet_scenes_early): só recolhe, sem segundo pedido.
			if _early_fleet_paths.has(pending_path): continue
			early_pair = false
			ResourceLoader.load_threaded_request(pending_path)
		for pending_path in requested:
			while ResourceLoader.load_threaded_get_status(pending_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await g.get_tree().process_frame
			if ResourceLoader.load_threaded_get_status(pending_path) == ResourceLoader.THREAD_LOAD_LOADED:
				retained.append(ResourceLoader.load_threaded_get(pending_path))
			_early_fleet_paths.erase(pending_path)
		requested.clear()
		# Pedidas no começo já carregaram com o porto: sem o quadro de folga entre pares.
		if early_pair: continue
		await g.get_tree().process_frame

## O primeiro uso do espelho C# (RoadGraphSearch.cs) paga ~22 ms de JIT de Build/NearestEdge/
## Plan/BuildPath (medido em 05/10, docs/reviews/dispatch-plan-stall-20261005.md). Perto do
## terminal, prepare_startup_route já paga isso sob a cortina; longe dele o custo caía no
## primeiro despacho/ônibus/PortHaul em pleno jogo. Um roteador descartável compila os mesmos
## métodos sem tocar no estado dos roteadores reais (bloqueios, relógio, espelho) nem no RNG.
## HARBOR_ROUTER_JIT_PREWARM=0 desliga, para A/B.
func _prewarm_route_jit() -> void:
	if OS.get_environment("HARBOR_ROUTER_JIT_PREWARM") == "0": return
	if g.traffic_routes == null or g.traffic_routes.vertices.size() < 2: return
	var began := Time.get_ticks_usec()
	var router: RefCounted = preload("res://gameplay/dispatch/DispatchRoadRouter.gd").new()
	router.configure(g.traffic_routes)
	var count: int = g.traffic_routes.vertices.size()
	var planned := false
	# Alguns pares podem não ter caminho (mão única); só um plano completo exercita BuildPath.
	for step in [2, 3, 5, 7]:
		var result: Dictionary = router.plan(g.traffic_routes.vertices[0], g.traffic_routes.vertices[count / step])
		if result.get("ok", false):
			planned = true
			break
	var elapsed := Time.get_ticks_usec() - began
	print("startup: route_jit_prewarm native=%s planned=%s ms=%.3f" % [router._native != null, planned, elapsed / 1000.0])
	if g.world.get_meta("benchmark_trace", false): g._trace_cost("startup:route_jit_prewarm", began)

## Espera as filas paralelas. Uma etapa que pare com erro de script nunca devolveria a vez e a cortina ficaria
## presa: depois de LANE_DEADLINE_MSEC a carga segue com aviso (o pré-aquecimento que faltou compila no jogo).
## Devolve false se o mundo saiu da árvore no meio.
const LANE_DEADLINE_MSEC := 180000
func _await_lanes(pending: Array[int]) -> bool:
	var deadline := Time.get_ticks_msec() + LANE_DEADLINE_MSEC
	while pending[0] > 0:
		await g.get_tree().process_frame
		if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return false
		if Time.get_ticks_msec() > deadline:
			push_warning("Pré-aquecimento em paralelo: %d fila(s) não terminaram em %d s; a carga segue." % [pending[0], int(LANE_DEADLINE_MSEC / 1000.0)])
			break
	return true

## Uma fila de pré-aquecimentos de desenho em série; várias filas correm juntas (GETECO_PREWARM_PARALLEL).
## Chamada sem await: cada etapa espera os próprios quadros e `pending` cai quando a fila acaba.
func _prewarm_lane(steps: Array, pending: Array[int], curtain: CanvasLayer) -> void:
	for step in steps:
		if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): break
		var traced := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
		await g._draw_prewarm_step(str(step), curtain)
		g._trace_cost("startup:prewarm:" + str(step), traced)
	pending[0] -= 1

func _draw_prewarm_step(step: String, curtain: CanvasLayer) -> void:
	match step:
		"fire":
			preload("res://gameplay/emergency/Fire.gd").prewarm_visuals()
			await preload("res://gameplay/emergency/EffectsPrewarm.gd").run(g.world, curtain)
		"rain": await preload("res://runtime/RainPrewarm.gd").run(g.world, curtain)
		"police_visual": await preload("res://gameplay/emergency/PoliceVisualPrewarm.gd").run(g.world, curtain)
		"vehicle_variants": await preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").run(g.world, curtain)
		"bridge_look": await preload("res://runtime/BridgeLookPrewarm.gd").run(g.world, curtain)
		# Omni (cubo e paraboloide) e spot com sombra + chão natural opaco e de borda: a feature de
		# pipeline de sombra local passa a existir antes do jogo (túnel da ponte, lanterna, faróis).
		"local_light_shadow": await preload("res://runtime/LocalLightShadowPrewarm.gd").run(g.world, curtain)
		"desert_ground_cover": await preload("res://world/desert/DesertGroundCover.gd").prewarm_draw(g.world, curtain)
		"family_variants": await preload("res://runtime/FamilyVariantPrewarm.gd").run(g.world, curtain)
		"painted_facades": await preload("res://runtime/PaintedFacadePrewarm.gd").run(g.world, curtain)
		"wildlife": await preload("res://runtime/WildlifePrewarm.gd").run(g.world, curtain)
		"forge": await preload("res://runtime/ForgePrewarm.gd").run(g.world, curtain)
		"skate": await preload("res://activities/skate/SkateModel.gd").prewarm_colors(g.world)
		"meshy_bodies": await preload("res://assets/civilians/MeshyBodyPrewarm.gd").run(g.world, curtain)
		# Primeira aparição da Cobra e da polícia no tiroteio (sumiço do morto, itens largados, giroflex):
		# quadros de 588-646 ms no desenho no release de 17/10. Depois dos GLBs do Meshy, já carregados acima.
		"spawn_visuals": await preload("res://gameplay/emergency/SpawnVisualPrewarm.gd").run(g.world, curtain)
		"street_fx": await preload("res://gameplay/street_physics/StreetEffectsPrewarm.gd").run(g.world, curtain)
		# Aquece depois que o CityLook liga o framebuffer Mobile final (incluindo glow).
		"reaction_visuals": await preload("res://gameplay/emergency/ReactionVisualPrewarm.gd").run(g.world, curtain)
		"vehicle_interior": await preload("res://gameplay/VehicleInteriorMaterialPrewarm.gd").run(g.world, curtain)
		# Tiros, impactos, explosão e armas na mão desenhados diante da câmera (cache de pipeline frio).
		"combat_effects": await preload("res://gameplay/CombatEffectsPrewarm.gd").run(g.world, curtain)
		# Filas de carga sem desenho (GETECO_LOAD_LANES): correm junto com as de desenho.
		"audio_banks": await g._prewarm_audio_banks()
		"weapon_templates": await g._prewarm_weapon_templates()
		"resident_regions": await g._prewarm_resident_regions()
		# Silhueta de oclusão nos formatos de carro e no jogador, mobília dos prédios do porto (sonda de 22–25/10).
		"late_surfaces": await preload("res://runtime/LateSurfacePrewarm.gd").run(g.world, curtain)

## Etapas do pré-aquecimento com nome (22/10, 3ª rodada): no cache frio `startup:combat_resources` levava
## 31 s (5 s a quente) e só o total ia ao registro. Cada etapa vai ao registro da sessão
## (`startup:prewarm:<nome>`) e fecha a etapa na sonda de pipelines (GETECO_PIPELINE_PROBE=1).
func _prewarm_mark(label: String, began: int) -> int:
	g._trace_cost("startup:prewarm:" + label, began)
	PIPELINE_PROBE.stage(label)
	return Time.get_ticks_usec() if began != 0 else 0

## Os demais modelos da frota (polícia, empilhadeira, viaturas do porto...) eram lidos do disco
## na hora em que nasciam: 650 ms num quadro (medido: `port_forklift`, `PoliceMotorPool`). São
## poucos MB no total; a leitura corre em segundo plano e o carregamento posterior acha em cache.
func _request_remaining_fleet_scenes(already: Array[String]) -> void:
	var extra: Array[String] = []
	for id in preload("res://runtime/FleetCatalog.gd").all():
		var path := str(preload("res://runtime/FleetCatalog.gd").spec(id).get("scene", ""))
		if path.is_empty() or path in already or path in extra: continue
		extra.append(path)
	await g._retain_fleet_paths(extra, g._fleet_extra)
