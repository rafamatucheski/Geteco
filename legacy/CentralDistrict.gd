@tool
class_name CentralDistrict
extends Node2D

## Fase 1: bairro inicial compacto. A geometria e as rotas vivem aqui para
## impedir prédios em ruas e NPCs vagando pelo asfalto.

const DISTRICT_SIZE := Vector2(1800, 1280)
const ROAD_WIDTH := 180.0
const SIDEWALK_WIDTH := 48.0
const AVENUE_X := 780.0
const AVENUE_Y := 510.0
const LOCAL_STREET := Rect2(1290, 70, 100, 440)
const PROCEDURAL_TREE := preload("res://geodata/nature/ProceduralStreetTree.gd")
const LAMP_SCRIPT := preload("res://geodata/StreetLamp.gd")
const ProceduralBuildingScene := preload("res://geodata/ProceduralBuilding.gd")
const MODERN_TRAFFIC := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
const AuthoredPedestrian := preload("res://world/shared/pedestrians/AuthoredSidewalkPedestrian.gd")
const DocksParkingScene := preload("res://world/shared/emergency/DocksParking.tscn")
const EmergencyVehicleYardScene := preload("res://world/shared/emergency/EmergencyVehicleYard.gd")

const ROAD_COLOR := Color("#222b35")
const SIDEWALK_COLOR := Color("#a9aaa2")
const CURB_COLOR := Color("#70767a")
const GRASS_COLOR := Color("#52634d")
const LANE_COLOR := Color("#e8cd4d")
const MAIN_INTERSECTION_ID: StringName = &"central_district_main"
const MAIN_INTERSECTION_CENTER := Vector2(AVENUE_X + ROAD_WIDTH * 0.5, AVENUE_Y + ROAD_WIDTH * 0.5)

## Fixed authored centre.  This layout never rerolls: every block has a role,
## an access pattern and its own silhouette.
var blocks := [
	{"id": "MERCADO_VELHO", "rect": Rect2(70, 70, 710, 440), "lots": [
		{"kind": "clothing_shop", "rect": Rect2(132, 134, 190, 200), "poi": "LOJA_ROUPAS"},
		{"kind": "ammunation_shop", "rect": Rect2(334, 134, 170, 200), "poi": "AMMU-NATION"},
		{"kind": "warehouse", "rect": Rect2(516, 134, 190, 130)},
		{"kind": "office", "rect": Rect2(516, 276, 190, 126)},
		{"kind": "brownstone", "rect": Rect2(132, 346, 176, 116)},
		{"kind": "rowhouse", "rect": Rect2(320, 346, 184, 116)}
	]},
	{"id": "CLINICA", "rect": Rect2(960, 70, 330, 440), "lots": [
		{"kind": "hospital", "rect": Rect2(1008, 118, 234, 254), "poi": "HOSPITAL"},
		{"kind": "park", "rect": Rect2(1008, 382, 234, 80)}
	]},
	{"id": "CIVICO", "rect": Rect2(1390, 70, 340, 440), "lots": [
		{"kind": "police", "rect": Rect2(1438, 118, 244, 192), "poi": "DELEGACIA"},
		{"kind": "police_yard", "rect": Rect2(1438, 322, 244, 140)}
	]},
	{"id": "DOCAS", "rect": Rect2(70, 690, 710, 520), "lots": [
		{"kind": "garage", "rect": Rect2(118, 738, 300, 290), "poi": "GARAGEM"},
		{"kind": "morgue", "rect": Rect2(430, 738, 254, 160), "poi": "IML_CENTRAL"},
		{"kind": "rowhouse", "rect": Rect2(430, 910, 254, 112)}
	]},
	{"id": "DISTRITO_MISTO", "rect": Rect2(960, 690, 770, 520), "lots": [
		{"kind": "fire_station", "rect": Rect2(1008, 738, 270, 280), "poi": "QUARTEL_CENTRAL"},
		{"kind": "corner_shop", "rect": Rect2(1290, 738, 180, 158)},
		{"kind": "shop", "rect": Rect2(1482, 738, 200, 158)},
		{"kind": "brownstone", "rect": Rect2(1290, 908, 180, 254), "arcade_depth": 74.0},
		{"kind": "rowhouse", "rect": Rect2(1482, 908, 200, 254), "arcade_depth": 74.0}
	]}
]

