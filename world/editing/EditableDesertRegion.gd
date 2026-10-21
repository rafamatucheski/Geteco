extends "res://world/desert/DesertRegion.gd"
## Same production scenery and streaming, with constructor-time editor overrides.
const EDIT_DATA := preload("res://world/editing/WorldEditData.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const UNITS := preload("res://world/editing/WorldUnits.gd")
var edit_changes: Dictionary = {}
## Peças que alguém copiou: precisam virar grupo mesmo sem edição própria.
var clone_sources: Dictionary = {}
## Destino -> origens (ver WorldUnits.pull_map).
var _pull: Dictionary = {}

func _ready() -> void:
	if not Engine.get_meta("geteco_live_preview_build",false):
		super._ready()
		return
	prepare_data()
	prepared = true
	_horizon = preload("res://world/desert/DesertHorizon.gd").build()
	add_child(_horizon)
	if not initial_prewarm_only: set_focus(initial_focus if initial_focus.is_finite() else spawn_position)

static func build_region(_id := "desert", first_focus := Vector3.INF) -> Node3D:
	var result = load("res://world/editing/EditableDesertRegion.gd").new()
	result.initial_focus = first_focus
	return result

static func piece_key(record: Dictionary) -> String:
	return "desert/"+str(record.kind)+"/"+PIECES.record_key(record)

static func editable_record(_record: Dictionary) -> bool:
	# Antes só casas, caixa d'água, banco e caminhão eram livres; poste, fio, luz e o resto
	# seguiam protegidos. Agora tudo se move: o visual vai, âncoras de missão ficam onde estão.
	return true

func prepare_data() -> void:
	if data_prepared: return
	super.prepare_data()
	var loaded := EDIT_DATA.read_document()
	if not loaded.error.is_empty(): push_error(loaded.error); return
	var document: Dictionary = Engine.get_meta("geteco_world_edit_document",loaded.document)
	edit_changes = document.get("regions",{}).get("desert",{})
	if edit_changes.is_empty(): return
	_apply_road_edits()
	_pull = UNITS.pull_map("desert",edit_changes,CELL)
	for id in edit_changes:
		if str(edit_changes[id].get("clone_of","")) != "" and not edit_changes[id].get("deleted",false): clone_sources[str(edit_changes[id].clone_of)] = true
	# Move the owning record too: edits must survive unloading the original cell.
	var moved: Array[Dictionary] = []
	for cell in records:
		var kept: Array = []
		for record in records[cell]:
			var change: Dictionary = edit_changes.get("piece/"+piece_key(record),{})
			if editable_record(record) and not change.is_empty():
				if record.kind == "building":
					for building in buildings:
						if building.id != record.data.id: continue
						building.position = EDIT_DATA.xyz(change.get("position",EDIT_DATA.xy(record.data.position)))
						var stretch := EDIT_DATA.point(change.get("stretch",[1,1]))
						building.size *= stretch
						# Reserve the rotated footprint for scenery/actor consumers.
						var angle := deg_to_rad(float(change.get("rotation",0)))
						var size: Vector2 = building.size
						building.size = Vector2(absf(cos(angle))*size.x+absf(sin(angle))*size.y,absf(sin(angle))*size.x+absf(cos(angle))*size.y)
					if change.get("deleted",false): buildings = buildings.filter(func(b): return b.id!=record.data.id)
				if change.get("deleted",false): continue
				if _cell(EDIT_DATA.xyz(change.position)) != cell:
					moved.append({"record":record,"position":EDIT_DATA.xyz(change.position)})
					continue
			kept.append(record)
		records[cell] = kept
	for item in moved: _record(item.position,item.record)
	for id in edit_changes:
		var row: Dictionary = edit_changes[id]
		if not str(id).begins_with("new/") or row.get("deleted",false): continue
		if row.type not in ["prop","tree","building","ground","light"]: continue
		if row.type == "building":
			var size := EDIT_DATA.point(row.size)
			var angle := deg_to_rad(float(row.rotation))
			var footprint := Vector2(absf(cos(angle))*size.x+absf(sin(angle))*size.y,absf(sin(angle))*size.x+absf(cos(angle))*size.y)
			buildings.append({"id":row.id,"name":"","position":EDIT_DATA.xyz(row.position),"size":footprint,"height":float(row.height)})
		_record(EDIT_DATA.xyz(row.position),{"kind":"editor_added","data":row})

func _build_record(chunk: Node3D, record: Dictionary) -> void:
	if edit_changes.is_empty() and not Engine.get_meta("geteco_live_preview_build",false):
		super._build_record(chunk,record)
		return
	if record.kind == "editor_added":
		_build_added(chunk,record.data)
		return
	var key := piece_key(record)
	var preview := bool(Engine.get_meta("geteco_live_preview_build",false))
	if not preview and not edit_changes.has("piece/"+key) and not clone_sources.has("piece/"+key):
		super._build_record(chunk,record)
		return
	var before := chunk.get_child_count()
	super._build_record(chunk,record)
	var children := chunk.get_children().slice(before)
	if children.is_empty(): return
	var group := PIECES.group(chunk,children,key,str(record.kind).capitalize(),not editable_record(record))
	if record.kind == "building":
		var transforms: Array[Transform3D] = []
		for child in group.get_children(): transforms.append(child.global_transform)
		group.global_position = record.data.position
		for i in group.get_child_count(): group.get_child(i).global_transform = transforms[i]
	var source_ground := _ground_height(Vector2(group.global_position.x,group.global_position.z))
	PIECES.spawn_clones(group,edit_changes,_ground_height)
	PIECES.apply_one(group,edit_changes)
	if is_instance_valid(group) and editable_record(record) and edit_changes.has("piece/"+key):
		group.global_position.y += _ground_height(Vector2(group.global_position.x,group.global_position.z))-source_ground

func _build_added(chunk: Node3D,row: Dictionary) -> void:
	var node: Node3D
	match str(row.type):
		"prop": node = preload("res://world/editing/WorldPropFactory.gd").create(row)
		"tree":
			node = preload("res://world/regions/NativePine.gd").create(int(row.variant),row.snow)
			node.scale = Vector3.ONE*float(row.scale)
			preload("res://world/editing/WorldPropFactory.gd").solid(node,Vector3(0,1.4,0),Vector3(.4,2.8,.4))
		"building":
			var data := {"id":row.id,"kind":row.model,"size":EDIT_DATA.point(row.size),"height_override":float(row.height),"color":row.color,"position":Vector3.ZERO}
			node = preload("res://world/urban_detail/UrbanBuildingFactory.gd").build_building(data)
		"ground":
			var ground := preload("res://world/editing/WorldGroundFactory.gd")
			node = ground.create(row,ground.bounds(row),_ground_height)
		"light":
			preload("res://world/editing/WorldEditRuntime.gd").build_light(self,chunk,{"data":row,"position":EDIT_DATA.xyz(row.position)})
			var lamp := chunk.get_child(chunk.get_child_count()-1) as Node3D
			lamp.position.y = _ground_height(EDIT_DATA.point(row.position))
			return
	if node == null: return
	node.set_meta("editor_id",row.id)
	chunk.add_child(node)
	if row.type != "ground":
		node.position = EDIT_DATA.xyz(row.position)
		node.position.y = _ground_height(EDIT_DATA.point(row.position))
		node.rotation.y = deg_to_rad(float(row.rotation))

## Chunk pronto: pedras, cactos, relevo e ruínas (não são registros) viram peças editáveis.
func _process(delta: float) -> void:
	# An edited object's physical source is required by the destination, rather than
	# optional dressing behind the drag strip's large background residency queue.
	if not _pull.is_empty():
		var required := {}
		for target in _pull:
			if not chunks.has(target): continue
			for origin in _pull[target]: required[origin] = true
		for origin in required:
			if not chunks.has(origin) and not _surface_jobs.has(origin):
				pending.erase(origin)
				pending.push_front(origin)
		for index in build_jobs.size():
			if required.has(build_jobs[index].key):
				var urgent: Dictionary = build_jobs[index]
				build_jobs.remove_at(index)
				build_jobs.push_front(urgent)
				break
	super._process(delta)

func _trim_chunks() -> void:
	if _pull.is_empty():
		super._trim_chunks()
		return
	var borrowed: Array[Vector2i] = []
	for target in _pull:
		if not chunks.has(target): continue
		for origin in _pull[target]:
			if not vehicle_support_cells.has(origin):
				vehicle_support_cells[origin] = true
				borrowed.append(origin)
	super._trim_chunks()
	for origin in borrowed: vehicle_support_cells.erase(origin)

func _run_build_job(job: Dictionary, budget: float) -> void:
	if edit_changes.is_empty() and not UNITS.preview_active():
		super._run_build_job(job,budget)
		return
	var chunk: Variant = chunks.get(job.key)
	super._run_build_job(job,budget)
	if is_instance_valid(chunk) and not build_jobs.has(job) and not job.get("units_done",false):
		job.units_done = true
		for origin in _pull.get(job.key,[]):
			if not chunks.has(origin) and origin not in pending: pending.append(origin)
		UNITS.finalize_chunk(self,chunk,job.key,edit_changes,_ground_height)

## Vias do deserto: mexe nos traçados antes de qualquer consumidor (geometria, tráfego, mapa) ler
## `roads`. Vias novas entram como asfalto ou terra com tráfego.
func _apply_road_edits() -> void:
	var touched := false
	for id in edit_changes:
		var row: Dictionary = edit_changes[id]
		if row.get("type","") != "road": continue
		var road_id := str(id).trim_prefix("road/")
		var index := -1
		for i in roads.size():
			if str(roads[i].id) == road_id: index = i
		if row.get("deleted",false):
			if index >= 0: roads.remove_at(index)
			touched = true
			continue
		var points := PackedVector3Array()
		for point in row.points:
			var planar := Vector2(float(point[0]),float(point[1]))
			points.append(Vector3(planar.x,LAYOUT.surface_height(planar),planar.y))
		var surface := "dirt" if str(row.get("surface","asphalt")) == "earth" else "asphalt"
		if index >= 0:
			roads[index].points = points
			roads[index].width = float(row.width)
			roads[index].surface = surface
		else:
			roads.append({"id":road_id,"points":points,"width":float(row.width),"traffic":true,"region":"desert","surface":surface,"one_way":false})
		touched = true
	if touched: road_geometry.configure(roads)
