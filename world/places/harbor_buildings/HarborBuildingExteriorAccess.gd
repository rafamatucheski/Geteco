extends Node3D
## Um adaptador preguiçoso de porta/colisão. Os exteriores originais ficam intactos até
## um cômodo próximo ser preparado; os mesmos volumes cortados servem ao visual e aos sólidos.
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const RESTAURANT_VENUES := {"CornerDiner":"anchor","PromenadeCafe":"tideline","ServiceCafe":"early_shift"}
var definition: Dictionary
var facade: Node3D
var access_ready := false
var _prepared := false
var _open := false
var _view_key := ""
var _meshes: Array[Dictionary] = []
var _multimeshes: Array[Dictionary] = []
var _labels: Array[Dictionary] = []
var _effects: Array[Dictionary] = []
var _roof_prop_ids := {}
var _original_shapes: Array[Dictionary] = []
var _replacement_body: StaticBody3D
var _door_visual: Node3D
var _scan_clock := 0.0
var _view_floor := -1
var _view_storey := 3.0
var _view_rooftop := false
## Lotes MultiMesh já varridos (id -> instance_count) e malhas já recusadas por
## _relevant_visual. A varredura de 0,5 s com o jogador dentro refazia, a cada
## passada, o laço GDScript por TODAS as instâncias dos lotes CityLook_ do trecho
## que não tinham nada nesta parcela (só os capturados eram pulados). Peças de
## apresentação não se mexem: a resposta de antes continua valendo.
var _scanned_batches := {}
var _rejected_meshes := {}
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
## Preparação fatiada (29/10): na partida release de 29/10 o corte da Torque (lote inteiro
## agrupado por material, todo capturado por _relevant_visual) custou 127 ms num quadro só,
## síncrono a 8 m da porta. Agora o laço do thread principal cede o quadro a cada ~2 ms e o
## recorte de triângulos (GDScript puro) roda no WorkerThreadPool; só a leitura das arrays
## (MeshArrayCache), o ArrayMesh e as colisões ficam no thread principal.
const PREP_SLICE_USEC := 2000
## Ticket da preparação fatiada em curso: a síncrona (set_open_amount antes do fim) o
## invalida e a fatiada descarta o que montou, sem mexer no estado já publicado.
var _prep_ticket := 0
var _prep_running := false
## Estatística da última preparação fatiada (testes e diagnóstico).
var last_prepare_stats := {}
## Meta opcional numa malha montada em código: Array com as arrays de cada superfície já na
## CPU (quem monta a malha as tem). O corte usa estas antes de pedir ao MeshArrayCache.
const CPU_ARRAYS_META := &"cpu_surface_arrays"

func _ready() -> void:
	set_process(false)

static func install(art: Node3D, source_id: String) -> Node3D:
	var def := CATALOG.for_source(source_id)
	if def.is_empty() or art == null: return null
	var existing := art.get_node_or_null("BuildingAccess")
	if existing != null: return existing
	var access: Node3D = load("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd").new()
	access.name = "BuildingAccess"
	access.definition = def
	access.facade = art
	art.add_child(access)
	access.global_transform = Transform3D(Basis(Vector3.UP,float(def.exterior_rotation)),def.exterior_position)
	access.set_meta("place_id",def.id)
	access.add_to_group("harbor_building_facade")
	access.call_deferred("_sync_transform")
	return access

func _sync_transform() -> void:
	global_transform = Transform3D(Basis(Vector3.UP,float(definition.exterior_rotation)),definition.exterior_position)

func set_open_amount(value: float) -> void:
	if value <= .01: return
	if not _prepared: _prepare_access()
	if _open: return
	_open = true
	for item in _original_shapes:
		if is_instance_valid(item.node): item.node.set_deferred("disabled",true)
	_replacement_body.collision_layer = 1
	if _door_visual != null: _door_visual.show()
	for item in _multimeshes:
		if is_instance_valid(item.node): item.node.multimesh = item.opened
	for item in _meshes:
		if is_instance_valid(item.node):
			item.node.mesh = item.open_mesh
			item.node.visible = item.visible and item.open_mesh != null
	access_ready = true
	_view_key = ""

func restore_exterior() -> void:
	if not _prepared: return
	for item in _meshes:
		if is_instance_valid(item.node):
			item.node.mesh = item.original
			item.node.visible = item.visible and not item.get("derived",false)
	for item in _multimeshes:
		if is_instance_valid(item.node): item.node.multimesh = item.original
	for item in _original_shapes:
		if is_instance_valid(item.node): item.node.set_deferred("disabled",item.disabled)
	_replacement_body.collision_layer = 0
	if _door_visual != null: _door_visual.hide()
	_hold_painted_doors(false)
	for item in _labels:
		if is_instance_valid(item.node): item.node.visible = item.visible
	for item in _effects:
		if is_instance_valid(item.node): item.node.visible = item.visible
	access_ready = false
	_open = false
	_view_key = ""
	set_process(false)

