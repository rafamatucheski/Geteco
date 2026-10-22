extends Node3D
## Independent streamed region. Coordinates never pass through Harbor's legacy pixel adapter.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const COMPACT := preload("res://world/desert/DesertCompactLayout.gd")
const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
const UNDERGROUND := preload("res://world/desert/underground/DesertUnderground.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
const ART := preload("res://world/desert/DesertArchitecture.gd")
const UTILITY := preload("res://world/desert/DesertUtilityLines.gd")
const DETAIL := preload("res://world/desert/DesertSurfaceDetail.gd")
const ROCKS := preload("res://world/desert/DesertSurfaceRocks.gd")
const RELIEF := preload("res://world/desert/DesertTerrainRelief.gd")
const TERRAIN_MESH := preload("res://world/desert/DesertTerrainMesh.gd")
const ROCK_FORMS := preload("res://world/desert/DesertHorizonRelief.gd")
const CANYON_DRESSING := preload("res://world/desert/DesertCanyonDressing.gd")
const ABANDONED := preload("res://world/desert/DesertAbandonedSite.gd")
const BANDIT_CAMP := preload("res://world/desert/DesertBanditCamp.gd")
const WILDLIFE := preload("res://world/desert/DesertWildlife.gd")
const DRY_FLORA := preload("res://world/desert/DesertDryFlora.gd")
const GROUND_COVER := preload("res://world/desert/DesertGroundCover.gd")
const EXPANSION := preload("res://world/desert/expansion/DesertExpansion.gd")
const MINING_LAYOUT := preload("res://world/mining/MiningLayout.gd")
const MINING_ART := preload("res://world/mining/MiningExterior.gd")
const MOON_VILLAGE := preload("res://world/desert/DesertMoonVillage.gd")
const VILLAGE_HOMES := preload("res://world/desert/village/DesertVillageHomes.gd")
const DRAG_MEET := preload("res://world/desert/drag_meet/DesertDragMeet.gd")
const DRAG_SUPPORT := preload("res://world/desert/DragTrackSupport.gd")
const SMUGGLER_LAYOUT := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const SMUGGLER_SCENERY := preload("res://world/desert/canyon/DesertSmugglerScenery.gd")
const CELL := 96.0
const BUILD_BUDGET_USEC := 1000
const SURFACE_STAGES := 18
const CHUNK_CACHE := preload("res://world/desert/DesertChunkCache.gd")
var region_id := "desert"
var initial_focus := Vector3.INF
var initial_prewarm_only := false
var prepared := false
var data_prepared := false
var north_pass_completed := false
var focus := Vector3.ZERO
var current_cell := Vector2i(100000,100000)
var retention_radius := 2
var _residency_dirty := false
var _lamp_cleanup_after_frame := -1
var _dressing_yield_frame := -1
var chunks: Dictionary = {}
var records: Dictionary = {}
var pending: Array[Vector2i] = []
var build_jobs: Array[Dictionary] = []
var _surface_jobs: Dictionary = {}
var _chunk_cache := CHUNK_CACHE.new()
var roads: Array[Dictionary] = []
var walkways: Array[Dictionary] = []
var buildings: Array[Dictionary] = []
var entries: Array[Dictionary] = []
var terrain: Node3D = null
var harbor_road_geometry: RefCounted = null
var vehicle_support_cells: Dictionary = {}
var developer_view_cells: Dictionary = {}
var _developer_bounds := Rect2()
# The side camera sees the entire course's north shoulder. Warm this bounded
# band on approach, then retain it through the return; ordinary city streaming
# stays unchanged. Preparation uses the existing one-cell/frame build budget.
const DRAG_VIEW_BOUNDS := Rect2(-1056 + COMPACT.DRAG.x,-1440 + COMPACT.DRAG.z,1248,192)
var drag_view_cells: Dictionary = {}
var drag_view_pending: Array[Vector2i] = []
var drag_track_support: StaticBody3D
var source_data: Dictionary = {}
var _night_level := 0.0
var _lamps: Array[OmniLight3D] = []
var _horizon: Node3D
var _presentation_lifetime: Dictionary={}
var drag_scenery: Node3D
var _drag_preparing := false
var road_geometry := preload("res://world/desert/DesertRoadGeometry.gd").new()
var ambient: Node3D
var wildlife: Node3D
var abandoned_site: Node3D
var canyon_site: Node3D
var expansion_life: Node3D
var mining_life: Node3D
var mining_dust: Node3D
var expansion_prewarm: Dictionary={}
var spawn_position: Vector3:
	get: return LAYOUT.BRIDGE_END+Vector3(0,.08,-6)

static func build_region(_id := "desert", first_focus := Vector3.INF) -> Node3D:
	var region = load("res://world/desert/DesertRegion.gd").new()
	region.initial_focus=first_focus
	return region

static func get_definition(_id := "desert") -> Dictionary:
	return {"id":"desert","source_id":"world/desert/DesertRegion.gd","unit_scale":1.0,"offset":Vector2.ZERO}

## Montar o deserto custou 9,4 s num quadro só ao começar perto da passagem norte (travessia do release de
## 15/10, "world.mount_region:desert"), sem nenhum span dentro. Cada etapa vai para o log da sessão.
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
func _ready() -> void:
	name="DesertNativeRegion"
	var began := STALL_WORK.begin()
	prepare_data()
	prepared=true
	STALL_WORK.finish_slow("desert.ready.prepare_data",began,2000)
	began = STALL_WORK.begin()
	if not is_instance_valid(_horizon): _horizon=preload("res://world/desert/DesertHorizon.gd").build()
	add_child(_horizon)
	drag_scenery=preload("res://world/desert/DragScenery.gd").new()
	_horizon.add_child(drag_scenery)
	drag_scenery.configure(self)
	STALL_WORK.finish_slow("desert.ready.horizon",began,2000)
	began = STALL_WORK.begin()
	ambient=preload("res://world/desert/DesertAmbientLife.gd").new()
	add_child(ambient)
	wildlife=WILDLIFE.new()
	add_child(wildlife)
	wildlife.configure(_ground_height,6102026)
	STALL_WORK.finish_slow("desert.ready.ambient_wildlife",began,2000)
	began = STALL_WORK.begin()
	expansion_life=EXPANSION.create_life(self,_ground_height,_decoration_clear)
	STALL_WORK.finish_slow("desert.ready.expansion_life",began,2000)
	began = STALL_WORK.begin()
	if MINING_LAYOUT.enabled():
		mining_life=preload("res://world/mining/MiningLife.gd").new()
		add_child(mining_life)
		mining_life.configure(self)
		mining_dust=preload("res://world/mining/MiningDust.gd").new()
		add_child(mining_dust)
		mining_dust.configure(_ground_height)
	STALL_WORK.finish_slow("desert.ready.mining",began,2000)
	began = STALL_WORK.begin()
	if not initial_prewarm_only: set_focus(initial_focus if initial_focus.is_finite() else spawn_position)
	STALL_WORK.finish_slow("desert.ready.set_focus",began,2000)

## Called while detached, under the loading curtain. The identical visual
## terrain is generated in slices and _ready reuses the completed hierarchy.
func prepare_presentation_incremental(tree: SceneTree, lifetime: Node = null) -> void:
	if is_instance_valid(_horizon): return
	var token := {"cancelled":false,"roots":[]}
	_presentation_lifetime=token
	var cancel := func() -> void: preload("res://world/desert/DesertPreparationLifetime.gd").cancel(token)
	if is_instance_valid(lifetime): lifetime.tree_exiting.connect(cancel,CONNECT_ONE_SHOT)
	var completed: Node3D=await preload("res://world/desert/DesertHorizon.gd").build_sliced(tree,token)
	if is_instance_valid(lifetime) and lifetime.tree_exiting.is_connected(cancel): lifetime.tree_exiting.disconnect(cancel)
	if not is_instance_valid(self) or bool(token.cancelled):
		if is_instance_valid(completed): completed.free()
		return
	_horizon=completed

func prepare_data() -> void:
	if data_prepared: return
	roads=LAYOUT.roads()
	roads.append_array(preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").roads())
	road_geometry.configure(roads)
	# Private gravel geometry is authored by MiningExterior; route consumers and
	# map still receive its same centre-line, excluded from ambient traffic.
	roads=roads+MINING_LAYOUT.roads()
	if MINING_LAYOUT.enabled():
		var mine_definition:=preload("res://world/mining/coal/CoalMinePlace.gd").definition_data()
		entries.append({"id":mine_definition.id,"place_id":mine_definition.id,"position":mine_definition.entry_position,"return_position":mine_definition.return_position,"label":mine_definition.original_name})
	for record in UTILITY.records(): _record(record.position,record)
	for record in MOON_VILLAGE.records():
		_record(record.position,record)
		if record.data.kind in ["home","store"]:
			var village_size: Vector3=record.data.size
			var village_planar := Vector2(village_size.x,village_size.z)
			if absf(sin(float(record.data.yaw)))>.5: village_planar=Vector2(village_size.z,village_size.x)
			buildings.append({"id":record.data.id,"name":"Santa Lua" if record.data.kind=="store" else "","position":record.position,"size":village_planar,"height":village_size.y})
	for building in LAYOUT.buildings():
		# NativeRegion's public geography API uses a planar footprint; art keeps XYZ dimensions.
		var dimensions: Vector3=building.size
		var footprint: Dictionary=building.duplicate()
		footprint.size=Vector2(dimensions.x,dimensions.z)
		footprint.height=dimensions.y
		buildings.append(footprint)
		_record(building.position,{"kind":"building","data":building})
	for definition in LAYOUT.place_definitions():
		entries.append({"id":definition.id,"place_id":definition.id,"position":definition.entry_position,"return_position":definition.return_position,"label":definition.original_name})
	for definition in UNDERGROUND.definitions():
		entries.append({"id":definition.id,"place_id":definition.id,"position":definition.entry_position,"return_position":definition.return_position,"label":definition.original_name})
	for record in UNDERGROUND.records(): _record(record.position,record)
	for definition in VILLAGE_HOMES.definitions():
		entries.append({"id":definition.id,"place_id":definition.id,"position":definition.entry_position,"return_position":definition.return_position,"label":definition.original_name})
	_record(LAYOUT.TRUCK_STOP,{"kind":"truck_stop","position":LAYOUT.TRUCK_STOP})
	_record(preload("res://world/desert/entrance/DesertTollPlaza.gd").POSITION,{"kind":"entrance_toll"})
	_record(preload("res://world/desert/DesertCoachStop.gd").POSITION,{"kind":"coach_stop","position":preload("res://world/desert/DesertCoachStop.gd").POSITION})
	_record(ABANDONED.POSITION,{"kind":"abandoned_site","position":ABANDONED.POSITION})
	# Minerador da pista da Forja da Serra, ao lado do acesso da Mineração.
	_record(preload("res://world/desert/DesertMinerCamp.gd").CENTER,{"kind":"forge_miner_camp"})
	for i in 4:
		var point := LAYOUT.TRUCK_STOP+Vector3(-26-float(i)*6.4,0,3)
		_record(point,{"kind":"bitrem","position":point,"index":i})
	for x in range(-350,-100,36):
		var point := Vector3(x,0,-888) + COMPACT.TOWN
		_record(point,{"kind":"lamp","position":point})
	for x in range(-900,91,64):
		var point := Vector3(x,0,-1330) + COMPACT.DRAG
		_record(point,{"kind":"lamp","position":point})
	# The workshop pole stands outside both working bays; the eastern pole sits
	# between Jessica and her neighbouring visitors, clear of the access curve.
	for point in [Vector3(-1034,0,-1297),Vector3(-978,0,-1288),Vector3(-911,0,-1271),Vector3(-1013,0,-1252),Vector3(-951,0,-1240),Vector3(-917,0,-1220)]:
		_record(point + COMPACT.DRAG,{"kind":"lamp","position":point + COMPACT.DRAG})
	for record in DRAG_MEET.records(): _record(record.position,record)
	_record(Vector3(-390,0,-926) + COMPACT.TOWN,{"kind":"water_tower","position":Vector3(-390,0,-926) + COMPACT.TOWN})
	_record(Vector3(-315,0,-914.2) + COMPACT.TOWN,{"kind":"rest_bench","position":Vector3(-315,0,-914.2) + COMPACT.TOWN})
	_record(LAYOUT.drag_start_point(),{"kind":"drag_line","position":LAYOUT.drag_start_point(),"finish":false})
	var finish := LAYOUT.drag_start_point()+LAYOUT.drag_direction()*LAYOUT.DRAG_LENGTH
	_record(finish,{"kind":"drag_line","position":finish,"finish":true})
	data_prepared=true

func _record(point: Vector3, data: Dictionary) -> void:
	var key := _cell(point)
	if not records.has(key): records[key]=[]
	records[key].append(data)

func _cell(point: Vector3) -> Vector2i: return Vector2i(floori(point.x/CELL),floori(point.z/CELL))
func map_routes() -> Array[Dictionary]: return roads+walkways
func set_focus(point: Vector3, complete_focus_chunk := false) -> void:
	focus=point
	if not prepared: return
	_update_drag_residency(point)
	var cell := _cell(point)
	if cell==current_cell:
		if complete_focus_chunk: _complete_focus_chunk(cell)
		return
	current_cell=cell
	_residency_dirty=true
	pending.clear()
	for x in range(-1,2):
		for z in range(-1,2):
			var key := cell+Vector2i(x,z)
			if not chunks.has(key): pending.append(key)
	pending.sort_custom(func(a: Vector2i,b: Vector2i): return Vector2(a-cell).length_squared()<Vector2(b-cell).length_squared())
	pending.erase(cell)
	_ensure_chunk_surfaces(cell)
	if complete_focus_chunk: _complete_focus_chunk(cell)
	preload("res://world/regions/DeveloperViewCells.gd").enqueue(self)
	_trim_chunks()

func _complete_focus_chunk(key: Vector2i) -> void:
	# Match NativeRegion's startup contract: finish only the occupied cell;
	# neighbours retain the ordinary streaming budget.
	_ensure_chunk_surfaces(key)
	for job in build_jobs.duplicate():
		if job.key!=key: continue
		while job in build_jobs: _run_build_job(job,INF)

func set_vehicle_support(vehicles: Array) -> void:
	var next_cells: Dictionary={}
	for vehicle in vehicles:
		if not vehicle is Dictionary or not vehicle.get("position") is Vector3: continue
		var radius: float=maxf(float(vehicle.get("radius",2.0)),2.0)
		var point: Vector3=vehicle.position
		for x in range(floori((point.x-radius)/CELL),floori((point.x+radius)/CELL)+1):
			for z in range(floori((point.z-radius)/CELL),floori((point.z+radius)/CELL)+1):
				var key := Vector2i(x,z)
				next_cells[key]=true
	if next_cells != vehicle_support_cells:
		vehicle_support_cells=next_cells
		_residency_dirty=true
		for key in vehicle_support_cells:
			_ensure_chunk_surfaces(key)
	_trim_chunks()

func set_developer_view(view: Rect2, enabled: bool, full_map := false) -> void:
	if enabled and not _developer_bounds.has_area():
		_developer_bounds = preload("res://world/regions/DeveloperViewCells.gd").record_bounds(records, CELL)
	var next: Dictionary = preload("res://world/regions/DeveloperViewCells.gd").select_cells(LAYOUT.BOUNDS if full_map else view, LAYOUT.BOUNDS, CELL) if enabled else {}
	if next == developer_view_cells: return
	developer_view_cells = next
	# Remove obsolete overview requests while preserving physical support and ordinary neighbours.
	for index in range(pending.size()-1, -1, -1):
		var key: Vector2i = pending[index]
		if developer_view_cells.has(key) or vehicle_support_cells.has(key): continue
		if drag_view_cells.has(key): continue
		if absi(key.x-current_cell.x)>1 or absi(key.y-current_cell.y)>1: pending.remove_at(index)
	preload("res://world/regions/DeveloperViewCells.gd").enqueue(self)
	_residency_dirty = true
	_trim_chunks()

func set_retention_radius(value: int) -> void:
	var next_radius := clampi(value,1,2)
	if next_radius != retention_radius:
		retention_radius=next_radius
		_residency_dirty=true
	_trim_chunks()

func prepare_collision_at(point: Vector3) -> bool:
	if not LAYOUT.contains(point): return false
	var key := _cell(point)
	var had_chunk := chunks.has(key)
	_ensure_chunk_surfaces(key)
	if not had_chunk and chunks.has(key): _residency_dirty=true
	return chunks.has(key)

func _ensure_chunk_surfaces(key: Vector2i) -> void:
	if chunks.has(key): return
	var began := STALL_WORK.begin()
	_begin_surface_job(key)
	# Urgent physical support (player, vehicles and restore) must be complete
	# before admission. Finish any work already prepared by the neighbour queue.
	while _surface_jobs.has(key): _advance_surface_job(key)
	STALL_WORK.finish_slow("stream.desert.surfaces",began,2000)

func _begin_surface_job(key: Vector2i) -> void:
	if chunks.has(key) or _surface_jobs.has(key): return
	var rect := Rect2(Vector2(key)*CELL,Vector2.ONE*CELL).intersection(LAYOUT.BOUNDS)
	if not rect.has_area(): return
	var cached: Dictionary=_chunk_cache.take(key)
	if not cached.is_empty():
		_restore_cached_chunk(key,cached)
		return
	var chunk := Node3D.new()
	chunk.name="Desert_%d_%d"%[key.x,key.y]
	# Until every surface is ready, neighbours stay hidden and their physical
	# objects are removed from the physics space by the inherited disabled mode.
	chunk.visible=false
	chunk.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(chunk)
	_surface_jobs[key]={"chunk":chunk,"rect":rect,"stage":0}

func _advance_surface_job(key: Vector2i) -> void:
	if not _surface_jobs.has(key): return
	var job: Dictionary=_surface_jobs[key]
	var began := STALL_WORK.begin()
	_build_surface_stage(job.chunk,job.rect,int(job.stage))
	STALL_WORK.finish_slow("stream.desert.surface_stage.%d"%int(job.stage),began,2000)
	job.stage=int(job.stage)+1
	if int(job.stage)<SURFACE_STAGES: return
	var chunk: Node3D=job.chunk
	_surface_jobs.erase(key)
	chunks[key]=chunk
	chunk.visible=true
	chunk.process_mode=Node.PROCESS_MODE_INHERIT
	if chunk.has_meta("desert_canyon_site"): canyon_site=chunk.get_meta("desert_canyon_site")
	build_jobs.append({"key":key,"rect":job.rect,"index":0,"dressed":false})

func _process(_delta: float) -> void:
	if _lamp_cleanup_after_frame >= 0 and Engine.get_process_frames() >= _lamp_cleanup_after_frame:
		_lamps=_lamps.filter(func(lamp): return is_instance_valid(lamp) and not lamp.is_queued_for_deletion())
		_lamp_cleanup_after_frame=-1
	# Um lugar do DesertWilds montou neste quadro: o enfeite fatiado fica para o próximo, sem somar.
	if _dressing_yield_frame==Engine.get_process_frames(): return
	var process_span := STALL_WORK.begin()
	_stream_process()
	STALL_WORK.finish_slow("stream.desert.process",process_span,2000)

func _stream_process() -> void:
	if not _workshop_staged.is_empty():
		var staged: Array = _workshop_staged.pop_front()
		if is_instance_valid(staged[0]) and is_instance_valid(staged[1]) and (staged[1] as Node).get_parent() == null:
			var stage_span := STALL_WORK.begin()
			(staged[0] as Node).add_child(staged[1])
			STALL_WORK.finish_slow("stream.desert.workshop_stage", stage_span, 2000)
		return
	var began := Time.get_ticks_usec()
	var budget := 4000 if _drag_preparing else BUILD_BUDGET_USEC
	if _surface_jobs.is_empty():
		if _drag_preparing and not drag_view_pending.is_empty(): _begin_surface_job(drag_view_pending.pop_front())
		elif not pending.is_empty(): _begin_surface_job(pending.pop_front())
		elif not drag_view_pending.is_empty(): _begin_surface_job(drag_view_pending.pop_front())
	while not _surface_jobs.is_empty() and Time.get_ticks_usec()-began<budget:
		_advance_surface_job(_surface_jobs.keys()[0])
	while not build_jobs.is_empty() and Time.get_ticks_usec()-began<budget:
		var next_job: Dictionary=build_jobs[0]
		if _drag_preparing:
			for job in build_jobs:
				if drag_view_cells.has(job.key): next_job=job; break
		_run_build_job(next_job,maxf(1.0,budget-(Time.get_ticks_usec()-began)))

func _run_build_job(job: Dictionary, _budget: float) -> void:
	if not chunks.has(job.key):
		build_jobs.erase(job)
		return
	var chunk: Node3D=chunks[job.key]
	var items: Array=records.get(job.key,[])
	if int(job.index)<items.size():
		var record_began := STALL_WORK.begin()
		_build_record(chunk,items[int(job.index)])
		STALL_WORK.finish_slow("stream.desert.record.%s"%str(items[int(job.index)].get("kind","?")),record_began,2000)
		job.index=int(job.index)+1
	elif not bool(job.dressed):
		var stage:=int(job.get("dress_stage",0))
		# Spans das etapas sem nome (22/10): quadros de 38–61 ms no deserto com 30–59 ms sem span.
		var dress_began := STALL_WORK.begin()
		_dress_stage(chunk,job.rect,job.key,stage)
		STALL_WORK.finish_slow("stream.desert.dress_stage.%d"%stage,dress_began,2000)
		job.dress_stage=stage+1
		job.dressed=stage>=3
	elif not bool(job.get("ground_cover_done",false)):
		# Chão povoado (moitas, pedras, cascalho): ~4 mil peças por trecho, montadas em fatias do mesmo orçamento.
		if not job.has("ground_cover"): job.ground_cover=GROUND_COVER.begin(job.rect)
		job.ground_cover_done=GROUND_COVER.step(chunk,job.rect,job.ground_cover,_ground_height,_decoration_clear,_budget)
	elif int(job.get("expansion_stage",0))<EXPANSION.STAGES:
		var stage:=int(job.get("expansion_stage",0))
		var expansion_began := STALL_WORK.begin()
		EXPANSION.build_stage(chunk,job.rect,stage,_ground_height,_decoration_clear)
		STALL_WORK.finish_slow("stream.desert.expansion_stage.%d"%stage,expansion_began,2000)
		job.expansion_stage=stage+1
	elif not bool(job.get("mining_built",false)):
		var mining_began := STALL_WORK.begin()
		for lamp in MINING_ART.build_chunk(chunk,job.rect):
			lamp.light_energy=float(lamp.get_meta("mining_light_energy",1.8))*_night_level
			_lamps.append(lamp)
		STALL_WORK.finish_slow("stream.desert.mining",mining_began,2000)
		job.mining_built=true
	else:
		build_jobs.erase(job)
		# Trecho pronto: a mesma fusão por trecho do porto e da serra (encontro de arrancada com 539
		# superfícies, 95% com sombra, censo de 14/10). Espera 2 quadros para as edições do editor.
		chunk.set_meta("vegetation_ready_frame", Engine.get_physics_frames())
		_finish_chunk_for_reuse(chunk)

func _finish_chunk_for_reuse(chunk: Node3D) -> void:
	await preload("res://world/chunk_bake/ChunkCellMerge.gd").finish_chunk_later(chunk)
	if is_instance_valid(chunk) and not GPU_RELEASE.is_retired(chunk) and chunk.is_inside_tree():
		chunk.set_meta("desert_reuse_ready",true)

func _update_drag_residency(point: Vector3) -> void:
	var planar := Vector2(point.x,point.z)
	# The full panorama belongs to the race camera. In the compact map,
	# growing its sky band also covered town and the mine; ordinary visits
	# must retain their local chunks rather than preloading the entire strip.
	var near_course := LAYOUT.DRAG_STRIP_BOUNDS.grow(80 if drag_view_cells.is_empty() else 140).has_point(planar)
	if near_course == (not drag_view_cells.is_empty()): return
	drag_view_pending.clear()
	drag_view_cells.clear()
	_residency_dirty = true
	if not near_course: return
	for x in range(floori(DRAG_VIEW_BOUNDS.position.x/CELL),ceili(DRAG_VIEW_BOUNDS.end.x/CELL)):
		for z in range(floori(DRAG_VIEW_BOUNDS.position.y/CELL),ceili(DRAG_VIEW_BOUNDS.end.y/CELL)):
			var key := Vector2i(x,z)
			drag_view_cells[key] = true
			if not chunks.has(key): drag_view_pending.append(key)
	var at := _cell(point)
	drag_view_pending.sort_custom(func(a: Vector2i,b: Vector2i): return Vector2(a-at).length_squared()<Vector2(b-at).length_squared())

func is_streaming_idle() -> bool: return pending.is_empty() and drag_view_pending.is_empty() and build_jobs.is_empty() and _surface_jobs.is_empty()

func prepare_drag_view(enabled: bool) -> void:
	_drag_preparing=enabled
	if enabled: _update_drag_residency(LAYOUT.drag_staging_point())

func drag_view_progress() -> float:
	if drag_view_cells.is_empty(): return 0.0
	var remaining := {}
	for key in drag_view_cells:
		if not chunks.has(key): remaining[key]=true
	for job in build_jobs:
		if drag_view_cells.has(job.key): remaining[job.key]=true
	return 1.0-float(remaining.size())/float(drag_view_cells.size())

func drag_view_ready() -> bool:
	return not drag_view_cells.is_empty() and drag_view_pending.is_empty() and drag_view_progress()>=1.0
## Só as superfícies (chão e colisão), que saem síncronas, um trecho por quadro. O enfeite que vem
## depois é fatiado em ~1 ms por quadro, então terminar conta quadros, não tempo: 34 trechos perto
## da arrancada levaram ~1.600 quadros, 27 s a 60 fps (padrão) no editor, contra 0,7 s das
## superfícies (sonda de 18/10). Quem só precisa de chão firme (DesertWilds) espera isto.
func surfaces_idle() -> bool: return pending.is_empty() and drag_view_pending.is_empty() and _surface_jobs.is_empty()
## Quem monta algo neste quadro antes do _process do deserto (process_priority menor) pede para o
## enfeite não rodar junto. Sem isso, a montagem de 2,5 ms (editor) caía no mesmo quadro de uma
## fatia de chão povoado de até 5,4 ms e o quadro perdia o vsync de 60 Hz (34 ms, teste de 18/10).
func yield_dressing_this_frame() -> void: _dressing_yield_frame=Engine.get_process_frames()
func prewarm() -> void:
	# Shared materials are generated once. Do not instantiate the entire 3km desert.
	preload("res://world/desert/DesertTownMaterials.gd").prewarm()
	G.material(Color("b9a079"),true)
	G.material(Color("706d61"),false,true)
	expansion_prewarm=EXPANSION.prewarm(_ground_height)
	prebuild_workshop()
	# Chão do paddock da arrancada (22/10): o 1º trecho dele criava o material e a malha com o shader próprio
	# no quadro (drag_meet.ground.quad 17 ms, 2 pipelines surface). Uma peça escondida sob a cortina basta.
	if is_inside_tree() and OS.get_environment("GETECO_PADDOCK_PREWARM") != "0":
		var paddock := MeshInstance3D.new()
		paddock.mesh = QuadMesh.new()
		paddock.material_override = DRAG_MEET._ground_material()
		paddock.position = Vector3(0, -500, 0)
		add_child(paddock)
		paddock.queue_free()
func prewarm_incremental() -> void:
	prewarm()
	while not is_streaming_idle(): await get_tree().process_frame
func release_chunks() -> void:
	_drag_preparing=false
	if is_instance_valid(ambient): ambient.suspend()
	if is_instance_valid(wildlife): wildlife.suspend()
	if is_instance_valid(expansion_life): expansion_life.suspend()
	if is_instance_valid(mining_life): mining_life.suspend()
	if is_instance_valid(mining_dust): mining_dust.suspend()
	developer_view_cells.clear()
	pending.clear()
	drag_view_pending.clear()
	drag_view_cells.clear()
	build_jobs.clear()
	for job: Dictionary in _surface_jobs.values(): GPU_RELEASE.retire(job.chunk)
	_surface_jobs.clear()
	if is_instance_valid(drag_track_support): GPU_RELEASE.retire(drag_track_support)
	drag_track_support = null
	for key in chunks: _retire_or_cache_chunk(key,chunks[key])
	chunks.clear()
	abandoned_site=null
	canyon_site=null
	_lamps.clear()
	vehicle_support_cells.clear()
	current_cell=Vector2i(100000,100000)
	_residency_dirty=false
	_lamp_cleanup_after_frame=-1
func _trim_chunks() -> void:
	if current_cell.x==100000 or not _residency_dirty: return
	_residency_dirty=false
	for key in chunks.keys():
		if vehicle_support_cells.has(key) or developer_view_cells.has(key) or drag_view_cells.has(key): continue
		if absi(key.x-current_cell.x)>retention_radius or absi(key.y-current_cell.y)>retention_radius:
			# Descarte gradual (fila de vídeo, 16/10): o trecho some já e é liberado aos poucos. Os postes dele
			# saem da lista agora, porque continuam válidos (escondidos) até a fila chegar neles.
			var retired: Node3D = chunks[key]
			_retire_or_cache_chunk(key,retired)
			chunks.erase(key)
			for i in range(build_jobs.size()-1,-1,-1):
				if build_jobs[i].key==key: build_jobs.remove_at(i)
			_lamp_cleanup_after_frame=Engine.get_process_frames()+1
	# Speculative surfaces can become obsolete before completion after a fast
	# turn/teleport. Never spend the following frames constructing abandoned cells.
	for key in _surface_jobs.keys():
		if vehicle_support_cells.has(key) or developer_view_cells.has(key) or drag_view_cells.has(key): continue
		if absi(key.x-current_cell.x)<=retention_radius and absi(key.y-current_cell.y)<=retention_radius: continue
		var unfinished: Dictionary=_surface_jobs[key]
		GPU_RELEASE.retire(unfinished.chunk)
		_surface_jobs.erase(key)

func _retire_or_cache_chunk(key: Vector2i, chunk: Node3D) -> void:
	var lamps: Array=[]
	for lamp in _lamps:
		if is_instance_valid(lamp) and chunk.is_ancestor_of(lamp): lamps.append(lamp)
	_lamps=_lamps.filter(func(lamp): return is_instance_valid(lamp) and not chunk.is_ancestor_of(lamp))
	var entry := {"chunk":chunk,"lamps":lamps,"abandoned_site":null,"canyon_site":null}
	if is_instance_valid(abandoned_site) and chunk.is_ancestor_of(abandoned_site):
		entry.abandoned_site=abandoned_site
		abandoned_site=null
	if is_instance_valid(canyon_site) and chunk.is_ancestor_of(canyon_site):
		entry.canyon_site=canyon_site
		canyon_site=null
	# Active actors, movable bodies or audio have their own owners/lifecycle;
	# completed static cells alone enter this cache. Pending merge coroutines
	# are excluded by the marker set only after finish_chunk_later returns.
	var reusable := chunk.has_meta("desert_reuse_ready") and not is_instance_valid(entry.abandoned_site) and not chunk.has_meta("desert_canyon_site")
	if reusable:
		for node in chunk.find_children("*","Node",true,false):
			if node is CharacterBody3D or node is RigidBody3D or (node is AudioStreamPlayer3D and node.playing) or (node is AudioStreamPlayer and node.playing) or node.is_in_group("digo_vehicle_gate") or node.is_in_group("v2_walkin_facade") or node.is_in_group("desert_toll_plaza") or node.is_in_group("desert_north_pass_gate"):
				reusable=false
				break
	if not reusable:
		_park_workshop_from(chunk)
		GPU_RELEASE.retire(chunk)
		return
	if chunk.get_parent()!=null: chunk.get_parent().remove_child(chunk)
	for retired in _chunk_cache.put(key,entry):
		_park_workshop_from(retired)
		GPU_RELEASE.retire_detached_subtree(retired)

## Oficina do Digo montada uma vez e estacionada (22/10): o registro inteiro custava 141–147 ms num
## quadro a cada visita (stream.desert.record.drag_workshop; pátio 64–70, lote 25), e o trecho dela
## quase nunca volta do cache (Digo, música e portão o tornam não reaproveitável). Só peças estáticas
## (malhas, colisões, placa): sai da árvore com o trecho e volta pronta no próximo. O pré-aquecimento
## monta a primeira sob a cortina. GETECO_DIGO_WORKSHOP_PARK=0 volta a montar a cada visita (A/B).
static var _workshop_park_enabled := OS.get_environment("GETECO_DIGO_WORKSHOP_PARK") != "0"
var _parked_workshop: Node3D
var _workshop_staged: Array = []

func _park_workshop_from(chunk: Node3D) -> void:
	if not _workshop_park_enabled or not is_instance_valid(chunk) or is_instance_valid(_parked_workshop): return
	var workshop := chunk.get_node_or_null("DigoWorkshop") as Node3D
	if workshop == null or not workshop.has_meta("desert_drag_workshop") or workshop.is_queued_for_deletion(): return
	chunk.remove_child(workshop)
	_parked_workshop = workshop

func _take_parked_workshop() -> Node3D:
	if not _workshop_park_enabled or not is_instance_valid(_parked_workshop): return null
	var workshop := _parked_workshop
	_parked_workshop = null
	workshop.visible = true
	# A fusão por célula do trecho velho escondeu as malhas dela (o lote ficou lá): voltam a aparecer e o
	# trecho novo funde de novo, como os registros guardados do NativeRegion.
	preload("res://world/chunk_bake/ChunkCellMerge.gd").restore_sources(workshop)
	return workshop

## Sob a cortina: monta a oficina fora de vista (o _ready dela roda ao entrar na árvore) e a estaciona.
func prebuild_workshop() -> void:
	if not _workshop_park_enabled or is_instance_valid(_parked_workshop) or not is_inside_tree(): return
	for chunk: Node3D in chunks.values():
		if is_instance_valid(chunk) and chunk.get_node_or_null("DigoWorkshop") != null: return
	var began := STALL_WORK.begin()
	var workshop := load("res://world/desert/drag_meet/DesertDigoWorkshop.gd").new() as Node3D
	workshop.name="DigoWorkshop"
	workshop.visible = false
	add_child(workshop)
	remove_child(workshop)
	_parked_workshop = workshop
	STALL_WORK.finish_slow("desert.prebuild_workshop",began,2000)

func _restore_cached_chunk(key: Vector2i, entry: Dictionary) -> void:
	var chunk: Node3D=entry.chunk
	chunks[key]=chunk
	add_child(chunk)
	for lamp in entry.get("lamps",[]):
		if is_instance_valid(lamp):
			_lamps.append(lamp)
			if not lamp.get_meta("street_destroyed",false): lamp.light_energy=float(lamp.get_meta("mining_light_energy",1.8))*_night_level
	if is_instance_valid(entry.get("abandoned_site")): abandoned_site=entry.abandoned_site
	if is_instance_valid(entry.get("canyon_site")): canyon_site=entry.canyon_site
	var rect := Rect2(Vector2(key)*CELL,Vector2.ONE*CELL)
	if rect.intersects(DRAG_SUPPORT.BOUNDS) and not is_instance_valid(drag_track_support): drag_track_support=DRAG_SUPPORT.install(self)

func streaming_reuse_diagnostics() -> Dictionary:
	var result: Dictionary=_chunk_cache.diagnostics()
	result["preparing_surfaces"]=_surface_jobs.size()
	return result

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE:
		preload("res://world/desert/DesertPreparationLifetime.gd").cancel(_presentation_lifetime)
		if is_instance_valid(_horizon) and _horizon.get_parent()==null: _horizon.free()
		if is_instance_valid(_parked_workshop) and _parked_workshop.get_parent()==null: _parked_workshop.free()
		for staged: Array in _workshop_staged:
			if is_instance_valid(staged[1]) and (staged[1] as Node).get_parent()==null: (staged[1] as Node).free()
		for retained in _chunk_cache.clear():
			if is_instance_valid(retained) and retained.get_parent()==null: retained.free()

func set_chairlift_operating(_value: bool) -> void: pass
func set_night_lights(level: float) -> void:
	_night_level=clampf(level,0,1)
	for lamp in _lamps:
		if is_instance_valid(lamp) and not lamp.get_meta("street_destroyed",false): lamp.light_energy=float(lamp.get_meta("mining_light_energy",1.8))*_night_level

func _surface(chunk: Node3D, id: String, rect: Rect2, offset: float, mat: Material, solid := false) -> void:
	if not rect.has_area(): return
	# Every layer follows the same piecewise-linear ramp, including paint and shoulders.
	if rect.end.y>-448:
		for z in range(floori(rect.position.y/8.0),ceili(rect.end.y/8.0)):
			_surface_quad(chunk,id,rect.intersection(Rect2(rect.position.x,float(z)*8,rect.size.x,8)),offset,mat,solid)
	else: _surface_quad(chunk,id,rect,offset,mat,solid)

func _ramp_height(point: Vector2) -> float:
	if point.y<=-448: return 0.0
	var low := floorf(point.y/8.0)*8.0
	var high := minf(low+8.0,LAYOUT.BOUNDS.end.y)
	if high<=low: return LAYOUT.surface_height(point)
	return lerpf(LAYOUT.surface_height(Vector2(point.x,low)),LAYOUT.surface_height(Vector2(point.x,high)),(point.y-low)/(high-low))

func _surface_quad(chunk: Node3D, id: String, rect: Rect2, offset: float, mat: Material, solid: bool) -> void:
	if not rect.has_area(): return
	var points := PackedVector3Array()
	for p in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		points.append(Vector3(p.x,_ramp_height(p)+offset,p.y))
	var surface := G.quad(chunk,id,points,mat,solid)
	if id=="DesertGround": surface.set_meta("desert_base_ground",true)
	# Wheel contact drives tire dirt, skid audio and traction. Naming is not a surface contract.
	var vehicle_surface := "hard" if id=="WeatheredAsphalt" else "dirt"
	surface.set_meta("vehicle_surface",vehicle_surface)
	if solid:
		for child in surface.get_children():
			if child is StaticBody3D: child.set_meta("vehicle_surface",vehicle_surface)

func _build_surfaces(chunk: Node3D, rect: Rect2) -> void:
	for stage in SURFACE_STAGES: _build_surface_stage(chunk,rect,stage)

## Same ordered constructors as the synchronous path, with a yield boundary
## between independent owners. No surface is exposed until all stages finish.
func _build_surface_stage(chunk: Node3D, rect: Rect2, stage: int) -> void:
	match stage:
		0:
			if is_instance_valid(drag_scenery): drag_scenery.build_collision(chunk,rect)
		1:
			for flat in TERRAIN_MESH.flat_remainders(rect):
				for remaining in MINING_ART.ground_remainders(flat):
					for untouched in SMUGGLER_LAYOUT.ground_remainders(remaining):
						_surface(chunk,"DesertGround",untouched,0,G.material(Color("b9a079"),true),true)
		2:
			var site := SMUGGLER_SCENERY.build_chunk(chunk,rect)
			if is_instance_valid(site): chunk.set_meta("desert_canyon_site",site)
		3:
			if rect.intersects(RELIEF.BOUNDS): TERRAIN_MESH.install_collision(chunk,Vector2i((rect.get_center()/CELL).floor()))
		4: road_geometry.build_chunk(chunk,rect)
		5: DETAIL.build_sites_ground(chunk,rect)
		6: EXPANSION.build_surfaces(chunk,rect,_ground_height)
		7: MINING_ART.build_surfaces(chunk,rect)
		8: MOON_VILLAGE.build_ground(chunk,rect)
		9: MOON_VILLAGE.build_collision(chunk,rect)
		10: preload("res://world/desert/north_pass/DesertNorthPassScenery.gd").build_chunk(chunk,rect,north_pass_completed)
		11:
			if preload("res://runtime/desert/DesertActivitiesPolicy.gd").enabled(): preload("res://world/desert/community/DesertCommunitySite.gd").build_chunk(chunk,rect)
		12: DRAG_MEET.build_ground(chunk,rect)
		13:
			if rect.intersects(DRAG_SUPPORT.BOUNDS):
				if not is_instance_valid(drag_track_support): drag_track_support = DRAG_SUPPORT.install(self)
				DRAG_SUPPORT.replace_chunk_collision(self,chunk)
		14: preload("res://world/desert/DesertGroundOwnership.gd").compose(chunk,rect,road_geometry)
		15: preload("res://activities/desert_drag/DesertDragBoardProp.gd").build_chunk(chunk,rect)
		16: _boundary_ridge(chunk,rect)
		17: preload("res://world/regions/ScenarioBoundary3D.gd").build_desert(chunk,rect,_ground_height)

func set_north_pass_completed(completed: bool) -> void:
	north_pass_completed=completed
	if not is_inside_tree(): return
	for gate in get_tree().get_nodes_in_group(preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").GROUP):
		if is_ancestor_of(gate): preload("res://world/desert/north_pass/DesertNorthPassScenery.gd").set_completed(gate,completed)

func _boundary_ridge(chunk: Node3D, rect: Rect2) -> void:
	var bounds := LAYOUT.BOUNDS
	var sites: Array[Vector2]=[]
	for z in range(floori(rect.position.y/44),ceili(rect.end.y/44)):
		for x in [bounds.position.x+12,bounds.end.x-12]: sites.append(Vector2(x,float(z)*44+22))
	for x in range(floori(rect.position.x/44),ceili(rect.end.x/44)):
		for z in [bounds.position.y+12,bounds.end.y-12]:
			var p := Vector2(float(x)*44+22,z)
			# Reserve the complete irregular footprint around the independent bridge.
			if z>bounds.end.y-20 and absf(p.x-LAYOUT.BRIDGE_END.x)<78: continue
			sites.append(p)
	for point in sites:
		if not rect.has_point(point): continue
		var ridge_point: Vector2=point
		if not preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").reservation_clear(point):
			# Keep the boundary sealed outside the cut. Only the central outcrop
			# conflicts with the road; move the eastern one beyond the cliff.
			if not is_equal_approx(point.y,bounds.position.y+12): continue
			var offset: float=point.x-preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").X
			if absf(offset)<20: continue
			if offset>0 and offset<40: ridge_point.x=402.0
		# Seal the new perimeter from outside. A 55 m rock centred 12 m inside
		# the old basin would bury the places now bordering the smaller map.
		# The irregular foot reaches at least 28 m in Z and 35 m in X;
		# a 26 m setback keeps it touching the ground edge without a gap.
		if is_equal_approx(point.x,bounds.position.x+12): ridge_point.x=bounds.position.x-26.0
		if is_equal_approx(point.x,bounds.end.x-12): ridge_point.x=bounds.end.x+26.0
		if is_equal_approx(point.y,bounds.position.y+12): ridge_point.y=bounds.position.y-26.0
		if is_equal_approx(point.y,bounds.end.y-12): ridge_point.y=bounds.end.y+26.0
		var height := 16+sin(point.x*.015+point.y*.027)*4
		ROCK_FORMS.create_outcrop(chunk,Vector3(ridge_point.x,_ground_height(ridge_point),ridge_point.y),55.0,height+5.0,absi(int(point.x*71+point.y*133)),true)

func _build_record(chunk: Node3D, record: Dictionary) -> void:
	match record.kind:
		"entrance_toll": chunk.add_child(preload("res://world/desert/entrance/DesertTollPlaza.gd").new())
		"drag_meet": DRAG_MEET.build_record(chunk,record)
		"drag_workshop":
			var workshop := _take_parked_workshop()
			var staged: Array = []
			if workshop == null:
				workshop = load("res://world/desert/drag_meet/DesertDigoWorkshop.gd").new() as Node3D
				workshop.name="DigoWorkshop"
			else:
				# Pátio e Gol (126 de 192 nós) voltam nos quadros seguintes: no jogo a volta inteira custou
				# 20 ms num quadro (estresse do deserto de 22/10). Só peças estáticas; nada depende da ordem.
				for part_name in ["DigoYardDetails","GolUnderRepair"]:
					var part := workshop.get_node_or_null(part_name)
					if part == null: continue
					workshop.remove_child(part)
					staged.append([workshop,part])
			workshop.position=record.position
			chunk.add_child(workshop)
			_workshop_staged.append_array(staged)
		"moon_village":
			for lamp in MOON_VILLAGE.build_record(chunk,record.data):
				lamp.light_energy=1.8*_night_level
				_lamps.append(lamp)
		"forge_miner_camp": chunk.add_child(preload("res://world/desert/DesertMinerCamp.gd").new())
		"abandoned_site":
			abandoned_site=ABANDONED.build()
			chunk.add_child(abandoned_site)
		"utility_pole", "utility_span", "utility_service": UTILITY.build_record(chunk,record)
		"building": chunk.add_child(ART.building(record.data))
		"desert_underground": UNDERGROUND.build_record(chunk,record)
		"truck_stop":
			var stop := ART.truck_stop(false)
			stop.position=record.position
			chunk.add_child(stop)
		"coach_stop": chunk.add_child(preload("res://world/desert/DesertCoachStop.gd").build())
		"bitrem":
			var truck := ART.bitrem([Color("a75339"),Color("718787"),Color("d2b676"),Color("76634e")][int(record.index)])
			truck.position=record.position
			chunk.add_child(truck)
		"lamp": _lamp(chunk,record.position)
		"water_tower": _water_tower(chunk,record.position)
		"rest_bench":
			var p: Vector3=record.position
			var bench := Node3D.new()
			bench.name="HorizonteBreakableBench"
			bench.position=p
			chunk.add_child(bench)
			G.box(bench,"HorizonteBenchSeat",Vector3(0,.52,0),Vector3(2.6,.22,.76),Color("8b6849"),true)
			G.box(bench,"HorizonteBenchBack",Vector3(0,.93,-.32),Vector3(2.6,.74,.14),Color("927152"),true)
			for side in [-1.0,1.0]:
				G.box(bench,"BenchLeg",Vector3(side*.94,.22,0),Vector3(.13,.44,.62),Color("646654"),true)
				G.box(bench,"BenchArm",Vector3(side*1.25,.78,.03),Vector3(.12,.12,.76),Color("646654"),true)
			preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("bench_seat",bench,chunk)
		"drag_line":
			var p: Vector3=record.position
			for i in 10:
				var color := Color("d3c8a4") if i%2==0 or not record.finish else Color("34352f")
				G.box(chunk,"FinishSquare" if record.finish else "StartStripe",p+Vector3(0,.032,-4.5+float(i)),Vector3(.65,.015,1),color)

func _lamp(chunk: Node3D, at: Vector3) -> void:
	var pole := Node3D.new()
	pole.name="DesertBreakableLamp"
	pole.position=at
	chunk.add_child(pole)
	G.box(pole,"LampPole",Vector3(0,3.6,0),Vector3(.14,7.2,.14),Color("7a7361"),true)
	G.box(pole,"LampArm",Vector3(0,7.15,1),Vector3(.1,.1,2),Color("7a7361"))
	G.box(pole,"LampHead",Vector3(0,7.08,2),Vector3(.6,.15,1),Color("d6c19a"))
	var lamp := OmniLight3D.new()
	lamp.position=Vector3(0,6.8,2)
	lamp.light_color=Color("ffd29a")
	lamp.omni_range=32
	lamp.light_energy=1.8*_night_level
	lamp.shadow_enabled=false
	pole.add_child(lamp)
	_lamps.append(lamp)
	preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("lamp",pole,chunk)

func _water_tower(chunk: Node3D, at: Vector3) -> void:
	for x in [-2.0,2.0]:
		for z in [-2.0,2.0]: G.box(chunk,"WaterTowerLeg",at+Vector3(x,5,z),Vector3(.28,10,.28),Color("78684d"),true)
	G.cylinder(chunk,"WaterTank",at+Vector3(0,11,0),3.1,4,Color("a29777"))
	G.cylinder(chunk,"TankRim",at+Vector3(0,13.04,0),3.3,.2,Color("736c56"))

func _dress(chunk: Node3D, rect: Rect2, key: Vector2i) -> void:
	for stage in 4: _dress_stage(chunk,rect,key,stage)

func _dress_stage(chunk: Node3D, rect: Rect2, key: Vector2i, stage: int) -> void:
	var began := STALL_WORK.begin()
	match stage:
		0: DETAIL.build_chunk(chunk,rect,roads,_decoration_clear,_ground_height)
		1:
			if rect.intersects(RELIEF.BOUNDS): CANYON_DRESSING.build_chunk(chunk,rect,6102026,_ground_height)
		2:
			if rect.intersects(RELIEF.BOUNDS): DRY_FLORA.build_chunk(chunk,rect,6102026,_ground_height)
		3: _dress_props(chunk,rect,key)
	STALL_WORK.finish_slow("stream.desert.dress.%s"%["detail","canyon","flora","props"][stage],began,2000)

func _dress_props(chunk: Node3D, rect: Rect2, key: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=absi(key.x*73856093^key.y*19349663)+6606
	for i in 8:
		var p := Vector2(rng.randf_range(rect.position.x+2,rect.end.x-2),rng.randf_range(rect.position.y+2,rect.end.y-2))
		if not _decoration_clear(p,4): continue
		var node: Node3D
		if i%3==0: node=ART.cactus(rng.randf_range(1.6,3.7))
		else:
			node=Node3D.new()
			var size := Vector3(rng.randf_range(.6,2.1),rng.randf_range(.35,1.1),rng.randf_range(.65,1.7))
			var rock := ROCKS.rock(node,"Sandstone",Vector3(0,size.y*.45,0),size,Color("9f7d56"),size.x>1.2)
			rock.rotation.y=rng.randf()*TAU
			rock.rotation.z=.12
		node.position=Vector3(p.x,_ground_height(p),p.y)
		chunk.add_child(node)
		preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("desert_tree" if i%3==0 else "desert_rock",node,chunk,{},[],.8 if i%3==0 else -1.0)
	# Broad stratified mesas leave recognizable empty basins and road sightlines.
	if posmod(key.x*7+key.y*3,9)==0:
		var center := rect.get_center()
		if not RELIEF.BOUNDS.grow(34).has_point(center) and _decoration_clear(center,34):
			var persistent: bool=is_instance_valid(drag_scenery) and drag_scenery.owns_outcrop(key)
			ROCK_FORMS.create_outcrop(chunk,Vector3(center.x,_ground_height(center),center.y),28.0,23.0,absi(key.x*771+key.y*331),true,not persistent)

func _ground_height(point: Vector2) -> float:
	if SMUGGLER_LAYOUT.enabled() and SMUGGLER_LAYOUT.BOUNDS.has_point(point): return preload("res://world/desert/canyon/DesertSmugglerTerrain.gd").surface_height(point)
	if MINING_LAYOUT.enabled() and MINING_LAYOUT.BOUNDS.has_point(point): return MINING_ART.surface_height(point)
	return _ramp_height(point)+TERRAIN_MESH.surface_height(point)

func _decoration_clear(point: Vector2, radius: float) -> bool:
	if is_instance_valid(drag_scenery) and not drag_scenery.reservation_clear(point,radius): return false
	if preload("res://world/desert/entrance/DesertTollPlaza.gd").RESERVATION.grow(radius).has_point(point): return false
	if not SMUGGLER_LAYOUT.reservation_clear(point,radius): return false
	if Rect2(-189,-891 + COMPACT.TOWN.z,8,6).grow(radius+.4).has_point(point): return false
	if not preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").reservation_clear(point,radius): return false
	if not MOON_VILLAGE.reservation_clear(point,radius): return false
	if not MINING_LAYOUT.reservation_clear(point,radius): return false
	if not ABANDONED.reservation_clear(point,radius) or BANDIT_CAMP.reserved(point,radius): return false
	if preload("res://runtime/desert/wilds/DesertWilds.gd").reserved(point,radius): return false
	if not EXPANSION.reservation_clear(point,radius): return false
	if RELIEF.passage_clear(point,radius): return false
	# Small props sit on gentle ground; escarpments are the rock formation itself.
	if RELIEF.BOUNDS.has_point(point) and RELIEF.normal_at(point).y<.93: return false
	if not LAYOUT.road_clear(point,radius): return false
	if Rect2(210,-797 + COMPACT.TRUCK_STOP.z,125,92).grow(radius).has_point(point): return false
	if not LAYOUT.drag_reservation_clear(point,radius): return false
	for building in buildings:
		var p: Vector3=building.position
		var size: Vector2=building.size
		if Rect2(Vector2(p.x,p.z)-size*.5,size).grow(radius+5).has_point(point): return false
	return true

func set_environment_activity(enabled: bool, point: Vector3) -> void:
	if is_instance_valid(mining_dust):
		if enabled: mining_dust.set_focus(point)
		else: mining_dust.suspend()
	if is_instance_valid(mining_life):
		if enabled: mining_life.set_focus(point)
		else: mining_life.suspend()
	if is_instance_valid(wildlife):
		if enabled: wildlife.set_focus(point)
		else: wildlife.suspend()
	if is_instance_valid(expansion_life):
		if enabled: expansion_life.set_focus(point)
		else: expansion_life.suspend()
	if not is_instance_valid(ambient): return
	if enabled: ambient.set_focus(point)
	else: ambient.suspend()