func _ready() -> void:
	z_index = 0
	queue_redraw()
	if Engine.is_editor_hint():
		# Preview apenas: antes deste ajuste o CentralDistrict.gd nao tinha
		# @tool, entao _ready()/_draw() so rodavam com o jogo em Play e a
		# cena aparecia totalmente vazia no editor. Agora o _draw() (ruas,
		# calcadas, quarteiroes, faixas) roda no editor tambem, mas nada
		# abaixo disso e spawnado aqui: previamente essas chamadas criavam
		# predios, arvores, trafego, pedestres e managers de gameplay como
		# nos reais da cena -- em modo editor isso salvaria centenas de nos
		# procedurais dentro do .tscn e tentaria rodar logica que depende do
		# jogo estar rodando (autoloads, colisoes, IA).
		return
	validate_layout()
	_create_lot_visuals_and_collisions()
	_create_trees_and_lamps()
	_register_main_intersection()
	_create_authored_parking()
	_create_directed_traffic()
	_create_sidewalk_pedestrians()
	_create_gang_and_missions()

func _create_gang_and_missions() -> void:
	if get_node_or_null("GangManager") == null and get_tree().get_first_node_in_group("gang_manager") == null:
		var gm := GangManager.new()
		gm.name = "GangManager"
		add_child(gm)
		
	if get_node_or_null("VehicleUpgradeManager") == null and get_tree().get_first_node_in_group("vehicle_upgrade_manager") == null:
		var vum := VehicleUpgradeManager.new()
		vum.name = "VehicleUpgradeManager"
		add_child(vum)
		
	if get_node_or_null("MissionManager") == null and get_tree().get_first_node_in_group("mission_manager") == null:
		var mm := MissionManager.new()
		mm.name = "MissionManager"
		add_child(mm)
		
	if get_node_or_null("IronCobraCulDeSac") == null:
		var cul_de_sac := IronCobraCulDeSac.new()
		cul_de_sac.name = "IronCobraCulDeSac"
		add_child(cul_de_sac)
		
	if get_node_or_null("CarChalkboard") == null:
		var chalkboard := CarChalkboard.new()
		chalkboard.name = "CarChalkboard"
		add_child(chalkboard)
		
	if get_node_or_null("HospitalHealthPickup") == null:
		var hp := HealthPickup.new()
		hp.name = "HospitalHealthPickup"
		hp.position = Vector2(1125, 385)
		add_child(hp)
		
		var hosp_marker := Marker2D.new()
		hosp_marker.name = "HospitalSpawnMarker"
		hosp_marker.add_to_group("hospital_spawn")
		hosp_marker.position = Vector2(1125, 385)
		add_child(hosp_marker)

func _exit_tree() -> void:
	var manager := get_node_or_null("/root/TrafficLightManager")
	if manager != null and manager.has_method("unregister_intersection"):
		manager.unregister_intersection(MAIN_INTERSECTION_ID)

func _register_main_intersection() -> void:
	var manager := get_node_or_null("/root/TrafficLightManager")
	if manager != null and manager.has_method("register_intersection"):
		manager.register_intersection(MAIN_INTERSECTION_ID, MAIN_INTERSECTION_CENTER, ROAD_WIDTH)

func _create_authored_parking() -> void:
	var docks_parking := DocksParkingScene.instantiate()
	docks_parking.name = "DocksAuthoredParking"
	add_child(docks_parking)

func validate_layout() -> void:
	var vertical := Rect2(AVENUE_X, 0, ROAD_WIDTH, DISTRICT_SIZE.y)
	var horizontal := Rect2(0, AVENUE_Y, DISTRICT_SIZE.x, ROAD_WIDTH)
	for block in blocks:
		var interior: Rect2 = (block.rect as Rect2).grow(-SIDEWALK_WIDTH)
		for lot in block.lots:
			var lot_rect: Rect2 = lot.rect
			assert(interior.encloses(lot_rect), "%s has a lot outside its block" % block.id)
			assert(not lot_rect.intersects(vertical) and not lot_rect.intersects(horizontal) and not lot_rect.intersects(LOCAL_STREET), "%s has a lot on a road" % block.id)
	print("CENTRAL_DISTRICT_READY: 5 authored blocks, local street, service alley, 8 current lane vehicles, 28 current sidewalk pedestrians")

