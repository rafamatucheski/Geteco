extends Node3D
## Streamed native railway: shared centre-lines, batched geometry and physical
## platforms. No road graph edits, projected sprites or per-car SubViewports.
const NETWORK := preload("res://world/railway/RailwayNetwork.gd")
const CELL := 64.0
const LOAD_DISTANCE := 240.0
const RELEASE_DISTANCE := 310.0
const UPDATE_INTERVAL := 0.2
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
var controller
var chunks: Dictionary = {}
var station_nodes: Dictionary = {}
var tunnel_nodes: Dictionary = {}
var focus := Vector3.INF
var _descriptors: Dictionary = {}
var _pending: Array[Vector2i] = []
## Trechos a refazer (apoio caiu numa estrada de região que terminou de preparar): o velho fica até o
## novo ficar pronto, um por quadro como os outros.
var _rebuild: Dictionary = {}
var _materials := {}
var _unit_box := BoxMesh.new()
var _track_slab: ArrayMesh
var _elapsed := 0.0
var _campaign_completed := false
var _gate: Node3D
var _source_roads: Array[Dictionary] = []
var _clearance_regions: Dictionary = {}
var _clearance_changed := false
var _clearance_buildings: Array = []
var _batches: Dictionary = {}
var _batch_parent: Node3D
var _body: StaticBody3D
const CORRIDOR_CELL := 8.0
var _corridor_cells: Dictionary = {}

const STATION_COLUMN_X := 6.45
## Folga das colunas de estação até a rua. A rodovia da serra é desenhada ~6 m mais larga que a largura
## cadastrada (map2_highway_outbound); com a folga comum de 2,8 m a coluna da Northgate caía na última
## faixa. Sem folga, a plataforma fica só no viaduto, em balanço.
const STATION_ROAD_MARGIN := 9.0

func configure(owner_controller) -> void:
	controller = owner_controller
	name = "RailwayWorld"
	_prepare_descriptors()
	_prepare_clearance_roads()

func _ready() -> void:
	if _descriptors.is_empty(): _prepare_descriptors()
	if controller != null and is_instance_valid(controller.world.player):
		set_focus(controller.world.player.global_position)

func _process(delta: float) -> void:
	# Build one short chunk per frame. Station/tunnel instances are independent
	# so their support is complete before admitting a passenger.
	if not _pending.is_empty():
		var key: Vector2i = _pending.pop_front()
		if _rebuild.has(key) and chunks.has(key):
			_rebuild.erase(key)
			var old: Node3D = chunks[key]
			chunks.erase(key)
			var rebuild_began := STALL_WORK.begin()
			_build_chunk(key)
			GPU_RELEASE.retire(old)
			STALL_WORK.finish("railway.chunk_rebuild", rebuild_began, {"key":str(key)})
		elif not chunks.has(key):
			var chunk_began := STALL_WORK.begin()
			_build_chunk(key)
			STALL_WORK.finish("railway.chunk", chunk_began, {"key":str(key)})
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL: return
	_elapsed = 0.0
	if controller == null or not is_instance_valid(controller.world.player): return
	var began := STALL_WORK.begin()
	_prepare_clearance_roads()
	STALL_WORK.finish_slow("railway.clearance_roads", began, 2000, self)
	if _clearance_changed:
		_clearance_changed = false
		began = STALL_WORK.begin()
		_recheck_supports()
		STALL_WORK.finish_slow("railway.recheck_supports", began, 2000, self)
	if controller.session != null:
		var railway = controller.session.get("railway")
		if is_instance_valid(railway) and (bool(railway.get("landing")) or bool(railway.get("_boarding"))): return
	var next_focus: Vector3 = controller.world.player.global_position
	if not controller.state.place_id.is_empty() and controller.session != null:
		next_focus = controller.session.return_point
	set_focus(next_focus)
	var campaign := preload("res://world/north_gateway/NorthGatewayPolicy.gd")
	set_campaign_completed(campaign.campaign_completed(controller.state.campaign.snapshot()))