func set_floor_view(floor_index: int, storey_height: float, rooftop := false) -> void:
	if not _prepared: _prepare_access()
	set_open_amount(1.0)
	# Jogador dentro: a folha pintada da entrada fica aberta até ele sair.
	_hold_painted_doors(true)
	var key := "%d/%s"%[floor_index,str(rooftop)]
	if key == _view_key: return
	var began := STALL_WORK.begin()
	_apply_floor_view(key, floor_index, storey_height, rooftop)
	STALL_WORK.finish("building.access.floor_view", began, {"place":str(definition.get("id","")), "floor":floor_index})

func _apply_floor_view(key: String, floor_index: int, storey_height: float, rooftop: bool) -> void:
	_view_key = key
	_view_floor = floor_index
	_view_storey = storey_height
	_view_rooftop = rooftop
	set_process(floor_index>=0 and not rooftop)
	for item in _labels:
		if is_instance_valid(item.node): item.node.visible = item.visible and (rooftop or floor_index<0)
	for item in _effects:
		if is_instance_valid(item.node): item.node.visible = item.visible and (rooftop or floor_index<0)
	var cuts: Array[AABB] = [_door_cut()]
	if floor_index >= 0 and not rooftop:
		# Paredes viradas para a câmera e volumes superiores são cortados juntos, e os
		# colisores inteiros ficam. O andar ativo fornece o acabamento da parede interna.
		var size: Vector2 = definition.size
		var front_margin := float(definition.get("facade_cut_front",1.2))
		cuts.append(AABB(Vector3(-size.x*.5-1.2,floor_index*storey_height+.78,-size.y*.5-1.2),Vector3(size.x+2.4,500,size.y+1.2+front_margin)))
	for item in _meshes:
		if not is_instance_valid(item.node): continue
		if not item.has("views"): item.views = {}
		if not item.views.has(key):
			if rooftop or floor_index<0: item.views[key] = item.open_mesh
			elif item.get("hide_inside",false): item.views[key] = null
			elif item.get("owned_architecture",false):
				# Todas as alas e projeções deste prédio dividem o corte.
				# Um lote jogável estreito não pode deixar a própria ala da frente,
				# o vidro da porta ou o toldo projetados sobre o cômodo.
				var bounds: AABB = item.transform*item.original.get_aabb()
				var owned_cut := AABB(Vector3(bounds.position.x-1.0,floor_index*storey_height+.78,bounds.position.z-1.0),Vector3(bounds.size.x+2.0,500,bounds.size.z+2.0))
				# Coroas recuadas podem ficar dentro da área jogável: remove a
				# mesma cavidade do colisor delas, incluindo os 78cm de baixo.
				item.views[key] = _cut_mesh(item.original,item.transform,[_door_cut(),_interior_cut(),owned_cut])
			else: item.views[key] = _cut_mesh(item.original,item.transform,cuts)
		var result: Mesh = item.views[key]
		item.node.mesh = result
		item.node.visible = item.visible and result != null
	if _door_visual != null: _door_visual.visible = floor_index < 1 and not rooftop

func _process(delta: float) -> void:
	_scan_clock -= delta
	if _scan_clock>0 or not _open: return
	_scan_clock = .5
	var began := STALL_WORK.begin()
	# O mobiliário da cidade é agendado depois do registro do prédio. Captura só nós
	# de apresentação recém-montados para detalhes tardios de telhado não flutuarem dentro.
	var known := {}
	for item in _meshes:
		if is_instance_valid(item.node): known[item.node.get_instance_id()] = true
	var changed := false
	for node in _presentation_nodes("MeshInstance3D"):
		var node_id: int = node.get_instance_id()
		if known.has(node_id) or _rejected_meshes.get(node_id) == node.mesh: continue
		if is_ancestor_of(node) or node.mesh==null or node.skin!=null or node.is_queued_for_deletion(): continue
		var relative: Transform3D = global_transform.affine_inverse()*node.global_transform
		var owned: bool = _owns_architecture(node) or _belongs_to_native_roof(relative*node.mesh.get_aabb())
		var canopy: bool = _is_venue_canopy(node)
		if not _relevant_visual(relative*node.mesh.get_aabb(),owned or canopy):
			_rejected_meshes[node_id] = node.mesh
			continue
		_meshes.append({"node":node,"original":node.mesh,"open_mesh":_cut_mesh(node.mesh,relative,[_door_cut()]),"transform":relative,"visible":node.visible,"owned_architecture":owned,"hide_inside":canopy})
		changed = true
	var known_labels := {}
	for item in _labels:
		if is_instance_valid(item.node): known_labels[item.node.get_instance_id()] = true
	for label in _presentation_nodes("Label3D"):
		if not known_labels.has(label.get_instance_id()) and (_owns_architecture(label) or _access_bounds().has_point(to_local(label.global_position))):
			_labels.append({"node":label,"visible":label.visible})
			changed = true
	if _capture_effects(): changed = true
	var batch_count := _multimeshes.size()
	_prepare_multimeshes()
	if _multimeshes.size()!=batch_count:
		for item in _multimeshes: item.node.multimesh = item.opened
		changed = true
	if changed:
		_add_roof_prop_solids()
		_view_key = ""
		set_floor_view(_view_floor,_view_storey,_view_rooftop)
	STALL_WORK.finish_slow("building.access.rescan", began, 2000, self)

