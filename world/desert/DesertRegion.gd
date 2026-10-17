extends Node3D
## Independent streamed region. Coordinates never pass through Harbor's legacy pixel adapter.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
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
const SMUGGLER_LAYOUT := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const SMUGGLER_SCENERY := preload("res://world/desert/canyon/DesertSmugglerScenery.gd")
const CELL := 96.0
const BUILD_BUDGET_USEC := 1000
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
var chunks: Dictionary = {}
var records: Dictionary = {}
var pending: Array[Vector2i] = []
var build_jobs: Array[Dictionary] = []
var roads: Array[Dictionary] = []
var walkways: Array[Dictionary] = []
var buildings: Array[Dictionary] = []
var entries: Array[Dictionary] = []
var terrain: Node3D = null
var harbor_road_geometry: RefCounted = null
var vehicle_support_cells: Dictionary = {}
var source_data: Dictionary = {}
var _night_level := 0.0
var _lamps: Array[OmniLight3D] = []
var _horizon: Node3D
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
	_horizon=preload("res://world/desert/DesertHorizon.gd").build()
	add_child(_horizon)
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
	for x in range(-350,-100,36): _record(Vector3(x,0,-888),{"kind":"lamp","position":Vector3(x,0,-888)})
	for x in range(-900,91,64): _record(Vector3(x,0,-1330),{"kind":"lamp","position":Vector3(x,0,-1330)})
	# The workshop pole stands outside both working bays; the eastern pole sits
	# between Jessica and her neighbouring visitors, clear of the access curve.
	for point in [Vector3(-1034,0,-1297),Vector3(-978,0,-1288),Vector3(-911,0,-1271),Vector3(-1013,0,-1252),Vector3(-951,0,-1240),Vector3(-917,0,-1220)]:
		_record(point,{"kind":"lamp","position":point})
	for record in DRAG_MEET.records(): _record(record.position,record)
	_record(Vector3(-390,0,-926),{"kind":"water_tower","position":Vector3(-390,0,-926)})
	_record(Vector3(-315,0,-914.2),{"kind":"rest_bench","position":Vector3(-315,0,-914.2)})
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
	var rect := Rect2(Vector2(key)*CELL,Vector2.ONE*CELL).intersection(LAYOUT.BOUNDS)
	if not rect.has_area(): return
	var chunk := Node3D.new()
	chunk.name="Desert_%d_%d"%[key.x,key.y]
	add_child(chunk)
	chunks[key]=chunk
	# Collidable terrain and all road support are ready before admitting actors.
	var began := STALL_WORK.begin()
	_build_surfaces(chunk,rect)
	STALL_WORK.finish_slow("stream.desert.surfaces",began,2000)
	build_jobs.append({"key":key,"rect":rect,"index":0,"dressed":false})

func _process(_delta: float) -> void:
	if _lamp_cleanup_after_frame >= 0 and Engine.get_process_frames() >= _lamp_cleanup_after_frame:
		_lamps=_lamps.filter(func(lamp): return is_instance_valid(lamp) and not lamp.is_queued_for_deletion())
		_lamp_cleanup_after_frame=-1
	var began := Time.get_ticks_usec()
	if not pending.is_empty(): _ensure_chunk_surfaces(pending.pop_front())
	while not build_jobs.is_empty() and Time.get_ticks_usec()-began<BUILD_BUDGET_USEC:
		_run_build_job(build_jobs[0],BUILD_BUDGET_USEC)

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
		_dress(chunk,job.rect,job.key)
		job.dressed=true
	elif not bool(job.get("ground_cover_done",false)):
		# Chão povoado (moitas, pedras, cascalho): ~4 mil peças por trecho, montadas em fatias do mesmo orçamento.
		if not job.has("ground_cover"): job.ground_cover=GROUND_COVER.begin(job.rect)
		job.ground_cover_done=GROUND_COVER.step(chunk,job.rect,job.ground_cover,_ground_height,_decoration_clear,_budget)
	elif int(job.get("expansion_stage",0))<EXPANSION.STAGES:
		var stage:=int(job.get("expansion_stage",0))
		EXPANSION.build_stage(chunk,job.rect,stage,_ground_height,_decoration_clear)
		job.expansion_stage=stage+1
	elif not bool(job.get("mining_built",false)):
		for lamp in MINING_ART.build_chunk(chunk,job.rect):
			lamp.light_energy=float(lamp.get_meta("mining_light_energy",1.8))*_night_level
			_lamps.append(lamp)
		job.mining_built=true
	else:
		build_jobs.erase(job)
		# Trecho pronto: a mesma fusão por trecho do porto e da serra (encontro de arrancada com 539
		# superfícies, 95% com sombra, censo de 14/10). Espera 2 quadros para as edições do editor.
		chunk.set_meta("vegetation_ready_frame", Engine.get_physics_frames())
		preload("res://world/chunk_bake/ChunkCellMerge.gd").finish_chunk_later(chunk)