func set_focus(point: Vector3) -> void:
	if not point.is_finite(): return
	focus = point
	for key: Vector2i in _descriptors:
		var center := Vector3((key.x+0.5)*CELL,point.y,(key.y+0.5)*CELL)
		var distance := point.distance_to(center)
		if distance < LOAD_DISTANCE and not chunks.has(key) and key not in _pending: _pending.append(key)
		elif distance > RELEASE_DISTANCE:
			_pending.erase(key)
			_rebuild.erase(key)
			if chunks.has(key):
				# Descarte gradual: o trecho tem ~50 MultiMesh e centenas de colisões (16/10).
				GPU_RELEASE.retire(chunks[key])
				chunks.erase(key)
	_pending.sort_custom(func(a: Vector2i,b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(Vector2(point.x,point.z)/CELL) < Vector2(b).distance_squared_to(Vector2(point.x,point.z)/CELL))
	for station in NETWORK.stations():
		var distance: float = point.distance_to(station.position)
		if distance < 180.0: ensure_station(station.id)
		elif distance > 240.0 and station_nodes.has(station.id):
			GPU_RELEASE.retire(station_nodes[station.id])
			station_nodes.erase(station.id)
	for tunnel in NETWORK.tunnels():
		var nearest := Geometry3D.get_closest_point_to_segment(point,tunnel.a,tunnel.b)
		var distance := point.distance_to(nearest)
		if distance < 220.0 and not tunnel_nodes.has(tunnel.id): _build_tunnel(tunnel)
		elif distance > 280.0 and tunnel_nodes.has(tunnel.id):
			GPU_RELEASE.retire(tunnel_nodes[tunnel.id])
			tunnel_nodes.erase(tunnel.id)
	if point.distance_to(NETWORK.GATE_POSITION) < 220.0 and not is_instance_valid(_gate): _build_gate()
	elif point.distance_to(NETWORK.GATE_POSITION) > 280.0 and is_instance_valid(_gate):
		GPU_RELEASE.retire(_gate)
		_gate = null

func ensure_station(id: String) -> Node3D:
	if station_nodes.has(id): return station_nodes[id]
	var station := NETWORK.get_station(id)
	if station.is_empty(): return null
	var result := _build_station(station)
	station_nodes[id] = result
	# Entry and platform must have their neighbouring rail floor available now.
	for key: Vector2i in _descriptors:
		var center := Vector2(key)*CELL+Vector2.ONE*CELL*.5
		if center.distance_to(Vector2(station.position.x,station.position.z)) < 80.0 and not chunks.has(key):
			_pending.erase(key)
			_build_chunk(key)
	return result

func get_station_node(id: String) -> Node3D: return station_nodes.get(id)
static func approach_path(id: String) -> PackedVector3Array: return NETWORK.approach_path(id)

func set_campaign_completed(completed: bool) -> void:
	if completed == _campaign_completed: return
	_campaign_completed = completed
	if is_instance_valid(_gate):
		GPU_RELEASE.retire(_gate)
		_gate = null
	if focus.is_finite() and focus.distance_to(NETWORK.GATE_POSITION) < 220.0: _build_gate()

func debug_snapshot() -> Dictionary:
	var lights := 0
	for station: Node3D in station_nodes.values(): lights += station.get_meta("light_count",0)
	for tunnel: Node3D in tunnel_nodes.values(): lights += tunnel.get_meta("light_count",0)
	return {"chunks":chunks.size(), "queued_chunks":_pending.size(), "stations":station_nodes.size(),
		"tunnels":tunnel_nodes.size(), "lights":lights, "campaign_completed":_campaign_completed,
		"gate_closed":is_instance_valid(_gate) and not _campaign_completed}

func _prepare_descriptors() -> void:
	if not _descriptors.is_empty(): return
	var seen := {}
	for edge in NETWORK.edges():
		var points: PackedVector3Array = edge.points
		for index in range(1,points.size()):
			var a := points[index-1]
			var b := points[index]
			var identity := str(a.snapped(Vector3.ONE*.01))+":"+str(b.snapped(Vector3.ONE*.01))
			if seen.has(identity): continue
			seen[identity] = true
			_add_descriptor(a,b,index % 6 == 2,edge.id)
	# Every terminal has enough rail beyond its stop for the powered unit and
	# buffers. These are not passenger routes or walkable region shortcuts.
	for station in NETWORK.stations():
		if station.region == "harbor": continue
		var point: Vector3 = station.position
		var direction := 1.0 if station.id=="harbor_central" else -1.0
		_add_descriptor(point,point+Vector3(0,0,18*direction),false,"terminal")

func _add_descriptor(a: Vector3,b: Vector3,pillar: bool,id: String) -> void:
	_corridor_cells = {}
	var center: Vector3 = (a + b) * 0.5
	var key := Vector2i(floori(center.x/CELL),floori(center.z/CELL))
	if not _descriptors.has(key): _descriptors[key] = []
	_descriptors[key].append({"a":a,"b":b,"pillar":pillar,"id":id})

func _prepare_clearance_roads() -> void:
	# Prepared regions include edits, pathways and secondary activities. Source
	# fallback is only for isolated geometry previews without ProductionWorld.
	if controller != null:
		var regions: Dictionary = controller._region_cache.duplicate()
		regions.merge(controller.regions,true)
		if regions == _clearance_regions: return
		_clearance_regions = regions
		_source_roads.clear()
		_clearance_buildings.clear()
		_clearance_changed = true
		for region in regions.values():
			for road in region.roads: _source_roads.append(road)
			# Pegadas dos prédios para _pillar_clear, montadas só quando as regiões mudam
			# (antes cada pilar duplicava e mesclava o cache de regiões de novo).
			for building in region.buildings:
				var p: Vector3 = building.position
				_clearance_buildings.append([Vector2(p.x,p.z), building.size*.5+Vector2.ONE*2])
			if region.get("walkways") is Array:
				for road in region.walkways: _source_roads.append(road)
	if _source_roads.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
		for road in data.harbor_roads:
			var points := PackedVector3Array()
			for point in road.points: points.append(Vector3(point[0],0,point[1])/16.0)
			_source_roads.append({"points":points,"width":float(road.width)/16.0})
		_source_roads.append_array(preload("res://world/desert/DesertLayout.gd").roads())

func _recheck_supports() -> void:
	# A neighbouring region can finish preparation after a nearby chunk was
	# built. Rebuild only groups whose existing columns now occupy a road.
	# Trechos entram na fila de construção (um por quadro, o velho fica até o novo existir): refeitos
	# todos de uma vez, quando a região do outro lado da ponte terminava de preparar, eram centenas de
	# colisões e dezenas de MultiMesh num quadro só (rastreio da travessia, 16/10).
	for key in chunks.keys():
		if not _rebuild.has(key) and not _supports_clear(chunks[key]):
			_rebuild[key] = true
			_pending.erase(key)
			_pending.push_front(key)
	# Estação refaz já: o embarque precisa do apoio completo.
	for id in station_nodes.keys():
		if not _supports_clear(station_nodes[id]):
			GPU_RELEASE.retire(station_nodes[id])
			station_nodes.erase(id)
			ensure_station(id)

func _supports_clear(group: Node3D) -> bool:
	for point: Vector3 in group.get_meta("support_points", []):
		if not _pillar_clear(point): return false
	return true

func _record_support(point: Vector3) -> void:
	var points: Array = _batch_parent.get_meta("support_points", [])
	points.append(point)
	_batch_parent.set_meta("support_points", points)

func _pillar_clear(point: Vector3, road_margin := 2.8) -> bool:
	_prepare_clearance_roads()
	var planar := Vector2(point.x,point.z)
	# The elevated rail may pass over the forge yard, but a bridge pier must never
	# occupy the yard or the walk to the workshop below it.
	if preload("res://world/mountain_detail/forge/MountainForge.gd").FOOTPRINT.grow(2.0).has_point(planar): return false
	# As rampas abertas do túnel do canal descem abaixo da rua: um pilar de 1,2 m
	# plantado no nível da rua ali cai no meio da pista na saída do túnel.
	if preload("res://world/urban_detail/CanalTunnel3D.gd").reserves(planar,2.0): return false
	for road in _source_roads:
		var points: PackedVector3Array = road.points
		var radius := float(road.width)*.5+road_margin
		for index in range(1,points.size()):
			var a := Vector2(points[index-1].x,points[index-1].z)
			var b := Vector2(points[index].x,points[index].z)
			if Geometry2D.get_closest_point_to_segment(planar,a,b).distance_to(planar) < radius: return false
	if controller != null:
		for footprint in _clearance_buildings:
			var center: Vector2 = footprint[0]
			var half: Vector2 = footprint[1]
			if absf(center.x-point.x)<half.x and absf(center.y-point.z)<half.y: return false
	return true

func _new_group(label: String) -> Node3D:
	var group := Node3D.new()
	group.name = label
	group.add_to_group("railway_geometry")
	add_child(group)
	_batch_parent = group
	_batches = {}
	_body = StaticBody3D.new()
	_body.name = "RailwaySolids"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.add_to_group("railway_solid")
	group.add_child(_body)
	return group

func _build_chunk(key: Vector2i) -> void:
	var group := _new_group("RailChunk_%d_%d" % [key.x,key.y])
	# Reuse the camera's local glass window for rails, deck and supports.
	# The shared shader reveals only geometry between the target and camera.
	group.add_to_group("exterior_reveal_building")
	chunks[key] = group
	for segment in _descriptors.get(key,[]):
		var a: Vector3 = segment.a
		var b: Vector3 = segment.b
		# The first 18m of existing approaches already have their rails. Only
		# build the extension beyond the actual terminus, avoiding coplanar ties.
		if segment.id == "terminal_overlap": continue
		var length := a.distance_to(b)
		var direction := (b-a).normalized()
		var right := direction.cross(Vector3.UP).normalized()
		var center := (a+b)*.5
		_beam(a-Vector3.UP*.42,b-Vector3.UP*.42,6.8,.7,"concrete_track",true)
		_beam(a-Vector3.UP*.085,b-Vector3.UP*.085,3.4,.12,"ballast")
		for side in [-1.0,1.0]:
			_beam(a+right*.72*side+Vector3.UP*.09,b+right*.72*side+Vector3.UP*.09,.09,.12,"rail")
			_beam(a+right*3.18*side-Vector3.UP*.37,b+right*3.18*side-Vector3.UP*.37,.16,.58,"steel")
			# Low parapets have a real upper handrail, keeping actors on the
			# elevated maintenance edge without obscuring the passing landscape.
			if not _beside_platform(center,side*right.x) and not _junction_clearance(a+right*3.30*side,b+right*3.30*side):
				_beam(a+right*3.30*side+Vector3.UP*.47,b+right*3.30*side+Vector3.UP*.47,.10,1.02,"fence",true)
		var sleepers := maxi(1,ceili(length/1.8))
		for index in sleepers:
			var t := (float(index)+.5)/float(sleepers)
			_box(a.lerp(b,t),Vector3(2.5,.09,.24),"sleeper",_basis(direction))
		var support := center
		var support_clear: bool = segment.pillar and _pillar_clear(support)
		# The new Foundry approach follows the sidewalk. Carry it from the
		# setback north of the sidewalk, with a short elevated cantilever.
		if segment.pillar and not support_clear and segment.id == "harbor_viaduct" and center.x < 145.0 and absf(center.z-20.0)<.01:
			support = center+Vector3(0,0,-2.5)
			support_clear = _pillar_clear(support)
		if support_clear:
			_record_support(support)
			var top := center.y-.77
			var bottom := -4.0 if center.x>200 and center.x<570 and center.z> -374 else -.4
			_box(Vector3(support.x,(top+bottom)*.5,support.z),Vector3(1.2,top-bottom,1.2),"concrete",Basis.IDENTITY,true)
			_box(Vector3(center.x,top-(.3 if support!=center else .4),center.z),Vector3(6.8 if support!=center else 3.8,.6,1.5),"concrete",_basis(direction),true)
	_flush_batches()

func _beside_platform(point: Vector3, side_x: float) -> bool:
	for station in NETWORK.stations():
		if absf(point.x-station.position.x)<1.0 and absf(point.z-station.position.z)<17.5:
			if signf(side_x) == float(station.side): return true
	return false

func _junction_clearance(a: Vector3,b: Vector3) -> bool:
	for fraction in [0.0,.25,.5,.75,1.0]:
		if _guard_inside_corridor(a.lerp(b,fraction)): return true
	return false

func _guard_inside_corridor(point: Vector3) -> bool:
	# Omit only a guard that actually enters another running corridor. The
	# outside perimeter, including Northgate, remains physically protected.
	if point.x<330.0 or point.x>475.0 or point.z> -184.0 or point.z< -280.0: return false
	# Só os trechos cuja caixa (+3 m) cobre a célula do ponto: mesmas regras de antes.
	# A varredura de todos os descritores por ponto custava 127 ms num trecho só
	# (142 testes de guarda) no export, 140–180 ms nos sobrados e na travessia (16/10).
	if _corridor_cells.is_empty(): _index_corridor()
	for row in _corridor_cells.get(_corridor_cell(point), []):
		if point.x<minf(row.a.x,row.b.x)-3.0 or point.x>maxf(row.a.x,row.b.x)+3.0: continue
		if point.z<minf(row.a.z,row.b.z)-3.0 or point.z>maxf(row.a.z,row.b.z)+3.0: continue
		if point.distance_to(Geometry3D.get_closest_point_to_segment(point,row.a,row.b))<3.0: return true
	return false

static func _corridor_cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x/CORRIDOR_CELL),floori(point.z/CORRIDOR_CELL))