func _create_lot_visuals_and_collisions() -> void:
	var visual_root := Node2D.new()
	visual_root.name = "LotBuildings"
	visual_root.y_sort_enabled = true
	visual_root.z_index = 20
	add_child(visual_root)
	var seed := 0
	for block in blocks:
		for lot in block.lots:
			var rect: Rect2 = lot.rect
			if String(lot.kind) == "police_yard":
				_create_service_yard(rect, "police")
				continue
			# A setback becomes a service strip/entrance around the building. It
			# preserves a continuous sidewalk even for tall procedural volumes.
			var building_rect := rect.grow(-14)
			var building := ProceduralBuildingScene.new() as ProceduralBuilding
			building.name = String(lot.get("poi", "Building"))
			building.position = building_rect.get_center()
			building.footprint = building_rect.size
			building.building_kind = String(lot.kind)
			building.variant_seed = seed
			if lot.has("arcade_depth"):
				building.arcade_depth = float(lot.arcade_depth)
			seed += 1
			visual_root.add_child(building)
			# ProceduralBuilding owns its solid; parks remain walkable.
			# POIs will get small façade signs later; never float labels over roofs.

func _create_service_yard(rect: Rect2, service_kind: String) -> void:
	var yard := EmergencyVehicleYardScene.new()
	yard.name = "CentralPoliceMotorPool"
	yard.position = rect.get_center()
	yard.yard_size = rect.size - Vector2(16, 16)
	yard.service_kind = service_kind
	yard.road_direction = Vector2.DOWN
	yard.z_index = 2
	add_child(yard)

func _add_building_collision(rect: Rect2, label_name: String) -> void:
	var body := StaticBody2D.new()
	body.name = "%s_Blocker" % label_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _create_trees_and_lamps() -> void:
	var decor := Node2D.new()
	decor.name = "SidewalkDecor"
	decor.z_index = 8
	add_child(decor)
	for block in blocks:
		var rect: Rect2 = block.rect
		_add_tree(decor, Vector2(rect.position.x + 24, rect.position.y + 82))
		_add_tree(decor, Vector2(rect.end.x - 24, rect.end.y - 96))
		_add_tree(decor, Vector2(rect.position.x + 24, rect.end.y - 54))
		_add_lamp(decor, Vector2(rect.position.x + 44, rect.position.y + 24))
		_add_lamp(decor, Vector2(rect.end.x - 70, rect.end.y - 24))

func _add_tree(parent: Node2D, at: Vector2) -> void:
	var tree := PROCEDURAL_TREE.new() as ProceduralStreetTree
	tree.position = at
	tree.variant_seed = int(at.x * 7.0 + at.y * 13.0)
	tree.crown_scale = 0.88 + float(posmod(tree.variant_seed, 5)) * 0.035
	tree.tree_style = ProceduralStreetTree.TreeStyle.STREET if tree.variant_seed % 3 != 0 else ProceduralStreetTree.TreeStyle.BROADLEAF
	tree.leaf_color = Color("#356649") if tree.variant_seed % 2 == 0 else Color("#436f4b")
	parent.add_child(tree)

func _add_lamp(parent: Node2D, at: Vector2) -> void:
	var lamp := LAMP_SCRIPT.new()
	lamp.position = at
	parent.add_child(lamp)

var _traffic_lane_paths: Dictionary = {}
var _traffic_archetypes: Array = []
var _traffic_respawn_timer: float = 0.0
const TARGET_TRAFFIC_COUNT: int = 8