func is_streaming_idle() -> bool: return pending.is_empty() and build_jobs.is_empty()
func prewarm() -> void:
	# Shared materials are generated once. Do not instantiate the entire 3km desert.
	preload("res://world/desert/DesertTownMaterials.gd").prewarm()
	G.material(Color("b9a079"),true)
	G.material(Color("706d61"),false,true)
	expansion_prewarm=EXPANSION.prewarm(_ground_height)
func prewarm_incremental() -> void:
	prewarm()
	while not is_streaming_idle(): await get_tree().process_frame
func release_chunks() -> void:
	if is_instance_valid(ambient): ambient.suspend()
	if is_instance_valid(wildlife): wildlife.suspend()
	abandoned_site=null
	canyon_site=null
	if is_instance_valid(expansion_life): expansion_life.suspend()
	if is_instance_valid(mining_life): mining_life.suspend()
	if is_instance_valid(mining_dust): mining_dust.suspend()
	pending.clear()
	build_jobs.clear()
	for chunk in chunks.values(): GPU_RELEASE.retire(chunk)
	chunks.clear()
	_lamps.clear()
	vehicle_support_cells.clear()
	current_cell=Vector2i(100000,100000)
	_residency_dirty=false
	_lamp_cleanup_after_frame=-1
func _trim_chunks() -> void:
	if current_cell.x==100000 or not _residency_dirty: return
	_residency_dirty=false
	for key in chunks.keys():
		if vehicle_support_cells.has(key): continue
		if absi(key.x-current_cell.x)>retention_radius or absi(key.y-current_cell.y)>retention_radius:
			# Descarte gradual (fila de vídeo, 16/10): o trecho some já e é liberado aos poucos. Os postes dele
			# saem da lista agora, porque continuam válidos (escondidos) até a fila chegar neles.
			var retired: Node3D = chunks[key]
			_lamps=_lamps.filter(func(lamp): return is_instance_valid(lamp) and not retired.is_ancestor_of(lamp))
			GPU_RELEASE.retire(retired)
			chunks.erase(key)
			for i in range(build_jobs.size()-1,-1,-1):
				if build_jobs[i].key==key: build_jobs.remove_at(i)
			_lamp_cleanup_after_frame=Engine.get_process_frames()+1

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
	# Canyon rendering remains resident; only the identical physical faces stream.
	# Exclude its rectangle from the old flat ground, avoiding overlapping surfaces.
	for flat in TERRAIN_MESH.flat_remainders(rect):
		for remaining in MINING_ART.ground_remainders(flat):
			for untouched in SMUGGLER_LAYOUT.ground_remainders(remaining):
				_surface(chunk,"DesertGround",untouched,0,G.material(Color("b9a079"),true),true)
	var site := SMUGGLER_SCENERY.build_chunk(chunk,rect)
	if is_instance_valid(site): canyon_site=site
	if rect.intersects(RELIEF.BOUNDS): TERRAIN_MESH.install_collision(chunk,Vector2i((rect.get_center()/CELL).floor()))
	road_geometry.build_chunk(chunk,rect)
	DETAIL.build_sites_ground(chunk,rect)
	EXPANSION.build_surfaces(chunk,rect,_ground_height)
	MINING_ART.build_surfaces(chunk,rect)
	MOON_VILLAGE.build_ground(chunk,rect)
	MOON_VILLAGE.build_collision(chunk,rect)
	preload("res://world/desert/north_pass/DesertNorthPassScenery.gd").build_chunk(chunk,rect,north_pass_completed)
	if preload("res://runtime/desert/DesertActivitiesPolicy.gd").enabled(): preload("res://world/desert/community/DesertCommunitySite.gd").build_chunk(chunk,rect)
	DRAG_MEET.build_ground(chunk,rect)
	preload("res://world/desert/DesertGroundOwnership.gd").compose(chunk,rect,road_geometry)
	preload("res://activities/desert_drag/DesertDragBoardProp.gd").build_chunk(chunk,rect)
	_boundary_ridge(chunk,rect)
	preload("res://world/regions/ScenarioBoundary3D.gd").build_desert(chunk,rect,_ground_height)

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
		var height := 16+sin(point.x*.015+point.y*.027)*4
		ROCK_FORMS.create_outcrop(chunk,Vector3(ridge_point.x,_ground_height(ridge_point),ridge_point.y),55.0,height+5.0,absi(int(point.x*71+point.y*133)),true)