## Índice espacial dos descritores para _guard_inside_corridor: cada trecho entra em
## toda célula que a caixa dele, com a folga de 3 m do teste, toca.
func _index_corridor() -> void:
	_corridor_cells = {}
	for rows in _descriptors.values():
		for row in rows:
			var low := _corridor_cell(Vector3(minf(row.a.x,row.b.x)-3.0,0,minf(row.a.z,row.b.z)-3.0))
			var high := _corridor_cell(Vector3(maxf(row.a.x,row.b.x)+3.0,0,maxf(row.a.z,row.b.z)+3.0))
			for x in range(low.x,high.x+1):
				for z in range(low.y,high.y+1):
					var cell := Vector2i(x,z)
					if not _corridor_cells.has(cell): _corridor_cells[cell] = []
					_corridor_cells[cell].append(row)
	# Marca índice pronto mesmo sem trecho algum, para não refazer a cada chamada.
	if _corridor_cells.is_empty(): _corridor_cells[Vector2i(1 << 30, 1 << 30)] = []

func _build_station(station: Dictionary) -> Node3D:
	var group := _new_group("Station_"+str(station.id))
	group.set_meta("station_id",station.id)
	group.add_to_group("railway_station")
	var origin: Vector3 = station.position
	var side := float(station.side)
	var floor_y := origin.y+NETWORK.PLATFORM_HEIGHT
	var accent := "pine" if station.region=="mountain" else "copper" if station.region=="desert" else "teal"
	_station_box(origin,side,Vector3(4.4,floor_y-.22,0),Vector3(4.8,.44,34),"platform",true)
	_station_box(origin,side,Vector3(2.12,floor_y+.014,0),Vector3(.28,.028,33.8),"warning")
	_station_box(origin,side,Vector3(2.38,floor_y+.024,0),Vector3(.08,.04,33.8),"ivory")
	# The outer guard leaves the upper stair bridge unobstructed.
	var access_z := .5 if station.region == "harbor" else -5.5
	var opening_start := access_z-1.35
	var opening_end := access_z+1.35
	for rail in [[(-17.0+opening_start)*.5,opening_start+17.0],[(opening_end+17.0)*.5,17.0-opening_end]]:
		_station_box(origin,side,Vector3(6.69,floor_y+.55,rail[0]),Vector3(.12,1.1,rail[1]),"fence",true)
	for end in [-17.0,17.0]:
		_station_box(origin,side,Vector3(4.4,floor_y+.55,end),Vector3(4.6,1.1,.12),"fence",true)
	for z in [-12.0,0.0,12.0]:
		_station_box(origin,side,Vector3(6.12,floor_y+1.65,z),Vector3(.18,3.3,.18),accent,true)
		_station_box(origin,side,Vector3(4.38,floor_y+3.27,z),Vector3(4.8,.18,.18),accent)
	# Two canopy wings and a central gap keep Dante visible from the gameplay
	# camera. Shelter, ticket machine and seats use a clear free central aisle.
	for z in [-10.0,10.0]:
		_station_box(origin,side,Vector3(4.38,floor_y+3.43,z),Vector3(5.35,.16,11.0),accent,true)
		_detail_station_canopy(origin,side,floor_y,z,accent)
		_station_box(origin,side,Vector3(4.38,floor_y+3.27,z),Vector3(.12,.07,8.4),"lamp")
		_station_box(origin,side,Vector3(5.45,floor_y+.45,z),Vector3(.68,.20,3.0),"wood",true)
		_station_box(origin,side,Vector3(5.76,floor_y+.84,z),Vector3(.12,.7,3.0),"wood",true)
		for leg_z in [-1.0,1.0]:
			_station_box(origin,side,Vector3(5.46,floor_y+.19,z+leg_z),Vector3(.44,.38,.12),"steel")
	_station_box(origin,side,Vector3(5.7,floor_y+.91,3.0),Vector3(.75,1.82,.55),accent,true)
	_station_box(origin,side,Vector3(5.29,floor_y+1.13,3.0),Vector3(.025,.51,.36),"screen")
	_station_box(origin,side,Vector3(5.27,floor_y+.67,3.0),Vector3(.02,.055,.21),"steel")
	_station_box(origin,side,Vector3(6.08,floor_y+2.67,0),Vector3(.15,.65,4.0),accent)
	var label := Label3D.new()
	label.name = "StationName"
	label.text = str(station.label)
	label.position = Vector3(origin.x+side*5.97,floor_y+2.68,origin.z)
	label.rotation.y = -PI*.5*side
	label.font_size = 42
	label.pixel_size = .009
	label.modulate = Color("ecebdf")
	label.outline_size = 0
	label.no_depth_test = false
	group.add_child(label)
	# Full-column support is only placed outside the street reservation.
	# Colunas na borda de fora da plataforma (6,45 m; ela vai até 6,8 m). Em 5,75 m a da Northgate descia
	# rente à última faixa da rodovia da serra e o carro dessa faixa passava por dentro dela (30/10).
	for z in [-15.0,15.0]:
		var foot := Vector3(origin.x+side*STATION_COLUMN_X,0,origin.z+z)
		if _pillar_clear(foot, STATION_ROAD_MARGIN):
			_record_support(foot)
			# Columns meet the underside, without a coplanar cap on the walking floor.
			_station_box(origin,side,Vector3(STATION_COLUMN_X,floor_y*.5-.52,z),Vector3(.6,floor_y+.16,.6),"concrete",true)
	_build_access(origin,side,floor_y,accent,station.region == "harbor")
	if station.id == "harbor_north":
		# A narrow supported landing joins the east sidewalk to the offshore stairs.
		_station_box(origin,side,Vector3(4.99,-.13,12.0),Vector3(5.75,.26,2.4),"platform",true)
		for x in [4.0,9.0,12.0]:
			_station_box(origin,side,Vector3(x,-2.0,12.0),Vector3(.6,4.0,.6),"concrete",true)
	_flush_batches()
	var light := OmniLight3D.new()
	light.position = Vector3(origin.x+side*4.4,floor_y+2.8,origin.z)
	light.light_color = Color("ffdec0")
	light.light_energy = 1.15
	light.omni_range = 18.0
	light.omni_attenuation = 1.8
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 48.0
	light.distance_fade_length = 22.0
	group.add_child(light)
	group.set_meta("light_count",1)
	return group