func _door_cut() -> AABB:
	var half_depth: float = definition.size.y*.5
	# Inclui o nicho rebaixado original de .85m da loja e também a soleira.
	# Senão a parede rasa do fundo continua visível pela soleira aberta.
	var inward := 1.2
	if str(definition.building_kind)=="urban_slab":
		# This model's residential wall sits behind its .14-depth balcony bay.
		inward = maxf(inward,float(definition.size.y)*.14+.6)
	return AABB(Vector3(float(definition.entrance_local.x)-1.10,-.16,half_depth-inward),Vector3(2.20,2.90,3.6+inward))

func _interior_cut() -> AABB:
	var size: Vector2 = definition.size
	var ceiling: float = float(definition.storey_height)*int(definition.floor_count)-.12
	return AABB(Vector3(-size.x*.5+.22,-.16,-size.y*.5+.22),Vector3(size.x-.44,ceiling+.14,size.y-.44))

## Começa a preparação fatiada (HarborBuildingRuntime a 8 m da porta). Nada fica visível
## antes do fim: o corte só é aplicado por set_open_amount, que espera is_access_prepared()
## ou, se vier antes, termina a preparação síncrona como sempre foi.
func begin_prepare_access(budget_usec: int = PREP_SLICE_USEC) -> void:
	if _prepared or _prep_running: return
	if not is_inside_tree() or facade == null:
		_prepare_access()
		return
	_prep_ticket += 1
	_prep_running = true
	_run_prepare(_prep_ticket, maxi(1, budget_usec))

func is_access_prepared() -> bool:
	return _prepared

func is_access_preparing() -> bool:
	return _prep_running and not _prepared

func _prepare_access() -> void:
	if _prepared: return
	# Caminho síncrono (teste, restauração de save ou set_open_amount antes de a fatiada
	# terminar): invalida a fatiada em curso e faz tudo neste quadro, como antes.
	_prep_ticket += 1
	_prep_running = false
	var began := STALL_WORK.begin()
	_run_prepare(_prep_ticket, 0)
	STALL_WORK.finish("building.access.prepare", began, {"place":str(definition.get("id",""))})

## Mesma preparação nos dois modos. budget_usec 0 = síncrono (nunca cede o quadro, recorta
## no próprio thread); > 0 = cede a cada budget_usec e recorta no WorkerThreadPool. Tudo é
## montado em `state` e só publicado em _prep_commit, para a síncrona poder tomar o lugar.
func _run_prepare(ticket: int, budget_usec: int) -> bool:
	_sync_transform()
	var sliced := budget_usec > 0
	if not sliced: _prepared = true
	var body := StaticBody3D.new()
	body.name = "OpenedFacadeSolids"
	body.collision_layer = 0
	body.collision_mask = 0
	var state := {"ticket":ticket, "budget":budget_usec, "tree":get_tree() if sliced else null,
		"slice_began":Time.get_ticks_usec(), "span":STALL_WORK.begin(), "slices":1, "max_slice_usec":0,
		"started_frame":Engine.get_process_frames(), "labels":[], "effects":[], "meshes":[],
		"multimeshes":[], "scanned":{}, "shapes":[], "body":body, "details":[], "jobs":[]}
	var cuts: Array[AABB] = [_interior_cut(),_door_cut()]
	for label in _presentation_nodes("Label3D"):
		if _owns_architecture(label) or _access_bounds().has_point(to_local(label.global_position)):
			state.labels.append({"node":label,"visible":label.visible})
	if not await _prep_slice(state, "labels"): return _prep_discard(state)
	_capture_effects_into(state.effects)
	if not await _prep_slice(state, "effects"): return _prep_discard(state)
	# Snapshot antes de criar malhas e colisões pertencentes ao adaptador.
	var mesh_nodes := _presentation_nodes("MeshInstance3D")
	if not await _prep_slice(state, "mesh_scan"): return _prep_discard(state)
	for node in mesh_nodes:
		if not is_instance_valid(node) or node.mesh == null or node.skin != null or node.is_queued_for_deletion(): continue
		var relative: Transform3D = global_transform.affine_inverse()*node.global_transform
		var original: Mesh = node.mesh
		var owned: bool = _owns_architecture(node) or _belongs_to_native_roof(relative*original.get_aabb())
		var canopy: bool = _is_venue_canopy(node)
		if not _relevant_visual(relative*original.get_aabb(),owned or canopy): continue
		var record := {"node":node,"original":original,"open_mesh":original,"transform":relative,"visible":node.visible,"owned_architecture":owned,"hide_inside":canopy}
		# Fachada pintada já tem o vão aberto no lugar da porta desenhada; o corte
		# de 2,1 m abria um buraco largo no meio das janelas pintadas.
		if not _painted_part(node): _open_cut_into(state, record, original, relative)
		state.meshes.append(record)
		if not await _prep_slice(state, "meshes"): return _prep_discard(state)
	if not await _scan_multimesh_batches(state): return _prep_discard(state)
	for node in facade.find_children("*","CollisionShape3D",true,false):
		if node.shape == null or node.is_queued_for_deletion(): continue
		# A folha pintada da entrada tem colisão própria que gira com ela. Área de
		# detecção não é sólido: desligá-la junto com as paredes deixava a porta
		# pintada sem abrir para sempre depois que a sala era preparada (a 8 m).
		if node.get_parent().has_meta("painted_door_leaf") or node.get_parent() is Area3D: continue
		var relative: Transform3D = global_transform.affine_inverse()*node.global_transform
		if node.shape is BoxShape3D and not _access_bounds().intersects(relative*AABB(-node.shape.size*.5,node.shape.size)): continue
		state.shapes.append({"node":node,"disabled":node.disabled})
		if node.disabled: continue
		if node.shape is BoxShape3D:
			var source: AABB = relative*AABB(-node.shape.size*.5,node.shape.size)
			var pieces: Array[AABB] = [source]
			for cut in cuts:
				var next: Array[AABB] = []
				for piece in pieces: next.append_array(_subtract_box(piece,cut))
				pieces = next
			for piece in pieces: _add_box_shape_to(body, piece)
		elif node.shape is ConcavePolygonShape3D:
			var job := {"kind":"faces", "faces":node.shape.get_faces(), "relative":relative, "cuts":cuts}
			if sliced: state.jobs.append(job)
			else:
				_run_job(job)
				_add_faces_collider(body, job)
		else:
			# Non-box authored details retain their exact physical shape.
			var collider := CollisionShape3D.new()
			collider.shape = node.shape
			collider.transform = relative
			body.add_child(collider)
		if not await _prep_slice(state, "shapes"): return _prep_discard(state)
	if not state.jobs.is_empty():
		# Recorte de triângulos fora do thread principal; ele só espera o grupo terminar
		# (sem wait_for_* antes de is_group_task_completed, regra do HOW-TO-DEVELOP).
		var jobs: Array = state.jobs
		var group := WorkerThreadPool.add_group_task(Callable(get_script(), "_run_job_at").bind(jobs), jobs.size(), -1, false, "Corte da fachada do prédio")
		while not WorkerThreadPool.is_group_task_completed(group):
			await _prep_yield(state, "worker")
		WorkerThreadPool.wait_for_group_task_completion(group)
		if not _prep_alive(state): return _prep_discard(state)
		for job in jobs:
			if job.kind == "faces": _add_faces_collider(body, job)
			else: job.record[job.field] = _mesh_from_job(job)
			if not await _prep_slice(state, "commit_cut"): return _prep_discard(state)
	_prep_commit(state)
	return true

