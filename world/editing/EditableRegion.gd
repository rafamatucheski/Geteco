extends "res://world/regions/NativeRegion.gd"
## Production adapter. The original generator remains untouched for concurrent work.
const EDITS := preload("res://world/editing/WorldEditRuntime.gd")
const EDIT_DATA := preload("res://world/editing/WorldEditData.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const UNITS := preload("res://world/editing/WorldUnits.gd")
var _piece_changes: Dictionary = {}
## Destino -> origens: peça de chunk movida para outra célula precisa do chunk de origem vivo.
var _pull: Dictionary = {}

static func build_region(id: String, first_focus: Vector3 = Vector3.INF) -> Node3D:
	if id == "desert":
		var desert_script = load("res://world/editing/EditableDesertRegion.gd")
		return desert_script.build_region(id,first_focus) if desert_script!=null and desert_script.can_instantiate() else null
	if id not in ["harbor", "mountain"]: return null
	var region = load("res://world/editing/EditableRegion.gd").new()
	region.region_id = id
	region.initial_focus = first_focus
	return region

func prepare_data() -> void:
	super.prepare_data()
	# Reserve only validated pull-offs before streamed sidewalk props are built.
	if "--parking-baseline" not in OS.get_cmdline_user_args():
		preload("res://world/roadside_parking/RoadsideParkingLayout.gd").prepare(self)

func _prepare() -> void:
	super._prepare()
	if region_id == "harbor":
		_record(Vector3(-176,0,-96),{"kind":"motocross_course","position":Vector3(-176,0,-96)})
	var loaded := EDIT_DATA.read_document()
	if not loaded.error.is_empty():
		push_error("Editor de mundo: " + loaded.error)
		return
	var doc: Dictionary = Engine.get_meta("geteco_world_edit_document", loaded.document)
	if doc.get("regions", {}).get(region_id, {}).is_empty(): return
	EDITS.apply(self)
	for key in doc.regions[region_id]:
		var row: Dictionary = doc.regions[region_id][key]
		if row.get("type", "") == "piece": _piece_changes[key] = row
	if not _piece_changes.is_empty():
		PIECES.prepare(self,_piece_changes)
		_pull = UNITS.pull_map(str(region_id),_piece_changes,CELL)
	if region_id == "harbor":
		harbor_road_geometry.configure(roads)
		coastal_protection.configure(source_data, extra_land, harbor_road_geometry._layers[0].polygons)
	else:
		var terrain_roads: Array[Dictionary] = roads + walkways
		for avenue in source_data.harbor_roads:
			if avenue.id not in ["northbank_gateway_avenue", "eastgate_drive", "map2_highway_outbound"]: continue
			var points := PackedVector3Array()
			for p in avenue.points: points.append(CATALOG._at(Vector2(p[0],p[1]),"harbor"))
			terrain_roads.append({"id": avenue.id, "points": points, "width": float(avenue.width)*SCALE})
		terrain.configure(terrain_roads, CATALOG.definitions()+entries, EDITS.clearings(self)+[MOUNTAIN_ZOO.FOOTPRINT])

func _build_record(chunk: Node3D, record: Dictionary) -> void:
	var first_child := chunk.get_child_count()
	if record.kind == "motocross_course":
		chunk.add_child(preload("res://activities/motocross/MotocrossCourse.gd").new())
	elif record.kind == "roadside_parking":
		preload("res://world/roadside_parking/RoadsideParkingBay.gd").build(chunk,record.site)
	elif record.kind == "harbor_dressing" and record.get("zone_id", "") == "cobra":
		var dressing := preload("res://world/editing/EditableCobraDressing.gd").new()
		dressing.configure(record.zone_id)
		dressing.position = record.position
		chunk.add_child(dressing)
	elif record.kind == "editor_ground":
		var height := Callable(terrain,"surface_height_at") if terrain != null else Callable()
		var ground := preload("res://world/editing/WorldGroundFactory.gd").create(record.data,record.clip,height,record.get("masks",[]))
		if ground != null: chunk.add_child(ground)
	elif record.kind == "editor_prop":
		var prop: Node3D = preload("res://world/editing/WorldPropFactory.gd").create(record.data)
		prop.position = record.position
		if terrain != null: prop.position.y = terrain.surface_height_at(Vector2(prop.position.x,prop.position.z))
		chunk.add_child(prop)
	elif record.kind == "editor_light":
		EDITS.build_light(self, chunk, record)
	elif record.kind == "tree" and record.has("editor_id"):
		var tree = preload("res://world/regions/NativePine.gd").create(record.variant, record.snow)
		tree.position = record.position
		if terrain != null: tree.position.y = terrain.surface_height_at(Vector2(tree.position.x,tree.position.z))
		tree.scale = Vector3.ONE*float(record.editor_scale)
		tree.rotation.y = float(record.editor_rotation)
		tree.set_meta("editor_id", record.editor_id)
		chunk.add_child(tree)
		_tree_collision(tree,chunk)
	else:
		var before := chunk.get_child_count()
		super._build_record(chunk, record)
		if record.has("editor_id") and chunk.get_child_count() > before:
			var art: Node3D = chunk.get_child(before)
			art.rotation.y = float(record.get("editor_rotation",0.0))
			art.set_meta("editor_id",record.editor_id)

	if record.kind == "harbor_route_zone":
		for node in chunk.get_children().slice(first_child):
			preload("res://world/editing/EditableCobraDressing.gd").tag_route(node,record.zone_id)
	if Engine.get_meta("geteco_live_preview_build",false):
		var preview_id := str(record.get("editor_id",EDIT_DATA.record_id(record)))
		if not preview_id.is_empty():
			for node in chunk.get_children().slice(first_child):
				if not node.has_meta("editor_id"): node.set_meta("editor_id",preview_id)
	# Tudo que um registro constrói vira uma peça editável (ver WorldUnits). Só agrupa na prévia
	# ou quando o documento mexe nesse registro: sem edição o jogo não paga nada.
	if chunk.get_child_count() > first_child and (UNITS.preview_active() or record.has("editor_piece_ids")):
		if UNITS.record_eligible(record): UNITS.group_record(self,chunk,record,first_child)
		else:
			for node in chunk.get_children().slice(first_child): node.set_meta("world_unit_skip",true)
	if record.has("editor_piece_ids"):
		var ground := UNITS.ground_of(self)
		for node in chunk.get_children().slice(first_child):
			PIECES.apply(node,_piece_changes,ground)
			# A própria peça do registro pode ter sido excluída (apply a libera).
			if is_instance_valid(node): PIECES.filter_record(node,record)

func _building(chunk: Node3D, data: Dictionary) -> void:
	var before := chunk.get_child_count()
	super._building(chunk, data)
	if data.has("editor_id") and chunk.get_child_count() > before:
		var art: Node3D = chunk.get_child(before)
		art.rotation.y = float(data.editor_rotation)
		art.set_meta("editor_id", data.editor_id)
		if data.has("editor_service"):
			# NativeRegion mounts the original facade; deform it once, including
			# baked collision shapes, instead of rebuilding a generic replacement.
			art.rotation.y = 0
			preload("res://world/editing/WorldServiceBuildings.gd").apply_art(art,data.editor_service)

## Chunk pronto: o que ele construiu fora de registros (pedras, vegetação, mobiliário) vira
## peça editável. Sem edições nem prévia isto sai na primeira linha.
func _trim_chunks(cell: Vector2i) -> void:
	if _pull.is_empty():
		super._trim_chunks(cell)
		return
	var borrowed: Array[Vector2i] = []
	for target in _pull:
		if not chunks.has(target): continue
		for origin in _pull[target]:
			if not vehicle_support_cells.has(origin):
				vehicle_support_cells[origin] = true
				borrowed.append(origin)
	super._trim_chunks(cell)
	for origin in borrowed: vehicle_support_cells.erase(origin)

func _run_build_job(job: Dictionary, budget_usec: float) -> bool:
	var finished: bool = super._run_build_job(job,budget_usec)
	if finished and int(job.stage) >= 4 and _pull.has(job.key):
		for origin in _pull[job.key]:
			if not chunks.has(origin) and origin not in pending: pending.append(origin)
	if finished and int(job.stage) >= 4 and not job.get("units_done",false) and is_instance_valid(job.chunk):
		job.units_done = true
		UNITS.finalize_chunk(self,job.chunk,job.key,_piece_changes,UNITS.ground_of(self))
	return finished