func _detail_station_canopy(origin: Vector3,side: float,floor_y: float,z: float,accent: String) -> void:
	# Standing seams and folded edges share the station's existing batches.
	# All dressing stays overhead; the original roof collider and central sight
	# opening remain unchanged, as do the platform, posts and boarding envelope.
	for index in 8:
		var x := 1.98 + float(index)*.68
		_station_box(origin,side,Vector3(x,floor_y+3.55,z),Vector3(.045,.08,10.82),accent)
		for end in [-5.24,5.24]:
			_station_box(origin,side,Vector3(x,floor_y+3.599,z+end),Vector3(.09,.018,.10),"rail")
	for x in [1.77,6.99]:
		_station_box(origin,side,Vector3(x,floor_y+3.40,z),Vector3(.14,.28,11.12),"steel",true)
		_station_box(origin,side,Vector3(x,floor_y+3.565,z),Vector3(.19,.055,11.18),accent)
	for end in [-5.52,5.52]:
		_station_box(origin,side,Vector3(4.38,floor_y+3.40,z+end),Vector3(5.36,.28,.13),accent,true)
		_station_box(origin,side,Vector3(4.38,floor_y+3.265,z+end),Vector3(5.36,.045,.15),"steel")
	# Open gutter: a low trough and raised lips make drainage readable from above.
	_station_box(origin,side,Vector3(7.10,floor_y+3.32,z),Vector3(.25,.045,11.08),"steel",true)
	_station_box(origin,side,Vector3(7.22,floor_y+3.38,z),Vector3(.045,.15,11.08),accent,true)
	for end in [-5.5,5.5]:
		_station_box(origin,side,Vector3(7.10,floor_y+3.38,z+end),Vector3(.25,.15,.045),accent)
	for x in [2.75,5.92]:
		_station_box(origin,side,Vector3(x,floor_y+3.22,z),Vector3(.13,.18,10.75),"steel",true)
	for offset in [-3.8,0.0,3.8]:
		_station_box(origin,side,Vector3(4.38,floor_y+3.10,z+offset),Vector3(5.16,.16,.14),"steel",true)
	var support_z := -12.0 if z < 0.0 else 12.0
	var a := Vector3(origin.x+side*6.12,floor_y+2.63,origin.z+support_z)
	var b := Vector3(origin.x+side*4.92,floor_y+3.20,origin.z+support_z)
	_beam(a,b,.10,.10,"steel",true)
	_station_box(origin,side,Vector3(6.12,floor_y+2.66,support_z),Vector3(.23,.24,.25),"steel",true)