## Corte da porta para a versão aberta de uma malha: na hora (síncrono) ou como tarefa.
func _open_cut_into(state: Dictionary, record: Dictionary, mesh: Mesh, relative: Transform3D) -> void:
	var plan := _plan_cut(mesh, relative, [_door_cut()])
	if not plan.has("job"):
		record.open_mesh = plan.mesh
		return
	var job: Dictionary = plan.job
	if int(state.budget) <= 0:
		_run_job(job)
		record.open_mesh = _mesh_from_job(job)
		return
	job.record = record
	job.field = "open_mesh"
	state.jobs.append(job)

func _prep_alive(state: Dictionary) -> bool:
	return int(state.ticket) == _prep_ticket and is_inside_tree()

## Fecha a fatia quando passou do orçamento e espera o próximo quadro. Devolve false se a
## preparação deixou de valer (síncrona tomou o lugar ou o prédio saiu da árvore).
func _prep_slice(state: Dictionary, phase: String) -> bool:
	if int(state.budget) <= 0: return true
	if Time.get_ticks_usec() - int(state.slice_began) < int(state.budget): return true
	await _prep_yield(state, phase)
	return _prep_alive(state)

func _prep_yield(state: Dictionary, phase: String) -> void:
	_note_slice(state, phase)
	STALL_WORK.finish("building.access.prepare.slice", int(state.span), {"place":str(definition.get("id","")), "phase":phase})
	await (state.tree as SceneTree).process_frame
	state.slice_began = Time.get_ticks_usec()
	state.span = STALL_WORK.begin()
	state.slices = int(state.slices) + 1

func _note_slice(state: Dictionary, phase: String) -> void:
	var elapsed := Time.get_ticks_usec() - int(state.slice_began)
	if elapsed > int(state.max_slice_usec):
		state.max_slice_usec = elapsed
		state.max_phase = phase

func _prep_discard(state: Dictionary) -> bool:
	# Nada disto foi publicado: as peças derivadas estão ocultas e o corpo nem entrou na árvore.
	for node in state.details:
		if is_instance_valid(node): node.queue_free()
	if is_instance_valid(state.body): state.body.free()
	if int(state.ticket) == _prep_ticket: _prep_running = false
	if int(state.budget) > 0: STALL_WORK.finish("building.access.prepare.slice", int(state.span), {"place":str(definition.get("id","")), "phase":"discard"})
	return false

