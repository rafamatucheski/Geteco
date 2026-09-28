extends Node3D
## Edited station architecture with separate urban and regional service controllers.
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const EDIT_DATA := preload("res://world/editing/WorldEditData.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const LOAD_DISTANCE := 105.0
const UNLOAD_DISTANCE := 135.0
const INTERVAL := 0.25
# Undo the old floor projection and map source pixels into the native /16 map.
# This is a calibration ratio, not another /16 applied to metric geometry.
const FLOOR_CALIBRATION := Vector3(18.0 / 16.0, 1.0, 18.0 * 0.76822128 / 16.0)
const STOPS := [
	{"id":"urban_station_0","name":"Terminal Sul","road":"dock_street","point":Vector2(1650,2200),"tangent":Vector2.RIGHT,"width":120.0,"direction":-1},
	{"id":"urban_station_1","name":"Westgate / Hospital","road":"westgate_drive","point":Vector2(400,1730),"tangent":Vector2.DOWN,"width":110.0,"direction":-1},
	{"id":"urban_station_2","name":"Centro / Comércio","road":"westgate_drive","point":Vector2(400,800),"tangent":Vector2.DOWN,"width":110.0,"direction":-1},
	{"id":"urban_station_3","name":"Foundry / Mercado","road":"foundry_avenue","point":Vector2(1900,400),"tangent":Vector2.RIGHT,"width":120.0,"direction":1},
	{"id":"urban_station_4","name":"Cais / Serviços","road":"quay_boulevard","point":Vector2(3000,920),"tangent":Vector2.DOWN,"width":120.0,"direction":1},
	{"id":"urban_station_5","name":"Docas / Trabalho","road":"quay_boulevard","point":Vector2(3000,1480),"tangent":Vector2.DOWN,"width":120.0,"direction":1},
]
var controller
var definitions: Array[Dictionary] = []
var instances: Dictionary = {}
var _elapsed := 0.0
var terminal_operations: Node3D
var urban_service: Node3D

func configure(owner_controller, use_edits := true) -> void:
	controller = owner_controller
	name = "UrbanTransitPresentation"
	definitions.clear()
	for index in STOPS.size():
		var source: Dictionary = STOPS[index]
		var tangent: Vector2 = source.tangent
		var forward: Vector2 = tangent * int(source.direction)
		# UnifiedRoadNetwork2D._offset_lane_centerline uses orthogonal(), then
		# reverses the curve for direction -1. All six source lanes are straight.
		var lane: Vector2 = source.point + tangent.orthogonal() * float(source.width) * 0.25 * int(source.direction)
		var angle := forward.angle()
		var origin: Vector2 = lane - forward * 90.0 - Vector2.DOWN.rotated(angle) * 60.0
		definitions.append({"id":source.id,"name":source.name,"position":Vector3(origin.x,0,origin.y)/16.0,"type":1 if index==0 else 0,"angle":angle,"road":source.road})
	definitions.append({"id":"harbor_coach_terminal","name":"Rodoviária","position":Vector3(1700,0,1060)/16.0,"type":2,"angle":0.0,"road":"market_street"})
	for index in STOPS.size():
		definitions[index].stop_point = Vector3(STOPS[index].point.x,0,STOPS[index].point.y)/16.0
	if use_edits:
		var loaded := EDIT_DATA.read_document()
		var document: Dictionary = Engine.get_meta("geteco_world_edit_document",loaded.document)
		for index in STOPS.size():
			var definition: Dictionary = definitions[index]
			var id := "piece/transit/"+str(definition.id)
			var row: Dictionary = document.get("regions",{}).get("harbor",{}).get(id,{})
			if row.is_empty() or not EDIT_DATA.validate_entity(row).is_empty(): continue
			definition.deleted = row.get("deleted",false)
			if definition.deleted: continue
			definition.base_position = definition.position
			definition.edit = row.duplicate(true)
			var target := Vector3(row.position[0],0,row.position[1])
			var stretch: Array = row.get("stretch",[1,1])
			var basis := Basis(Vector3.UP,deg_to_rad(float(row.get("rotation",0))))*Basis.from_scale(Vector3(stretch[0],1,stretch[1]))
			definition.stop_point = target+basis*(definition.stop_point-definition.position)
			definition.position = target
	if is_inside_tree(): refresh()

static func upgrade_editor_catalog(catalog: Dictionary) -> void:
	if not catalog.has("harbor"): return
	var source = load("res://runtime/UrbanTransitPresentation.gd").new()
	source.configure(null,false)
	var context: Dictionary = catalog.harbor.get("context",{})
	for index in STOPS.size():
		var definition: Dictionary = source.definitions[index]
		var old_id := "context/harbor/transit/"+str(definition.id)
		var id := "piece/transit/"+str(definition.id)
		if context.has(id): continue
		if not context.has(old_id): continue
		var row: Dictionary = context[old_id].duplicate(true)
		context.erase(old_id)
		var pivot := Vector2(definition.position.x,definition.position.z)
		var margin := (EDIT_DATA.point(row.position)-pivot).abs()
		row.size = [row.size[0]+2*margin.x,row.size[1]+2*margin.y]
		row.merge({"id":id,"type":"piece","position":[pivot.x,pivot.y],"rotation":0.0,"locked":false,"source_record":"transit/"+str(definition.id),"label":"Tubo · "+str(definition.name),"ground":false},true)
		context[id] = row
	source.free()

func _ready() -> void:
	refresh()
	if controller != null:
		terminal_operations = preload("res://runtime/terminal/TerminalOperations.gd").new()
		terminal_operations.configure(controller)
		add_child(terminal_operations)
		urban_service = preload("res://runtime/transit/UrbanBusService.gd").new()
		urban_service.configure(controller)
		add_child(urban_service)

func on_region_changed() -> void:
	_clear()
	refresh()
	if is_instance_valid(urban_service): urban_service.refresh_presence()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < INTERVAL: return
	_elapsed = 0.0
	refresh()

func refresh() -> void:
	if controller == null or not is_inside_tree(): return
	if controller.state.region_id != "harbor":
		if not instances.is_empty(): _clear()
		return
	if not is_instance_valid(controller.world.player): return
	var focus: Vector3 = controller.world.player.global_position
	if not controller.state.place_id.is_empty() and controller.session != null:
		focus = controller.session.return_point
	for definition in definitions:
		if definition.get("deleted",false):
			if instances.has(definition.id): instances[definition.id].queue_free(); instances.erase(definition.id)
			continue
		var point: Vector3 = definition.position
		var distance := Vector2(point.x-focus.x,point.z-focus.z).length()
		var id: String = definition.id
		if instances.has(id):
			if distance > UNLOAD_DISTANCE:
				instances[id].queue_free()
				instances.erase(id)
		elif distance <= LOAD_DISTANCE:
			instances[id] = build_geometry(self,definition)

static func build_geometry(parent: Node3D, definition: Dictionary) -> Node3D:
	var calibration := Node3D.new()
	calibration.name = str(definition.id)+"GroundCalibration"
	calibration.position = definition.get("base_position",definition.position)
	calibration.scale = FLOOR_CALIBRATION
	calibration.set_meta("editor_id",str(definition.id))
	parent.add_child(calibration)
	var station: Node3D = FACTORY.populate_transit(calibration,definition.id,Vector3.ZERO,int(definition.type),float(definition.angle))
	station.station_name = definition.name
	station.set_meta("source_road",definition.road)
	if str(definition.id).begins_with("urban_station_"):
		PIECES.mark(calibration,"transit/"+str(definition.id),"Tubo · "+str(definition.name))
		calibration.set_meta("editor_id","piece/transit/"+str(definition.id))
		if definition.has("edit"):
			var row: Dictionary = definition.edit
			PIECES.apply(calibration,{row.id:row})
	return calibration

func _clear() -> void:
	for instance in instances.values():
		if is_instance_valid(instance): instance.queue_free()
	instances.clear()