func _build_access(origin: Vector3,side: float,floor_y: float,accent: String, compact := false) -> void:
	var rise := floor_y/3.0
	var far_z := 2.0 if compact else -4.0
	var landing_z := .5 if compact else -5.5
	var run := 10.0-far_z
	_station_box(origin,side,Vector3(10.65,-.10,11.5),Vector3(5.6,.20,5.5),"platform",true)
	for deck in [[rise,landing_z],[rise*2,11.5],[floor_y,landing_z]]:
		_station_box(origin,side,Vector3(10.65,deck[0]-.12,deck[1]),Vector3(5.5,.24,3.0),"platform",true)
		var edge_z: float = deck[1]+(-1.5 if deck[1]<5 else 1.5)
		_access_guard(Vector3(origin.x+side*7.9,deck[0],origin.z+edge_z),Vector3(origin.x+side*13.4,deck[0],origin.z+edge_z))
		for x in [8.0,13.3]:
			if is_equal_approx(float(deck[0]),floor_y) and x==8.0: continue
			_access_guard(Vector3(origin.x+side*x,deck[0],origin.z+deck[1]-1.5),Vector3(origin.x+side*x,deck[0],origin.z+deck[1]+1.5))
	for index in 3:
		var x := 12.0 if index!=1 else 9.3
		var start_z := 10.0 if index!=1 else far_z
		var end_z := far_z if index!=1 else 10.0
		var a := Vector3(origin.x+side*x,rise*index,origin.z+start_z)
		var b := Vector3(origin.x+side*x,rise*(index+1),origin.z+end_z)
		_ramp(a,b,2.12,"platform")
		var count := 25
		for step in count:
			var start := float(step)/float(count)
			var end := float(step+1)/float(count)
			var midpoint := a.lerp(b,(start+end)*.5)
			midpoint.y = lerpf(a.y,b.y,end)-.055
			# The final tread ends at the landing seam instead of sharing its top.
			_box(midpoint,Vector3(2.12,.11,run/count+(0.0 if step==count-1 else .008)),"concrete")
			var nose := a.lerp(b,end)
			nose.y += .006
			_box(nose,Vector3(2.04,.018,.045),"steel")
		for rail_side in [-1.0,1.0]:
			_access_guard(a+Vector3(rail_side*1.10,0,0),b+Vector3(rail_side*1.10,0,0))
			_beam(a+Vector3(rail_side*1.04,-.18,0),b+Vector3(rail_side*1.04,-.18,0),.14,.28,"steel")
	# Upper connection at the north end of the staircase, open on both sides.
	# Join only the gap: the platform and landing already own their top faces.
	_station_box(origin,side,Vector3(7.35,floor_y-.12,landing_z),Vector3(1.1,.24,2.7),"platform",true)
	for z in [landing_z-1.35,landing_z+1.35]:
		_access_guard(Vector3(origin.x+side*6.3,floor_y,origin.z+z),Vector3(origin.x+side*11.3,floor_y,origin.z+z))
	for x in [8.1,13.2]:
		for z in [landing_z-1.1,12.7]:
			_station_box(origin,side,Vector3(x,floor_y*.5-.12,z),Vector3(.18,floor_y-.24,.18),accent,true)
	# Functional ticket mast at ground level; proper station name is repeated
	# where a pedestrian approaches, without decorative descriptive text.
	_station_box(origin,side,Vector3(8.2,1.7,14.1),Vector3(.16,3.4,.16),accent,true)
	_station_box(origin,side,Vector3(8.2,3.2,14.1),Vector3(1.0,.70,.12),accent)