func _prep_commit(state: Dictionary) -> void:
	_prepared = true
	_prep_running = false
	_labels.append_array(state.labels)
	_effects.append_array(state.effects)
	_meshes.append_array(state.meshes)
	_multimeshes.append_array(state.multimeshes)
	_scanned_batches.merge(state.scanned, true)
	_original_shapes.append_array(state.shapes)
	_replacement_body = state.body
	_add_roof_prop_solids()
	add_child(_replacement_body)
	_make_open_door()
	if int(state.budget) > 0:
		_note_slice(state, "commit")
		STALL_WORK.finish("building.access.prepare.slice", int(state.span), {"place":str(definition.get("id","")), "phase":"commit"})
		last_prepare_stats = {"slices":state.slices, "max_slice_ms":float(state.max_slice_usec)/1000.0, "max_phase":str(state.get("max_phase","")),
			"frames":Engine.get_process_frames()-int(state.started_frame), "jobs":(state.jobs as Array).size(),
			"meshes":(state.meshes as Array).size(), "shapes":(state.shapes as Array).size()}

static func _add_faces_collider(body: StaticBody3D, job: Dictionary) -> void:
	var remaining: PackedVector3Array = job.get("remaining", PackedVector3Array())
	if remaining.is_empty(): return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(remaining)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

func _access_bounds() -> AABB:
	var size: Vector2 = definition.size
	return AABB(Vector3(-size.x*.5-1.2,-.5,-size.y*.5-1.2),Vector3(size.x+2.4,float(definition.roof_height)+12.0,size.y+4.8))

func _owns_architecture(node: Node) -> bool:
	# Alguns adaptadores de fachada são donos de um vilarejo/encontro inteiro em lote. Só
	# um prédio nativo único tem um limite arquitetônico sem ambiguidade.
	return facade is UrbanBuildingBase and (node==facade or facade.is_ancestor_of(node))

func _restaurant_venue() -> String:
	return RESTAURANT_VENUES.get(str(definition.get("source_id","")),"")

func _belongs_to_native_roof(bounds: AABB) -> bool:
	if not facade is UrbanBuildingBase or bounds.end.y<float(definition.roof_height)-.30: return false
	# Acabamentos de telhado são irmãos no chunk. A ala leste de um prédio em L
	# se estende além da ala norte jogável, mas ainda é dona do mobiliário do telhado.
	# Associa pela área original do prédio, nunca pela margem da calçada.
	var native := facade as UrbanBuildingBase
	var center := native.to_local(to_global(bounds.get_center()))
	return absf(center.x)<=native.building_size.x*.5+.08 and absf(center.z)<=native.building_size.y*.5+.08

func _is_attached_fire_escape(batch: Node, bounds: AABB) -> bool:
	if not str(batch.name).begins_with("CityLook_fe_"): return false
	var size: Vector2 = definition.size
	# Estes lotes misturam vários prédios; associa só as plataformas e
	# escadas na frente desta fachada, nunca o mobiliário de rua de outro lote.
	return absf(bounds.get_center().x)<size.x*.5+.15 and bounds.end.z>size.y*.5-.2 and bounds.position.z<size.y*.5+1.9 and bounds.position.z>size.y*.5-.4

func _is_venue_canopy(node: Node) -> bool:
	var venue := _restaurant_venue()
	if venue.is_empty(): return false
	var overhead := false
	var ancestor := node
	while ancestor!=null:
		if str(ancestor.name) in ["Parasol","ParasolPole"]: overhead=true
		if ancestor.has_meta("venue_id"): return overhead and str(ancestor.get_meta("venue_id"))==venue
		ancestor = ancestor.get_parent()
	return false

func _relevant_visual(bounds: AABB, owned := false) -> bool:
	if owned: return true
	if not _access_bounds().intersects(bounds): return false
	# O Torque põe a fachada em lote junto com materiais iguais em outros pontos
	# do lote. Captura esse lote, mas recorta só a fachada de loja limitada.
	if str(definition.get("source_id","")) == "TorqueStore": return true
	var center := bounds.get_center()
	# O mobiliário de rua fica ao lado do cômodo e precisa continuar completo. Acessórios
	# elevados (ar-condicionado de janela, canos, neon) ainda participam do corte do andar.
	if bounds.position.y<.35 and (absf(center.x)>definition.size.x*.5+.12 or absf(center.z)>definition.size.y*.5+.12): return false
	return true

func _presentation_nodes(type: String) -> Array[Node]:
	# O mobiliário de chunk pertence aos chunks em streaming, ao lado (não abaixo) do
	# prédio. Restringe a busca extra a essas raízes de apresentação conhecidas;
	# ruas, arquitetura de prédios vizinhos e corpos de gameplay continuam com seus donos.
	var result: Array[Node] = []
	var roots: Array[Node] = [facade]
	var chunk := facade.get_parent()
	if chunk != null:
		for sibling in chunk.get_children():
			var label := str(sibling.name)
			if label.begins_with("CityLook_") or label.begins_with("RoofNeon_") or label.begins_with("Billboard_") or label.begins_with("RoofSteam"):
				roots.append(sibling)
	var venue := _restaurant_venue()
	if not venue.is_empty():
		for terrace in get_tree().get_nodes_in_group("harbor_restaurant_terrace"):
			if str(terrace.get_meta("venue_id",""))!=venue: continue
			for component in ["Parasol","ParasolPole"]:
				var overhead: Node = terrace.get_node_or_null(component)
				if overhead!=null: roots.append(overhead)
	for root_owner in roots:
		if root_owner.is_class(type): result.append(root_owner)
		result.append_array(root_owner.find_children("*",type,true,false))
	return result

