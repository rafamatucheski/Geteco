extends "res://world/desert/DesertRegion.gd"
## Same production scenery and streaming, with constructor-time editor overrides.
const EDIT_DATA := preload("res://world/editing/WorldEditData.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
var edit_changes: Dictionary = {}

static func build_region(_id := "desert", first_focus := Vector3.INF) -> Node3D:
	var result = load("res://world/editing/EditableDesertRegion.gd").new()
	result.initial_focus = first_focus
	return result

static func piece_key(record: Dictionary) -> String:
	return "desert/"+str(record.kind)+"/"+PIECES.record_key(record)

static func editable_record(record: Dictionary) -> bool:
	# Doorways, mission targets, race gates and connected utility lines keep their anchors.
	return record.kind in ["water_tower", "rest_bench", "bitrem"]

func prepare_data() -> void:
	if data_prepared: return
	super.prepare_data()
	var loaded := EDIT_DATA.read_document()
	if not loaded.error.is_empty(): push_error(loaded.error); return
	var document: Dictionary = Engine.get_meta("geteco_world_edit_document",loaded.document)
	edit_changes = document.get("regions",{}).get("desert",{})
	# Move the owning record too: edits must survive unloading the original cell.
	var moved: Array[Dictionary] = []
	for cell in records:
		var kept: Array = []
		for record in records[cell]:
			var change: Dictionary = edit_changes.get("piece/"+piece_key(record),{})
			if editable_record(record) and not change.is_empty():
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
		if row.type not in ["prop","tree","building","ground"]: continue
		_record(EDIT_DATA.xyz(row.position),{"kind":"editor_added","data":row})

func _build_record(chunk: Node3D, record: Dictionary) -> void:
	if record.kind == "editor_added":
		_build_added(chunk,record.data)
		return
	var key := piece_key(record)
	var preview := bool(Engine.get_meta("geteco_live_preview_build",false))
	if not preview and not edit_changes.has("piece/"+key):
		super._build_record(chunk,record)
		return
	var before := chunk.get_child_count()
	super._build_record(chunk,record)
	var children := chunk.get_children().slice(before)
	if children.is_empty(): return
	var group := PIECES.group(chunk,children,key,str(record.kind).capitalize(),not editable_record(record))
	PIECES.apply(group,edit_changes)

func _build_added(chunk: Node3D,row: Dictionary) -> void:
	var node: Node3D
	match str(row.type):
		"prop": node = preload("res://world/editing/WorldPropFactory.gd").create(row)
		"tree":
			node = preload("res://world/regions/NativePine.gd").create(int(row.variant),row.snow)
			node.scale = Vector3.ONE*float(row.scale)
		"building":
			var data := {"id":row.id,"kind":row.model,"size":EDIT_DATA.point(row.size),"height_override":float(row.height),"color":row.color,"position":Vector3.ZERO}
			node = preload("res://world/urban_detail/UrbanBuildingFactory.gd").build_building(data)
		"ground":
			var ground := preload("res://world/editing/WorldGroundFactory.gd")
			node = ground.create(row,ground.bounds(row),_ground_height)
	if node == null: return
	node.set_meta("editor_id",row.id)
	chunk.add_child(node)
	if row.type != "ground":
		node.position = EDIT_DATA.xyz(row.position)
		node.position.y = _ground_height(EDIT_DATA.point(row.position))
		node.rotation.y = deg_to_rad(float(row.rotation))