func _access_guard(a: Vector3,b: Vector3) -> void:
	# Open railing with continuous physical guard, not a tall opaque side wall.
	for height in [.16,.55,1.05]:
		_beam(a+Vector3.UP*height,b+Vector3.UP*height,.055,.055,"steel")
	var count := maxi(1,ceili(a.distance_to(b)/.85))
	for i in count+1:
		var point := a.lerp(b,float(i)/count)
		_box(point+Vector3.UP*.53,Vector3(.065,1.06,.065),"steel")
	var shape := BoxShape3D.new()
	shape.size = Vector3(.10,1.1,a.distance_to(b)+.02)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(_basis((b-a).normalized()),(a+b)*.5+Vector3.UP*.55)
	_body.add_child(collision)

func _station_box(origin: Vector3,side: float,local: Vector3,size: Vector3,material: String,solid := false) -> void:
	_box(Vector3(origin.x+local.x*side,local.y,origin.z+local.z),size,material,Basis.IDENTITY,solid)

func _build_tunnel(tunnel: Dictionary) -> void:
	var group := _new_group("Tunnel_"+str(tunnel.id))
	tunnel_nodes[tunnel.id] = group
	group.add_to_group("railway_tunnel")
	var a: Vector3 = tunnel.a
	var b: Vector3 = tunnel.b
	var direction := (b-a).normalized()
	var right := direction.cross(Vector3.UP).normalized()
	var frame := _basis(direction)
	var length := a.distance_to(b)
	var finish := "sandstone" if tunnel.region=="desert" else "rock"
	for side in [-1.0,1.0]:
		_beam(a+right*3.25*side+Vector3.UP*2.4,b+right*3.25*side+Vector3.UP*2.4,.60,5.9,"tunnel",true)
		_beam(a+right*2.93*side+Vector3.UP*.6,b+right*2.93*side+Vector3.UP*.6,.08,.17,"warning")
	_beam(a+Vector3.UP*6.10,b+Vector3.UP*6.10,7.1,.45,"tunnel",true)
	# Irregular sloping shoulders meet the existing floor without editing it;
	# the portals retain the concrete liner and a visible open clearance box.
	preload("res://world/railway/RailwayTunnelRidge.gd").build(group,a,b,_material(finish))
	# Articulated portal stonework frames the actual hollow passage.
	for end in [a,b]:
		for side in [-1.0,1.0]:
			_box(end+right*3.5*side+Vector3.UP*2.9,Vector3(1.0,6.5,1.1),finish,frame,true)
		_box(end+Vector3.UP*6.13,Vector3(8.0,.75,1.2),finish,frame,true)
		_box(end+Vector3.UP*6.58,Vector3(8.7,.16,1.45),"concrete",frame)
	for step in range(0,ceili(length/7.0)+1):
		var point := a.lerp(b,clampf(float(step)*7.0/length,0,1))
		for side in [-1.0,1.0]:
			_box(point+right*2.91*side+Vector3.UP*2.7,Vector3(.10,5.2,.16),"steel",frame)
		_box(point+Vector3.UP*5.83,Vector3(5.8,.12,.16),"steel",frame)
		_box(point+Vector3.UP*5.70,Vector3(2.0,.07,.28),"lamp",frame)
	_flush_batches()
	for t in [.24,.76]:
		var light := OmniLight3D.new()
		light.position = a.lerp(b,t)+Vector3.UP*4.3
		light.light_color = Color("ffdfb6")
		light.light_energy = 2.0
		light.omni_range = 23.0
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 60.0
		light.distance_fade_length = 22.0
		group.add_child(light)
	group.set_meta("light_count",2)