func _capture_effects() -> bool:
	return _capture_effects_into(_effects)

func _capture_effects_into(target: Array) -> bool:
	var changed := false
	for type in ["CPUParticles3D","GPUParticles3D"]:
		for node in _presentation_nodes(type):
			if not _owns_architecture(node) and not _access_bounds().has_point(to_local(node.global_position)): continue
			var known := false
			for item in target:
				if item.node==node: known=true; break
			if known: continue
			target.append({"node":node,"visible":node.visible})
			changed = true
	return changed

func _prepare_multimeshes() -> void:
	# Varredura síncrona (0,5 s com o jogador dentro): grava direto nas listas publicadas.
	_scan_multimesh_batches({"budget":0, "multimeshes":_multimeshes, "meshes":_meshes, "scanned":_scanned_batches, "details":[], "jobs":[]})

## Lotes MultiMesh da parcela. Com orçamento, cede o quadro entre instâncias e deixa o corte
## da porta como tarefa; devolve false se a preparação fatiada deixou de valer.
func _scan_multimesh_batches(state: Dictionary) -> bool:
	# Os donos do vilarejo/encontro põem o sítio inteiro em lote. Divide só as instâncias
	# deste lote, deixando vizinhos, atores e materiais no lote.
	var batches := _presentation_nodes("MultiMeshInstance3D")
	if not await _prep_slice(state, "multimesh_scan"): return false
	for batch in batches:
		if not is_instance_valid(batch) or batch.multimesh == null or batch.multimesh.mesh == null: continue
		var captured := false
		for item in state.multimeshes:
			if item.node == batch: captured = true; break
		if captured: continue
		var source: MultiMesh = batch.multimesh
		# Mesmo recurso já varrido sem nada nesta parcela: não repete o laço por instância.
		var batch_id: int = batch.get_instance_id()
		if state.scanned.get(batch_id) == source: continue
		state.scanned[batch_id] = source
		var owned: bool = _owns_architecture(batch)
		var opened: MultiMesh = null
		var frame: Transform3D = global_transform.affine_inverse()*batch.global_transform
		var first_record: int = state.meshes.size()
		var first_detail: int = state.details.size()
		for index in source.instance_count:
			if not await _prep_slice(state, "multimesh"): return false
			# O lote pode ter sido trocado ou apagado enquanto o quadro foi cedido: as peças
			# já tiradas dele apareceriam em dobro (o lote não esconderia as instâncias).
			if not is_instance_valid(batch) or batch.multimesh != source:
				for detail_index in range(first_detail, state.details.size()): state.details[detail_index].queue_free()
				state.details.resize(first_detail)
				state.meshes.resize(first_record)
				opened = null
				break
			var relative: Transform3D = frame*source.get_instance_transform(index)
			var bounds: AABB = relative*source.mesh.get_aabb()
			var attachment: bool = _is_attached_fire_escape(batch,bounds) or _belongs_to_native_roof(bounds)
			if not _relevant_visual(bounds,owned or attachment): continue
			if opened == null: opened = _copy_multimesh(source)
			var hidden: Transform3D = source.get_instance_transform(index)
			hidden.basis = Basis.from_scale(Vector3.ZERO)
			opened.set_instance_transform(index,hidden)
			var single := MeshInstance3D.new()
			single.name = "ParcelDetail%d"%index
			single.mesh = source.mesh
			single.material_override = preload("res://scripts/camera/ExteriorReveal.gd").source_material(batch.material_override)
			single.cast_shadow = batch.cast_shadow
			single.layers = batch.layers
			single.transform = relative
			single.visible = false
			add_child(single)
			state.details.append(single)
			var record := {"node":single,"original":source.mesh,"open_mesh":source.mesh,"transform":relative,"visible":batch.visible,"derived":true,"owned_architecture":owned or attachment}
			_open_cut_into(state, record, source.mesh, relative)
			state.meshes.append(record)
		if opened != null and is_instance_valid(batch) and batch.multimesh == source: state.multimeshes.append({"node":batch,"original":source,"opened":opened})
	return true

static func _copy_multimesh(source: MultiMesh) -> MultiMesh:
	# Resource.duplicate pode reproduzir o buffer antes de instance_count no Godot
	# 4.7.2. Aloca primeiro o layout de destino e depois copia cada instância.
	var copy := MultiMesh.new()
	copy.transform_format = source.transform_format
	copy.use_colors = source.use_colors
	copy.use_custom_data = source.use_custom_data
	copy.mesh = source.mesh
	copy.instance_count = source.instance_count
	copy.visible_instance_count = source.visible_instance_count
	copy.custom_aabb = source.custom_aabb
	for index in source.instance_count:
		copy.set_instance_transform(index,source.get_instance_transform(index))
		if source.use_colors: copy.set_instance_color(index,source.get_instance_color(index))
		if source.use_custom_data: copy.set_instance_custom_data(index,source.get_instance_custom_data(index))
	return copy