func _create_directed_traffic() -> void:
	var lanes := {
		"east": PackedVector2Array([Vector2(30, 556), Vector2(1770, 556), Vector2(1770, 536), Vector2(30, 536)]),
		"west": PackedVector2Array([Vector2(1770, 646), Vector2(30, 646), Vector2(30, 666), Vector2(1770, 666)]),
		"south": PackedVector2Array([Vector2(826, 30), Vector2(826, 1250), Vector2(806, 1250), Vector2(806, 30)]),
		"north": PackedVector2Array([Vector2(914, 1250), Vector2(914, 30), Vector2(934, 30), Vector2(934, 1250)])
	}
	var archetypes := ["sedan_classic", "taxi_yellow", "sport_coupe", "station_wagon", "ranch_pickup", "desert_jeep_4x4", "muscle_classic", "beach_cabriolet"]
	var specs := [["east", 0.0], ["east", 420.0], ["west", 160.0], ["west", 640.0], ["south", 70.0], ["south", 510.0], ["north", 230.0], ["north", 700.0]]
	_traffic_archetypes = archetypes
	
	var traffic_root := Node2D.new()
	traffic_root.name = "ModernDirectedTraffic"
	traffic_root.z_index = 9
	add_child(traffic_root)
	var lane_paths: Dictionary = {}
	for lane_name in lanes:
		var axis := "EW" if lane_name == "east" or lane_name == "west" else "NS"
		lane_paths[lane_name] = MODERN_TRAFFIC.create_lane(
			traffic_root,
			"Central_%s" % String(lane_name),
			lanes[lane_name],
			MAIN_INTERSECTION_ID,
			axis
		)
	_traffic_lane_paths = lane_paths

	for index in specs.size():
		var spec_info: Array = specs[index]
		var arch_id: String = archetypes[index % archetypes.size()]
		var lane_name: String = String(spec_info[0])
		var route: PackedVector2Array = lanes[lane_name]
		var route_length := 0.0
		for point_index in range(route.size()):
			route_length += route[point_index].distance_to(route[(point_index + 1) % route.size()])
		var requested_ratio := float(spec_info[1]) / maxf(1.0, route_length)
		var vehicle := MODERN_TRAFFIC.spawn_moving_vehicle(
			lane_paths[lane_name],
			"Traffic_%02d" % (index + 1),
			arch_id,
			requested_ratio,
			78.0 + float(index % 4) * 9.0,
			index
		)
		vehicle.add_to_group("central_district_traffic")

var _pedestrian_respawn_timer: float = 0.0
const TARGET_PEDESTRIAN_COUNT: int = 28

func _process(delta: float) -> void:
	_pedestrian_respawn_timer -= delta
	if _pedestrian_respawn_timer <= 0.0:
		_pedestrian_respawn_timer = 4.0
		_maintain_pedestrian_population()
	_traffic_respawn_timer -= delta
	if _traffic_respawn_timer <= 0.0:
		_traffic_respawn_timer = 3.5
		_maintain_traffic_population()