func _build_gate() -> void:
	_gate = _new_group("CampaignRailGate")
	_gate.set_meta("requires_act1",true)
	var point := NETWORK.GATE_POSITION
	for side in [-1.0,1.0]:
		_box(point+Vector3(side*3.8,2.8,0),Vector3(.5,6.2,.6),"steel",Basis.IDENTITY,true)
	_box(point+Vector3(0,5.9,0),Vector3(8.1,.45,.6),"steel",Basis.IDENTITY,true)
	if not _campaign_completed:
		_box(point+Vector3(0,2.6,0),Vector3(7.7,5.8,.30),"gate",Basis.IDENTITY,true)
		for y in [.8,2.6,4.4]:
			_box(point+Vector3(0,y,.19),Vector3(7.7,.22,.04),"warning")
		for x in [-3.0,-1.0,1.0,3.0]:
			_box(point+Vector3(x,5.7,.25),Vector3(.22,.14,.12),"red_lamp")
	_flush_batches()

func _basis(direction: Vector3) -> Basis:
	var right := direction.cross(Vector3.UP).normalized()
	return Basis(right,right.cross(direction).normalized(),-direction)

func _beam(a: Vector3,b: Vector3,width: float,height: float,material: String,solid := false) -> void:
	_box((a+b)*.5,Vector3(width,height,a.distance_to(b)+.016),material,_basis((b-a).normalized()),solid)

