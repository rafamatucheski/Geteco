extends Node3D
## Source-authored architecture only; no duplicated bus, passengers or M00 logic.
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
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

func configure(owner_controller) -> void:
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
	if is_inside_tree(): refresh()

func _ready() -> void:
	refresh()

func on_region_changed() -> void:
	_clear()
	refresh()

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
		var point: Vector3 = definition.position
		var distance := Vector2(point.x-focus.x,point.z-focus.z).length()
		var id: String = definition.id
		if instances.has(id):
			if distance > UNLOAD_DISTANCE:
				instances[id].queue_free()
				instances.erase(id)
		elif distance <= LOAD_DISTANCE:
			var calibration := Node3D.new()
			calibration.name = id + "GroundCalibration"
			calibration.position = point
			calibration.scale = FLOOR_CALIBRATION
			add_child(calibration)
			var station: Node3D = FACTORY.populate_transit(calibration,id,Vector3.ZERO,int(definition.type),float(definition.angle))
			station.station_name = definition.name
			station.set_meta("source_road",definition.road)
			instances[id] = calibration

func _clear() -> void:
	for instance in instances.values():
		if is_instance_valid(instance): instance.queue_free()
	instances.clear()
