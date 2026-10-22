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
## Estações perto do jogador (na árvore). Quem consulta `instances` continua vendo só as próximas.
var instances: Dictionary = {}
## Toda estação já montada, inclusive as guardadas fora da árvore. Montar custava 50-140 ms num quadro: a
## rodoviária tem ~270 malhas e cada tubo ~170 malhas e ~160 colisões, e o teleporte de aquecimento do
## benchmark (233,194 -> 64,82 / 152,82) montava rodoviária e tubos juntos (oeste_1 109 ms e porto_1 84 ms de
## _process no release de 16/10; 124-140 ms e +680-790 nós num quadro no editor). Afastar-se só tira a estação da
## árvore; voltar a recoloca sem montar de novo (_ready não roda outra vez). Todas são montadas sob a cortina.
var _built: Dictionary = {}
## GETECO_TRANSIT_CACHE=0 volta ao comportamento antigo (monta tudo ao chegar, libera ao sair) para comparar.
static var cache_enabled := OS.get_environment("GETECO_TRANSIT_CACHE") != "0"
## Uma estação entra ou sai da árvore por chamada; havendo mais, a próxima chamada vem no quadro seguinte.
var _refresh_soon := false
var _elapsed := 0.0
var terminal_operations: Node3D
var urban_service: Node3D

func configure(owner_controller, use_edits := true) -> void:
	controller = owner_controller
	name = "UrbanTransitPresentation"
	# Definições novas (edições do mundo): as estações montadas com as antigas não servem mais.
	_forget_built()
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
			var local_basis := Basis(Vector3.UP,deg_to_rad(float(row.get("rotation",0))))*Basis.from_scale(Vector3(stretch[0],1,stretch[1]))
			definition.stop_point = target+local_basis*(definition.stop_point-definition.position)
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

const _SYS_SPAN := preload("res://runtime/StallWorkTrace.gd")
## Span do sistema inteiro (22/10): quadros de 30–60 ms com o tempo em _process sem nenhum span.
func _process(delta: float) -> void:
	var span := _SYS_SPAN.begin()
	_process_traced(delta)
	_SYS_SPAN.finish_slow("sys.urban_transit.process", span, 3000)

func _process_traced(delta: float) -> void:
	_elapsed += delta
	if _elapsed < INTERVAL and not _refresh_soon: return
	_elapsed = 0.0
	refresh()

## Sem limite: só sob a cortina (prepare_startup_stations) e nos testes.
func refresh(unlimited := false) -> void:
	_refresh_soon = false
	if not cache_enabled: unlimited = true
	if controller == null or not is_inside_tree(): return
	if controller.state.region_id != "harbor":
		if not instances.is_empty(): _clear()
		return
	if not is_instance_valid(controller.world.player): return
	var focus: Vector3 = controller.world.player.global_position
	if not controller.state.place_id.is_empty() and controller.session != null:
		focus = controller.session.return_point
	# Saídas primeiro (baratas e liberam a vez), depois a entrada mais próxima.
	var nearest: Dictionary = {}
	var nearest_distance := INF
	var changes := 0
	for definition in definitions:
		var id: String = definition.id
		if definition.get("deleted",false):
			if instances.has(id): instances.erase(id)
			if _built.has(id):
				if is_instance_valid(_built[id]): _built[id].queue_free()
				_built.erase(id)
			continue
		var point: Vector3 = definition.position
		var distance := Vector2(point.x-focus.x,point.z-focus.z).length()
		if instances.has(id):
			if distance > UNLOAD_DISTANCE:
				if changes > 0 and not unlimited:
					_refresh_soon = true
					continue
				_park(id)
				changes += 1
		elif distance <= LOAD_DISTANCE:
			if unlimited: _show(definition)
			elif distance < nearest_distance:
				if not nearest.is_empty(): _refresh_soon = true
				nearest = definition
				nearest_distance = distance
			else: _refresh_soon = true
	if nearest.is_empty(): return
	if changes > 0:
		_refresh_soon = true
		return
	_show(nearest)

## Recoloca a estação guardada ou monta uma nova.
func _show(definition: Dictionary) -> void:
	var id: String = definition.id
	var station: Node3D = _built.get(id)
	if is_instance_valid(station):
		if station.get_parent() == null: add_child(station)
	else:
		station = build_geometry(self,definition)
		_built[id] = station
	instances[id] = station

func _park(id: String) -> void:
	var station: Node3D = instances.get(id)
	instances.erase(id)
	if not is_instance_valid(station): return
	# Montada com definições antigas (configure de novo): não volta, é liberada como antes.
	if _built.get(id) != station or not cache_enabled:
		_built.erase(id)
		station.queue_free()
		return
	if station.get_parent() == self: remove_child(station)

## Monta todas as estações enquanto a cortina cobre a tela, uma por quadro, e deixa na árvore só as
## próximas. Assim nenhuma estação é montada com o jogo rodando (só recolocada).
func prepare_startup_stations() -> void:
	if not cache_enabled: return
	for definition in definitions:
		if definition.get("deleted",false) or is_instance_valid(_built.get(definition.id)): continue
		if not is_inside_tree(): return
		_show(definition)
		await get_tree().process_frame
	# O jogador pode estar em outra região: aí todas ficam guardadas.
	if controller != null and controller.state.region_id != "harbor":
		_clear()
		return
	for id in instances.keys(): _park(id)
	refresh(true)

func _notification(what: int) -> void:
	# As guardadas fora da árvore não são filhas: sem isto vazariam com a apresentação.
	if what == NOTIFICATION_PREDELETE: _forget_built()

func _forget_built() -> void:
	for station in _built.values():
		if is_instance_valid(station) and station.get_parent() == null: station.free()
	_built.clear()

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

## Fora de Harbor: as estações saem da árvore e ficam guardadas para a volta.
func _clear() -> void:
	for id in instances.keys(): _park(id)
	instances.clear()