func _box(point: Vector3,size: Vector3,material: String,orientation := Basis.IDENTITY,solid := false) -> void:
	if not _batches.has(material): _batches[material] = []
	_batches[material].append(Transform3D(orientation * Basis.from_scale(size),point))
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = Transform3D(orientation,point)
		_body.add_child(collision)

func _ramp(a: Vector3,b: Vector3,width: float,material: String) -> void:
	var right := Vector3.RIGHT*width*.5
	var points := PackedVector3Array([a-right,a+right,b-right,b+right,
		a-right-Vector3.UP*.22,a+right-Vector3.UP*.22,b-right-Vector3.UP*.22,b+right-Vector3.UP*.22])
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	_body.add_child(collision)
	_beam(a-Vector3.UP*.14,b-Vector3.UP*.14,width,.25,material)

func _flush_batches() -> void:
	for material: String in _batches:
		var rows: Array = _batches[material]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _unit_box
		if material == "concrete_track":
			if _track_slab == null:
				_track_slab = preload("res://world/urban_detail/SlabVisibleFaces.gd").box_with_top_opening(Vector3.ONE,Rect2(-.25,-.5,.5,1.0))
			multi.mesh = _track_slab
		multi.instance_count = rows.size()
		for index in rows.size(): multi.set_instance_transform(index,rows[index])
		var instance := MultiMeshInstance3D.new()
		instance.name = material.capitalize()
		instance.multimesh = multi
		instance.material_override = _material("concrete" if material == "concrete_track" else material)
		if material in ["rail","warning","lamp","screen","red_lamp"]:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_batch_parent.add_child(instance)
	_batches = {}
	_batch_parent = null
	_body = null

func _material(id: String) -> StandardMaterial3D:
	if _materials.has(id): return _materials[id]
	var colors := {"concrete":"8a918c","ballast":"4b514c","rail":"a2aaab","sleeper":"6d7267",
		"steel":"3c4c50","fence":"566365","platform":"b8b5a4","warning":"d4ad49",
		"ivory":"e1ddc7","teal":"275a59","pine":"58513c","copper":"935e3d",
		"wood":"8b7050","screen":"7aa8a3","lamp":"edc78d","red_lamp":"e15935",
		"tunnel":"777a72","rock":"71766e","sandstone":"a58a67","gate":"786e58"}
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(colors.get(id,"868c84"))
	material.roughness = .88
	# Pilares, trilho e lastro liam como plano chapado (textura de grão fraca ou
	# nenhuma): relevo + rugosidade em espaço de mundo, mantendo o tom da paleta.
	var detail_kinds := {"concrete":"concrete","ballast":"gravel","sleeper":"wood","tunnel":"concrete",
		"rock":"granite","sandstone":"plaster","rail":"metal","steel":"metal","fence":"metal",
		"gate":"wood","teal":"metal","copper":"metal","pine":"wood"}
	if detail_kinds.has(id):
		var tint := material.albedo_color
		preload("res://assets/urban_detail/UrbanSurfaces.gd").detail(material, detail_kinds[id], 1.2 if id in ["rail","steel","fence","ballast","sleeper"] else 2.0, .9)
		material.albedo_color = Color(minf(tint.r * material.albedo_color.r, 1.0), minf(tint.g * material.albedo_color.g, 1.0), minf(tint.b * material.albedo_color.b, 1.0))
		material.roughness = 1.0
	elif id in ["platform","wood"]:
		var kind := "wood" if id=="wood" else "stone" if id=="platform" else "rail_grain"
		material.albedo_texture = preload("res://world/places/ShopInteriorMaterials.gd").texture(kind)
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE*(.65 if id=="platform" else 1.4)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if id in ["rail","steel","fence"]:
		material.metallic = .62
		material.roughness = .43 if id=="rail" else .67
	if id in ["lamp","screen","red_lamp"]:
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 1.4 if id=="lamp" else .55
	_materials[id] = material
	return material