func _add_roof_prop_solids() -> void:
	for item in _meshes:
		var key: int = item.node.get_instance_id()
		if _roof_prop_ids.has(key): continue
		_roof_prop_ids[key] = true
		var bounds: AABB = item.transform*item.original.get_aabb()
		var roof_y: float = definition.roof_height
		if bounds.position.y < roof_y-.35 or bounds.end.y < roof_y+.12 or bounds.size.y < .12: continue
		if bounds.size.x < .12 or bounds.size.z < .12: continue
		# Só objetos físicos de telhado; planos de telhado inclinado são pisos/paisagem de telhados.
		if bounds.size.x > definition.size.x*.75 or bounds.size.z > definition.size.y*.75: continue
		bounds.size.y = bounds.end.y-roof_y
		bounds.position.y = roof_y
		_add_box_shape(bounds)

func _add_box_shape(bounds: AABB) -> void:
	_add_box_shape_to(_replacement_body, bounds)

static func _add_box_shape_to(body: StaticBody3D, bounds: AABB) -> void:
	if minf(bounds.size.x,minf(bounds.size.y,bounds.size.z)) < .003: return
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = bounds.get_center()
	body.add_child(node)

func _hold_painted_doors(open: bool) -> void:
	if facade == null: return
	for anchor in facade.find_children("Doorway_front*","Node3D",true,false):
		if anchor.has_meta("walk_in") and anchor.has_node("Door"): anchor.get_node("Door").hold(open)

## Peça de PaintedFacadeKit (paredes/telhado pintados, porta própria que abre devagar).
static func _painted_part(node: Node) -> bool:
	var current := node
	while current != null:
		if String(current.name).begins_with("PaintedFacade_"): return true
		current = current.get_parent()
	return false

func _make_open_door() -> void:
	# Sobrado pintado: a folha pintada do kit é a porta de verdade, abre devagar e só
	# ao alcance do braço; a folha de metal fixa aparecia aberta a 8 m de distância.
	if not facade.find_children("PaintedFacade_*","",true,false).is_empty(): return
	_door_visual = Node3D.new()
	_door_visual.name = "OpenDoorLeaf"
	var leaf := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.07,2.45,.95)
	leaf.mesh = mesh
	leaf.position = Vector3(float(definition.entrance_local.x)-1.045,1.225,definition.size.y*.5+.50)
	leaf.material_override = preload("res://world/places/ShopInteriorMaterials.gd").material("metal",Color("485451"))
	_door_visual.add_child(leaf)
	add_child(_door_visual)
	_door_visual.hide()
	_add_box_shape(AABB(leaf.position-mesh.size*.5,mesh.size))

static func _subtract_box(source: AABB, cut: AABB) -> Array[AABB]:
	var result: Array[AABB] = []
	if not source.intersects(cut): return [source]
	var common := source.intersection(cut)
	var lo := source.position
	var hi := source.end
	var a := common.position
	var b := common.end
	for pair in [
		[lo,Vector3(a.x,hi.y,hi.z)], [Vector3(b.x,lo.y,lo.z),hi],
		[Vector3(a.x,lo.y,lo.z),Vector3(b.x,a.y,hi.z)], [Vector3(a.x,b.y,lo.z),Vector3(b.x,hi.y,hi.z)],
		[Vector3(a.x,a.y,lo.z),Vector3(b.x,b.y,a.z)], [Vector3(a.x,a.y,b.z),Vector3(b.x,b.y,hi.z)],
	]:
		var size: Vector3 = pair[1]-pair[0]
		if minf(size.x,minf(size.y,size.z)) > .0001: result.append(AABB(pair[0],size))
	return result

static func _cut_mesh(source: Mesh, relative: Transform3D, cuts: Array[AABB]) -> Mesh:
	var plan := _plan_cut(source, relative, cuts)
	if not plan.has("job"): return plan.mesh
	_run_job(plan.job)
	return _mesh_from_job(plan.job)

## Parte do thread principal antes do corte: resposta imediata (malha inteira, nada ou a
## original) ou uma tarefa com as arrays de cada superfície. As arrays vêm do MeshArrayCache
## (surface_get_arrays lia a GPU e esperava os quadros em voo; HOW-TO-DEVELOP §3.2).
static func _plan_cut(source: Mesh, relative: Transform3D, cuts: Array[AABB]) -> Dictionary:
	var bounds := relative*source.get_aabb()
	var touches := false
	for cut in cuts:
		if cut.encloses(bounds): return {"mesh":null}
		if bounds.intersects(cut): touches = true
	if not touches: return {"mesh":source}
	var surfaces: Array = []
	for surface_index in source.get_surface_count():
		surfaces.append({"arrays":_surface_arrays(source, surface_index), "material":source.surface_get_material(surface_index)})
	return {"job":{"kind":"mesh", "surfaces":surfaces, "relative":relative, "cuts":cuts}}

static func _surface_arrays(source: Mesh, surface: int) -> Array:
	# get_meta com padrão null reclama da chave ausente: pergunta antes.
	var kept: Variant = source.get_meta(CPU_ARRAYS_META) if source.has_meta(CPU_ARRAYS_META) else null
	if kept is Array and surface < (kept as Array).size(): return kept[surface]
	return MESH_ARRAYS.arrays_of(source, surface)