func _maintain_traffic_population() -> void:
	if _traffic_lane_paths.is_empty():
		return
	var active_cars: Array[Node] = []
	for node in get_tree().get_nodes_in_group("central_district_traffic"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			var tv = node as DemoTrafficVehicle
			if tv and not tv.is_broken and not tv._detached_from_lane:
				active_cars.append(node)
	if active_cars.size() < TARGET_TRAFFIC_COUNT:
		var missing := TARGET_TRAFFIC_COUNT - active_cars.size()
		var lane_keys := _traffic_lane_paths.keys()
		for i in range(mini(missing, 2)):
			var lane_key = lane_keys[randi() % lane_keys.size()]
			var lane_path: Path2D = _traffic_lane_paths[lane_key]
			var arch_id: String = _traffic_archetypes[randi() % _traffic_archetypes.size()]
			var vehicle := MODERN_TRAFFIC.spawn_moving_vehicle(
				lane_path,
				"Traffic_Respawn_%d" % randi(),
				arch_id,
				randf(),
				78.0 + float(randi() % 4) * 9.0,
				randi() % 8
			)
			vehicle.add_to_group("central_district_traffic")

func _maintain_pedestrian_population() -> void:
	var current_peds = get_tree().get_nodes_in_group("central_district_pedestrians")
	var count = current_peds.size()
	if count < TARGET_PEDESTRIAN_COUNT:
		var missing = TARGET_PEDESTRIAN_COUNT - count
		for i in range(mini(missing, 4)):
			_spawn_single_3d_pedestrian()

func _create_sidewalk_pedestrians() -> void:
	# Current articulated models, distributed on fixed sidewalk loops.
	for i in range(TARGET_PEDESTRIAN_COUNT):
		_spawn_single_3d_pedestrian(i)

func _spawn_single_3d_pedestrian(spawn_index: int = -1) -> void:
	var routes := _get_central_sidewalk_routes()
	var idx: int = spawn_index if spawn_index >= 0 else randi() % TARGET_PEDESTRIAN_COUNT
	var route_index := idx % routes.size()
	var route: PackedVector2Array = routes[route_index]
	var ped := AuthoredPedestrian.new()
	ped.name = "CentralPedestrian_%02d" % (idx + 1)
	ped.district_theme = AnimatedPedestrian3D.DistrictTheme.CITY_DOWNTOWN
	ped.archetype_override = idx % 8
	ped.configure_authored_route(route, "central_sidewalk_%02d" % route_index, float(idx) * 113.0)
	ped.add_to_group("central_district_pedestrians")
	add_child(ped)

func _get_central_sidewalk_routes() -> Array:
	# One closed loop per authored block. Coordinates stay inside the 48 px
	# sidewalk band and outside every building collision and traffic lane.
	return [
		PackedVector2Array([Vector2(100, 102), Vector2(750, 102), Vector2(750, 478), Vector2(100, 478)]),
		PackedVector2Array([Vector2(990, 102), Vector2(1260, 102), Vector2(1260, 478), Vector2(990, 478)]),
		PackedVector2Array([Vector2(1420, 102), Vector2(1700, 102), Vector2(1700, 478), Vector2(1420, 478)]),
		PackedVector2Array([Vector2(100, 720), Vector2(750, 720), Vector2(750, 1180), Vector2(100, 1180)]),
		PackedVector2Array([Vector2(990, 720), Vector2(1700, 720), Vector2(1700, 1180), Vector2(990, 1180)]),
	]

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DISTRICT_SIZE), Color("#3f4b51"))
	for block in blocks:
		var rect: Rect2 = block.rect
		draw_rect(rect, SIDEWALK_COLOR)
		draw_rect(rect.grow(-SIDEWALK_WIDTH), Color("#69675f"))
		draw_rect(rect, CURB_COLOR, false, 4.0)
		_draw_block_surface(rect.grow(-SIDEWALK_WIDTH))
	# Planned service alley and parking belong only to the Docks block; they are
	# not repeated texture marks elsewhere in the city.
	var docks_alley := Rect2(118, 1028, 566, 44)
	var docks_parking := Rect2(132, 1084, 272, 78)
	draw_rect(docks_alley, Color("#454a4a"))
	draw_rect(docks_alley, Color("#242a2d"), false, 2.0)
	draw_rect(docks_parking, Color("#555854"))
	for x in range(int(docks_parking.position.x + 12), int(docks_parking.end.x - 10), 42):
		draw_line(Vector2(x, docks_parking.position.y + 8), Vector2(x, docks_parking.end.y - 8), Color("#b8ae8a"), 2.0)
	var vertical := Rect2(AVENUE_X, 0, ROAD_WIDTH, DISTRICT_SIZE.y)
	var horizontal := Rect2(0, AVENUE_Y, DISTRICT_SIZE.x, ROAD_WIDTH)
	draw_rect(vertical, ROAD_COLOR)
	draw_rect(horizontal, ROAD_COLOR)
	draw_rect(LOCAL_STREET, ROAD_COLOR)
	for lane_x in [AVENUE_X + 40.0, AVENUE_X + 120.0]:
		_draw_vertical_dashes(lane_x, 20.0, AVENUE_Y - 16.0)
		_draw_vertical_dashes(lane_x, AVENUE_Y + ROAD_WIDTH + 16.0, DISTRICT_SIZE.y - 20.0)
	for lane_y in [AVENUE_Y + 40.0, AVENUE_Y + 120.0]:
		_draw_horizontal_dashes(lane_y, 20.0, AVENUE_X - 16.0)
		_draw_horizontal_dashes(lane_y, AVENUE_X + ROAD_WIDTH + 16.0, DISTRICT_SIZE.x - 20.0)
	for y in range(int(LOCAL_STREET.position.y + 18), int(LOCAL_STREET.end.y - 12), 48):
		draw_line(Vector2(LOCAL_STREET.get_center().x, y), Vector2(LOCAL_STREET.get_center().x, y + 22), LANE_COLOR, 3)
	_draw_crosswalks()