func _build_record(chunk: Node3D, record: Dictionary) -> void:
	match record.kind:
		"entrance_toll": chunk.add_child(preload("res://world/desert/entrance/DesertTollPlaza.gd").new())
		"drag_meet": DRAG_MEET.build_record(chunk,record)
		"drag_workshop":
			var workshop := load("res://world/desert/drag_meet/DesertDigoWorkshop.gd").new() as Node3D
			workshop.name="DigoWorkshop"
			workshop.position=record.position
			chunk.add_child(workshop)
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
	# Spans por etapa (16/10): o pico de ~150 ms sem span na travessia em (479, -333) cai
	# justamente no quadro em que um trecho do deserto se veste.
	var began := STALL_WORK.begin()
	DETAIL.build_chunk(chunk,rect,roads,_decoration_clear,_ground_height)
	STALL_WORK.finish_slow("stream.desert.dress.detail",began,2000)
	began = STALL_WORK.begin()
	if rect.intersects(RELIEF.BOUNDS): CANYON_DRESSING.build_chunk(chunk,rect,6102026,_ground_height)
	STALL_WORK.finish_slow("stream.desert.dress.canyon",began,2000)
	began = STALL_WORK.begin()
	if rect.intersects(RELIEF.BOUNDS): DRY_FLORA.build_chunk(chunk,rect,6102026,_ground_height)
	STALL_WORK.finish_slow("stream.desert.dress.flora",began,2000)
	began = STALL_WORK.begin()
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
		preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("desert_tree" if i%3==0 else "desert_rock",node,chunk)
	# Broad stratified mesas leave recognizable empty basins and road sightlines.
	if posmod(key.x*7+key.y*3,9)==0:
		var center := rect.get_center()
		if not RELIEF.BOUNDS.grow(34).has_point(center) and _decoration_clear(center,34):
			ROCK_FORMS.create_outcrop(chunk,Vector3(center.x,_ground_height(center),center.y),28.0,23.0,absi(key.x*771+key.y*331),true)
	STALL_WORK.finish_slow("stream.desert.dress.props",began,2000)

func _ground_height(point: Vector2) -> float:
	if SMUGGLER_LAYOUT.enabled() and SMUGGLER_LAYOUT.BOUNDS.has_point(point): return preload("res://world/desert/canyon/DesertSmugglerTerrain.gd").surface_height(point)
	if MINING_LAYOUT.enabled() and MINING_LAYOUT.BOUNDS.has_point(point): return MINING_ART.surface_height(point)
	return _ramp_height(point)+TERRAIN_MESH.surface_height(point)

func _decoration_clear(point: Vector2, radius: float) -> bool:
	if preload("res://world/desert/entrance/DesertTollPlaza.gd").RESERVATION.grow(radius).has_point(point): return false
	if not SMUGGLER_LAYOUT.reservation_clear(point,radius): return false
	if Rect2(-189,-891,8,6).grow(radius+.4).has_point(point): return false
	if not preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").reservation_clear(point,radius): return false
	if not MOON_VILLAGE.reservation_clear(point,radius): return false
	if not MINING_LAYOUT.reservation_clear(point,radius): return false
	if not ABANDONED.reservation_clear(point,radius) or BANDIT_CAMP.reserved(point,radius): return false
	if not EXPANSION.reservation_clear(point,radius): return false
	if RELIEF.passage_clear(point,radius): return false
	# Small props sit on gentle ground; escarpments are the rock formation itself.
	if RELIEF.BOUNDS.has_point(point) and RELIEF.normal_at(point).y<.93: return false
	if not LAYOUT.road_clear(point,radius): return false
	if Rect2(210,-797,125,92).grow(radius).has_point(point): return false
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