static func _run_job_at(index: int, jobs: Array) -> void:
	_run_job(jobs[index])

## Cálculo puro (pode rodar no WorkerThreadPool): não toca nó, árvore nem RenderingServer.
## SurfaceTool só monta arrays na CPU; o ArrayMesh é criado depois, no thread principal.
static func _run_job(job: Dictionary) -> void:
	var relative: Transform3D = job.relative
	var cuts: Array[AABB] = job.cuts
	if job.kind == "faces":
		var faces: PackedVector3Array = job.faces
		var remaining := PackedVector3Array()
		for index in range(0,faces.size(),3):
			var polygon: Array = [relative*faces[index],relative*faces[index+1],relative*faces[index+2]]
			var polygons: Array = [polygon]
			for cut in cuts: polygons = _subtract_polygons(polygons,cut)
			for piece in polygons:
				for corner in range(1,piece.size()-1): remaining.append_array(PackedVector3Array([piece[0],piece[corner],piece[corner+1]]))
		job.remaining = remaining
		return
	var inverse := relative.affine_inverse()
	var results: Array = []
	for surface in job.surfaces:
		var arrays: Array = surface.arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var texcoords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var emitted := 0
		for index in range(0,count,3):
			var original_points: Array[Vector3] = []
			var uv_points: Array[Vector2] = []
			var color_points: Array[Color] = []
			for corner in 3:
				var vertex_index := indices[index+corner] if not indices.is_empty() else index+corner
				original_points.append(relative*vertices[vertex_index])
				uv_points.append(texcoords[vertex_index] if vertex_index < texcoords.size() else Vector2.ZERO)
				if not colors.is_empty(): color_points.append(colors[vertex_index])
			var polygons: Array = [original_points]
			for cut in cuts: polygons = _subtract_polygons(polygons,cut)
			for polygon in polygons:
				for corner in range(1,polygon.size()-1):
					for point: Vector3 in [polygon[0],polygon[corner],polygon[corner+1]]:
						tool.set_uv(_triangle_uv(point,original_points,uv_points))
						if not color_points.is_empty():
							var weights := _triangle_weights(point,original_points)
							tool.set_color(color_points[0]*weights.x+color_points[1]*weights.y+color_points[2]*weights.z)
						tool.add_vertex(inverse*point)
						emitted += 1
		if emitted > 0:
			tool.generate_normals()
			# Equivale a tool.commit(output): commit_to_arrays + add_surface_from_arrays + material.
			results.append({"arrays":tool.commit_to_arrays(), "material":surface.material})
	job.results = results

static func _mesh_from_job(job: Dictionary) -> Mesh:
	var output := ArrayMesh.new()
	for result in job.get("results", []):
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result.arrays)
		if result.material != null: output.surface_set_material(output.get_surface_count()-1, result.material)
	return output if output.get_surface_count()>0 else null

static func _triangle_uv(point: Vector3, vertices: Array[Vector3], uv: Array[Vector2]) -> Vector2:
	var weights := _triangle_weights(point,vertices)
	return uv[0]*weights.x+uv[1]*weights.y+uv[2]*weights.z

static func _triangle_weights(point: Vector3, vertices: Array[Vector3]) -> Vector3:
	var edge0 := vertices[1]-vertices[0]
	var edge1 := vertices[2]-vertices[0]
	var delta := point-vertices[0]
	var aa := edge0.dot(edge0)
	var ab := edge0.dot(edge1)
	var bb := edge1.dot(edge1)
	var det := aa*bb-ab*ab
	if absf(det)<.000001: return Vector3(1,0,0)
	var v := (bb*delta.dot(edge0)-ab*delta.dot(edge1))/det
	var w := (aa*delta.dot(edge1)-ab*delta.dot(edge0))/det
	return Vector3(1.0-v-w,v,w)

static func _subtract_polygons(polygons: Array, cut: AABB) -> Array:
	var result: Array = []
	for polygon in polygons:
		var inside: Array = polygon
		for plane in [Vector4(1,0,0,cut.position.x),Vector4(-1,0,0,-cut.end.x),Vector4(0,1,0,cut.position.y),Vector4(0,-1,0,-cut.end.y),Vector4(0,0,1,cut.position.z),Vector4(0,0,-1,-cut.end.z)]:
			if inside.size()<3: break
			var outside := _clip_polygon(inside,plane,false)
			if outside.size()>=3: result.append(outside)
			inside = _clip_polygon(inside,plane,true)
	return result

static func _clip_polygon(polygon: Array, plane: Vector4, positive: bool) -> Array:
	var result: Array = []
	if polygon.is_empty(): return result
	var normal := Vector3(plane.x,plane.y,plane.z)
	var last: Vector3 = polygon[-1]
	var last_distance := normal.dot(last)-plane.w
	var last_inside := last_distance>=0 if positive else last_distance<0
	for point: Vector3 in polygon:
		var distance := normal.dot(point)-plane.w
		var current_inside := distance>=0 if positive else distance<0
		if current_inside != last_inside:
			result.append(last.lerp(point,last_distance/(last_distance-distance)))
		if current_inside: result.append(point)
		last = point
		last_distance = distance
		last_inside = current_inside
	return result