func _draw_vertical_dashes(x: float, from_y: float, to_y: float) -> void:
	var y := from_y
	while y < to_y:
		var dash_end := minf(y + 28.0, to_y)
		draw_line(Vector2(x, y), Vector2(x, dash_end), LANE_COLOR, 4.0)
		y += 54.0

func _draw_horizontal_dashes(y: float, from_x: float, to_x: float) -> void:
	var x := from_x
	while x < to_x:
		var dash_end := minf(x + 28.0, to_x)
		draw_line(Vector2(x, y), Vector2(dash_end, y), LANE_COLOR, 4.0)
		x += 54.0

func _draw_block_surface(interior: Rect2) -> void:
	# Dirty pavement, service courts and a few parking marks keep the block from
	# reading as a large lawn under isolated buildings.
	for y in range(int(interior.position.y + 12), int(interior.end.y - 8), 28):
		draw_line(Vector2(interior.position.x + 9, y), Vector2(interior.end.x - 9, y), Color("#575950"), 1.0)

func _draw_crosswalks() -> void:
	var stripe := Color("#e7e5da")
	var stop_line := Color("#f1efe5")
	for x in range(int(AVENUE_X + 12.0), int(AVENUE_X + ROAD_WIDTH - 8.0), 22):
		draw_rect(Rect2(x, AVENUE_Y + 8.0, 12, 24), stripe)
		draw_rect(Rect2(x, AVENUE_Y + ROAD_WIDTH - 32.0, 12, 24), stripe)
	for y in range(int(AVENUE_Y + 12.0), int(AVENUE_Y + ROAD_WIDTH - 8.0), 22):
		draw_rect(Rect2(AVENUE_X + 8.0, y, 24, 12), stripe)
		draw_rect(Rect2(AVENUE_X + ROAD_WIDTH - 32.0, y, 24, 12), stripe)
	draw_line(Vector2(AVENUE_X, AVENUE_Y - 8.0), Vector2(MAIN_INTERSECTION_CENTER.x, AVENUE_Y - 8.0), stop_line, 4.0)
	draw_line(Vector2(MAIN_INTERSECTION_CENTER.x, AVENUE_Y + ROAD_WIDTH + 8.0), Vector2(AVENUE_X + ROAD_WIDTH, AVENUE_Y + ROAD_WIDTH + 8.0), stop_line, 4.0)
	draw_line(Vector2(AVENUE_X - 8.0, MAIN_INTERSECTION_CENTER.y), Vector2(AVENUE_X - 8.0, AVENUE_Y + ROAD_WIDTH), stop_line, 4.0)
	draw_line(Vector2(AVENUE_X + ROAD_WIDTH + 8.0, AVENUE_Y), Vector2(AVENUE_X + ROAD_WIDTH + 8.0, MAIN_INTERSECTION_CENTER.y), stop_line, 4.0)
	_draw_local_street_mouth(stripe, stop_line)

func _draw_local_street_mouth(stripe: Color, stop_line: Color) -> void:
	for x in range(int(LOCAL_STREET.position.x + 8.0), int(LOCAL_STREET.end.x - 6.0), 18):
		draw_rect(Rect2(x, LOCAL_STREET.end.y - 27.0, 10, 18), stripe)
	draw_line(
		Vector2(LOCAL_STREET.position.x + 5.0, LOCAL_STREET.end.y - 4.0),
		Vector2(LOCAL_STREET.end.x - 5.0, LOCAL_STREET.end.y - 4.0),
		stop_line,
		4.0
	)
