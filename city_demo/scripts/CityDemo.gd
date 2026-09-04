@tool
class_name DemoCityDistrict
extends Node2D

const TILE_SIZE = 64
const MIN_CELL = Vector2i(-15, -12)
const MAX_CELL = Vector2i(15, 12)
const ROAD_TILE: Texture2D = preload("res://city_demo/art/road_tiles.svg")
const BUILDING_SCENE: PackedScene = preload("res://city_demo/scenes/CityBuilding.tscn")
const VEHICLE_SCENE: PackedScene = preload("res://city_demo/scenes/TrafficVehicle.tscn")
const PEDESTRIAN_SCENE: PackedScene = preload("res://city_demo/scenes/Pedestrian.tscn")

const VEHICLE_CROPS: Array[Rect2] = [
	Rect2(52, 106, 218, 392), Rect2(350, 49, 235, 462),
	Rect2(663, 48, 234, 475), Rect2(970, 35, 246, 499),
	Rect2(29, 638, 264, 548), Rect2(340, 625, 256, 566),
	Rect2(650, 587, 264, 619), Rect2(968, 551, 248, 673)
]
const VEHICLE_LENGTHS: Array[float] = [72.0, 78.0, 76.0, 82.0, 88.0, 94.0, 108.0, 118.0]

@export var enable_legacy_district: bool = false
@export var auto_spawn_buildings: bool = false
## The Phase 1 centre owns its own routes.  Keeping this off avoids adding the
## retired free-roaming traffic/pedestrians back over the new district.
@export var enable_legacy_runtime: bool = false

var tile_layer: TileMapLayer
var navigation_region: NavigationRegion2D
var pedestrian_points := PackedVector2Array()
var vehicle_registry: Array = []
var instantiated_vehicle_count: int = 0

func _ready() -> void:
	if Engine.is_editor_hint():
		for child in get_children():
			child.queue_free()

	if enable_legacy_district:
		_create_tile_district()
		_create_buildings()
		_create_decor()
	
	if Engine.is_editor_hint():
		queue_redraw()
		return
		
	if enable_legacy_runtime:
		_create_navigation()
		_load_vehicle_registry()
		_create_traffic()
		_create_pedestrians()
		_create_status_panel()
	_inject_hud()
	queue_redraw()

func _inject_hud():
	var hud_scene = load("res://HUD.tscn")
	if hud_scene:
		var hud = hud_scene.instantiate()
		get_parent().call_deferred("add_child", hud)
		var wanted_mgr = get_node_or_null("/root/WantedManager")
		if wanted_mgr:
			wanted_mgr.stars_changed.connect(hud.update_stars)
			
	var pause_scene = load("res://ui/PauseMenu.tscn")
	if pause_scene:
		var pause_menu = pause_scene.instantiate()
		get_parent().call_deferred("add_child", pause_menu)
			
	var phone_scene = load("res://PhoneBox.tscn")
	if phone_scene:
		var phone = phone_scene.instantiate()
		phone.position = Vector2(0, -100)
		get_parent().call_deferred("add_child", phone)
		
	var garage_scene = load("res://GarageTrigger.tscn")
	if garage_scene:
		var garage = garage_scene.instantiate()
		garage.position = Vector2(-664, 494)
		get_parent().call_deferred("add_child", garage)

	var weapon_store_scene = load("res://WeaponStore.tscn")
	if weapon_store_scene:
		var weapon_store = weapon_store_scene.instantiate()
		weapon_store.position = Vector2(-425, 485)
		get_parent().call_deferred("add_child", weapon_store)

	var effects_script = load("res://city_demo/scripts/WeaponEffects.gd")
	if effects_script:
		var effects = effects_script.new()
		get_parent().call_deferred("add_child", effects)

	var weather_script = load("res://DayNightWeatherManager.gd")
	if weather_script:
		var weather = weather_script.new()
		get_parent().call_deferred("add_child", weather)

func _draw() -> void:
	if not enable_legacy_district:
		return
	# Faixas amarelas centrais
	_draw_dashed_line(Vector2(-960, -32), Vector2(960, -32), Color("dbc85c"))
	_draw_dashed_line(Vector2(-960, 32), Vector2(960, 32), Color("dbc85c"))
	_draw_dashed_line(Vector2(-32, -768), Vector2(-32, 768), Color("dbc85c"))
	_draw_dashed_line(Vector2(32, -768), Vector2(32, 768), Color("dbc85c"))
	_draw_rectangular_lane(Rect2(-864, -672, 1728, 1344), Color(0.88, 0.88, 0.82, 0.65))
	
	# Faixas de Pedestre (Zebra) no Cruzamento Central
	_draw_zebra_crosswalk(Vector2(-60, -72), Vector2(60, -72), true)  # Norte
	_draw_zebra_crosswalk(Vector2(-60, 72), Vector2(60, 72), true)    # Sul
	_draw_zebra_crosswalk(Vector2(-72, -60), Vector2(-72, 60), false) # Oeste
	_draw_zebra_crosswalk(Vector2(72, -60), Vector2(72, 60), false)  # Leste
	
	# Linhas de Retenção Brancas (Stop Lines)
	draw_line(Vector2(0, -92), Vector2(64, -92), Color(0.95, 0.95, 0.95), 3.5)   # Pista Sul
	draw_line(Vector2(-64, 92), Vector2(0, 92), Color(0.95, 0.95, 0.95), 3.5)    # Pista Norte
	draw_line(Vector2(-92, -64), Vector2(-92, 0), Color(0.95, 0.95, 0.95), 3.5)  # Pista Leste
	draw_line(Vector2(92, 0), Vector2(92, 64), Color(0.95, 0.95, 0.95), 3.5)    # Pista Oeste

func _draw_zebra_crosswalk(start_pos: Vector2, end_pos: Vector2, is_horizontal: bool) -> void:
	var count := 8
	for i in range(count):
		var t := float(i) / float(count - 1)
		var center := start_pos.lerp(end_pos, t)
		if is_horizontal:
			draw_rect(Rect2(center.x - 4, center.y - 9, 8, 18), Color(0.92, 0.92, 0.92, 0.9))
		else:
			draw_rect(Rect2(center.x - 9, center.y - 4, 18, 8), Color(0.92, 0.92, 0.92, 0.9))

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color) -> void:
	var length := from.distance_to(to)
	var direction := from.direction_to(to)
	var cursor := 0.0
	while cursor < length:
		var dash_end := minf(cursor + 22.0, length)
		draw_line(from + direction * cursor, from + direction * dash_end, color, 2.0)
		cursor += 44.0

func _draw_rectangular_lane(rect: Rect2, color: Color) -> void:
	_draw_dashed_line(rect.position, Vector2(rect.end.x, rect.position.y), color)
	_draw_dashed_line(Vector2(rect.end.x, rect.position.y), rect.end, color)
	_draw_dashed_line(rect.end, Vector2(rect.position.x, rect.end.y), color)
	_draw_dashed_line(Vector2(rect.position.x, rect.end.y), rect.position, color)

func _create_tile_district() -> void:
	tile_layer = TileMapLayer.new()
	tile_layer.name = "FixedDistrictTileMap"
	tile_layer.z_index = -20
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = ROAD_TILE
	atlas_source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for tile_x in range(6):
		atlas_source.create_tile(Vector2i(tile_x, 0))
	tile_set.add_source(atlas_source, 0)
	tile_layer.tile_set = tile_set
	add_child(tile_layer)

	for y in range(MIN_CELL.y, MAX_CELL.y + 1):
		for x in range(MIN_CELL.x, MAX_CELL.x + 1):
			var cell := Vector2i(x, y)
			var tile_index := 0
			var vertical := _is_vertical_road(x)
			var horizontal := _is_horizontal_road(y)
			if vertical and horizontal:
				tile_index = 3
			elif vertical:
				tile_index = 2
			elif horizontal:
				tile_index = 1
			elif _is_sidewalk_cell(cell):
				tile_index = 4
			else:
				tile_index = 0
			tile_layer.set_cell(cell, 0, Vector2i(tile_index, 0), 0)

func _is_vertical_road(x: int) -> bool:
	return x == -1 or x == 0 or x == -14 or x == -13 or x == 13 or x == 14

func _is_horizontal_road(y: int) -> bool:
	return y == -1 or y == 0 or y == -11 or y == -10 or y == 10 or y == 11

func _is_road_cell(cell: Vector2i) -> bool:
	return _is_vertical_road(cell.x) or _is_horizontal_road(cell.y)

func _is_sidewalk_cell(cell: Vector2i) -> bool:
	if _is_road_cell(cell):
		return false
	return true

func _is_crosswalk_cell(cell: Vector2i) -> bool:
	return _is_vertical_road(cell.x) and _is_horizontal_road(cell.y)

func _is_cell_blocked_by_building(cell: Vector2i) -> bool:
	var cell_rect := Rect2(cell.x * TILE_SIZE, cell.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	var placements := [
		[-690, -230, 166], [-460, -255, 184], [-225, -220, 158],
		[225, -235, 174], [470, -260, 164], [690, -225, 156],
		[-680, 520, 172], [-445, 545, 160], [-220, 505, 182],
		[220, 525, 158], [455, 500, 178], [690, 540, 166]
	]
	for p in placements:
		var bx: float = float(p[0])
		var by: float = float(p[1])
		var bw: float = float(p[2])
		var bh: float = bw * 1.5
		var b_rect := Rect2(bx - bw * 0.48, by - bh * 0.98, bw * 0.96, bh * 0.98)
		if cell_rect.intersects(b_rect):
			return true
	return false

func _create_navigation() -> void:
	navigation_region = NavigationRegion2D.new()
	navigation_region.name = "SidewalkNavigation"
	navigation_region.navigation_layers = 1
	var vertices := PackedVector2Array()
	var vertex_lookup := {}
	var polygons: Array[PackedInt32Array] = []
	for y in range(MIN_CELL.y, MAX_CELL.y + 1):
		for x in range(MIN_CELL.x, MAX_CELL.x + 1):
			var cell := Vector2i(x, y)
			if not _is_sidewalk_cell(cell) and not _is_crosswalk_cell(cell):
				continue
			if _is_cell_blocked_by_building(cell):
				continue
			var top_left := Vector2(x * TILE_SIZE, y * TILE_SIZE)
			var corners := [top_left, top_left + Vector2(TILE_SIZE, 0), top_left + Vector2(TILE_SIZE, TILE_SIZE), top_left + Vector2(0, TILE_SIZE)]
			var polygon := PackedInt32Array()
			for corner in corners:
				var key := "%d:%d" % [int(corner.x), int(corner.y)]
				if not vertex_lookup.has(key):
					vertex_lookup[key] = vertices.size()
					vertices.append(corner)
				polygon.append(int(vertex_lookup[key]))
			polygons.append(polygon)
			if _is_sidewalk_cell(cell) and (x + y) % 3 == 0:
				pedestrian_points.append(top_left + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5))
	var navigation_polygon := NavigationPolygon.new()
	navigation_polygon.vertices = vertices
	for polygon in polygons:
		navigation_polygon.add_polygon(polygon)
	navigation_region.navigation_polygon = navigation_polygon
	add_child(navigation_region)

func _create_buildings() -> void:
	if not auto_spawn_buildings:
		return
	var container := Node2D.new()
	container.name = "FixedBuildings"
	container.y_sort_enabled = true
	add_child(container)
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		container.owner = get_tree().edited_scene_root
		
	var placements := [
		# Quadra Central Norte (Apartamentos Médios e Serviços Públicos)
		[-690, -230, 0, 166, "", DemoCityBuilding.Archetype.MEDIUM_APARTMENT],
		[-460, -255, 3, 184, "", DemoCityBuilding.Archetype.MEDIUM_APARTMENT],
		[-225, -220, 4, 158, "DELEGACIA CENTRAL", DemoCityBuilding.Archetype.MEDIUM_APARTMENT],
		[225, -235, 1, 174, "HOSPITAL CENTRAL", DemoCityBuilding.Archetype.MEDIUM_APARTMENT],
		[470, -260, 2, 164, "CORPO DE BOMBEIROS", DemoCityBuilding.Archetype.MEDIUM_APARTMENT],
		[690, -225, 5, 156, "", DemoCityBuilding.Archetype.MEDIUM_APARTMENT],
		# Três quadras condensadas: mistura de sobrados, lojas e armazéns.
		[-770, 525, 5, 98, "GARAGEM", DemoCityBuilding.Archetype.WAREHOUSE],
		[-660, 520, 2, 108, "AUTO PEÇAS", DemoCityBuilding.Archetype.COMMERCIAL_SHOP],
		[-545, 530, 3, 104, "", DemoCityBuilding.Archetype.SUBURBAN_HOUSE],
		[-425, 545, 5, 118, "AMMU-NATION", DemoCityBuilding.Archetype.COMMERCIAL_SHOP],
		[-305, 520, 4, 100, "", DemoCityBuilding.Archetype.SUBURBAN_HOUSE],
		[-195, 525, 0, 110, "", DemoCityBuilding.Archetype.SUBURBAN_HOUSE],
		# BAIRRO-PILOTO SUL-LESTE: quadra comercial coerente.
		[150, 530, 4, 82, "LANCHONETE", DemoCityBuilding.Archetype.COMMERCIAL_SHOP],
		[242, 524, 1, 86, "FARMÁCIA", DemoCityBuilding.Archetype.COMMERCIAL_SHOP],
		[338, 530, 5, 84, "MERCADO", DemoCityBuilding.Archetype.COMMERCIAL_SHOP],
		[432, 522, 0, 88, "", DemoCityBuilding.Archetype.COMMERCIAL_SHOP],
		[530, 530, 3, 84, "PADARIA", DemoCityBuilding.Archetype.COMMERCIAL_SHOP],
		[624, 524, 1, 86, "", DemoCityBuilding.Archetype.COMMERCIAL_SHOP],
		[720, 530, 4, 82, "CONVENIÊNCIA", DemoCityBuilding.Archetype.COMMERCIAL_SHOP],
		# Quadra Oeste (Comercial / Residencial)
		[-1080, -240, 3, 176, "DELEGACIA OESTE", DemoCityBuilding.Archetype.MEDIUM_APARTMENT],
		[-1300, -260, 0, 182, "", DemoCityBuilding.Archetype.MEDIUM_APARTMENT],
		[-1520, -235, 5, 170, "", DemoCityBuilding.Archetype.MEDIUM_APARTMENT],
		[-1080, 510, 0, 174, "", DemoCityBuilding.Archetype.WAREHOUSE],
		[-1300, 535, 4, 180, "", DemoCityBuilding.Archetype.WAREHOUSE],
		[-1520, 515, 2, 168, "", DemoCityBuilding.Archetype.WAREHOUSE],
		# Quadra Leste (Financeira / Arranha-Céus)
		[1080, -240, 5, 176, "DELEGACIA LESTE", DemoCityBuilding.Archetype.SKYSCRAPER],
		[1300, -260, 2, 182, "CENTRAL TOWER", DemoCityBuilding.Archetype.SKYSCRAPER],
		[1520, -235, 0, 170, "WORLD TRADE", DemoCityBuilding.Archetype.SKYSCRAPER],
		[1080, 510, 1, 174, "", DemoCityBuilding.Archetype.SKYSCRAPER],
		[1300, 535, 3, 180, "BANK OF LOS SANTOS", DemoCityBuilding.Archetype.SKYSCRAPER],
		[1520, 515, 1, 168, "", DemoCityBuilding.Archetype.SKYSCRAPER]
	]
	var tints := [Color("f5f0e8"), Color("e8f0f7"), Color("f3e2d2"), Color("dce8dd"), Color("e2e8f0"), Color("efe5dc")]
	for index in range(placements.size()):
		var data: Array = placements[index]
		var building := BUILDING_SCENE.instantiate() as DemoCityBuilding
		building.name = "Building_%02d" % (index + 1)
		building.position = Vector2(float(data[0]), float(data[1]))
		building.archetype = data[5] as DemoCityBuilding.Archetype
		building.variant = int(data[2])
		building.visual_width = float(data[3])
		building.building_title = String(data[4])
		building.footprint = Vector2(building.visual_width * 0.82, 82.0)
		building.tint = tints[index % tints.size()]
		container.add_child(building)
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			building.owner = get_tree().edited_scene_root

func _add_district_sign(building: Node2D, text: String) -> void:
	var sign := Label.new()
	sign.text = text
	sign.position = Vector2(-68, 8)
	sign.size = Vector2(136, 20)
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.add_theme_font_size_override("font_size", 11)
	sign.add_theme_color_override("font_outline_color", Color.BLACK)
	sign.add_theme_constant_override("outline_size", 3)
	if "AMMU" in text:
		sign.add_theme_color_override("font_color", Color("f4d35e"))
	elif "DELEGACIA" in text:
		sign.add_theme_color_override("font_color", Color("72b8ff"))
	elif "HOSPITAL" in text:
		sign.add_theme_color_override("font_color", Color("7df1a4"))
	else:
		sign.add_theme_color_override("font_color", Color.WHITE)
	building.add_child(sign)

func _create_decor() -> void:
	var art_paths := [
		"res://city_demo/art/tree-street-small.png",
		"res://city_demo/art/tree-round-crown.png",
		"res://city_demo/art/shrub-cluster.png"
	]
	var positions := [
		Vector2(-560, -500), Vector2(-320, -510), Vector2(320, -500), Vector2(575, -500),
		Vector2(-580, 250), Vector2(-300, 260), Vector2(315, 270), Vector2(585, 260),
		Vector2(-950, -480), Vector2(-1200, -490), Vector2(-1420, -480),
		Vector2(950, -480), Vector2(1200, -490), Vector2(1420, -480),
		Vector2(-950, 260), Vector2(-1200, 270), Vector2(-1420, 260),
		Vector2(950, 260), Vector2(1200, 270), Vector2(1420, 260),
		Vector2(-80, -320), Vector2(80, -320), Vector2(-80, 320), Vector2(80, 320),
		# Árvores da calçada do Bairro-Piloto (não entram no asfalto).
		Vector2(190, 585), Vector2(290, 585), Vector2(390, 585), Vector2(490, 585),
		Vector2(590, 585), Vector2(690, 585)
	]
	for index in range(positions.size()):
		var texture := load(art_paths[index % art_paths.size()]) as Texture2D
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.position = positions[index]
		var target_width := 64.0 if index % 3 != 1 else 84.0
		var scale_factor := target_width / texture.get_width()
		sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.z_index = -3
		add_child(sprite)
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			sprite.owner = get_tree().edited_scene_root
		
	# Instancia pedestres com modelo humanoide 3D em tempo real nas calçadas
	var anim_3d_script = load("res://AnimatedPedestrian3D.gd")
	if anim_3d_script and not Engine.is_editor_hint():
		var ped_spawns := [
			Vector2(-280, -75), Vector2(280, -75), Vector2(-350, 75), Vector2(350, 75),
			Vector2(-75, -280), Vector2(75, 280), Vector2(-450, 480), Vector2(180, 480)
		]
		for p_pos in ped_spawns:
			var ped = anim_3d_script.new()
			ped.position = p_pos
			add_child(ped)

	# Instancia Postes de Luz Noturnos com iluminação âmbar nas calçadas (somente se enable_legacy_district estiver ativo)
	var lamp_script = load("res://StreetLamp.gd")
	if lamp_script and enable_legacy_district:
		var lamp_positions := [
			[Vector2(-420, -78), true], [Vector2(-180, -78), true],
			[Vector2(180, -78), true], [Vector2(420, -78), true],
			[Vector2(-420, 78), false], [Vector2(-180, 78), false],
			[Vector2(180, 78), false], [Vector2(420, 78), false],
			[Vector2(-78, -420), true], [Vector2(-78, -180), true],
			[Vector2(78, -420), true], [Vector2(78, -180), true],
			[Vector2(-78, 180), false], [Vector2(-78, 420), false],
			[Vector2(78, 180), false], [Vector2(78, 420), false]
		]
		for item in lamp_positions:
			var lamp = lamp_script.new()
			lamp.position = item[0]
			lamp.is_facing_south = (item[1] == true)
			add_child(lamp)
			if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
				lamp.owner = get_tree().edited_scene_root

func _load_vehicle_registry() -> void:
	var file := FileAccess.open("res://city_demo/data/traffic.json", FileAccess.READ)
	if file == null:
		push_error("Registro dos 50 veículos não pôde ser carregado.")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		vehicle_registry = parsed.get("signatureVehicles", [])
	if vehicle_registry.size() != 50:
		push_warning("Esperados 50 veículos no registro; encontrados %d." % vehicle_registry.size())

func _create_traffic() -> void:
	var traffic_root := Node2D.new()
	traffic_root.name = "BidirectionalTraffic"
	traffic_root.z_index = -2
	add_child(traffic_root)
	var lane_specs := [
		["CentralEast", PackedVector2Array([Vector2(-960, -32), Vector2(960, -32)]), [0.12, 0.46, 0.78]],
		["CentralWest", PackedVector2Array([Vector2(960, 32), Vector2(-960, 32)]), [0.18, 0.55, 0.86]],
		["CentralSouth", PackedVector2Array([Vector2(32, -768), Vector2(32, 768)]), [0.22, 0.68]],
		["CentralNorth", PackedVector2Array([Vector2(-32, 768), Vector2(-32, -768)]), [0.35, 0.82]],
		["OuterClockwise", PackedVector2Array([Vector2(-840, -648), Vector2(840, -648), Vector2(840, 648), Vector2(-840, 648), Vector2(-840, -648)]), [0.05]],
		["OuterCounterClockwise", PackedVector2Array([Vector2(-888, -696), Vector2(-888, 696), Vector2(888, 696), Vector2(888, -696), Vector2(-888, -696)]), [0.55]]
	]
	var registry_index := 0
	for lane_spec in lane_specs:
		var path := Path2D.new()
		path.name = String(lane_spec[0])
		var curve := Curve2D.new()
		for point in lane_spec[1]:
			curve.add_point(point)
		curve.bake_interval = 12.0
		path.curve = curve
		traffic_root.add_child(path)
		for phase in lane_spec[2]:
			var follow := PathFollow2D.new()
			follow.loop = true
			follow.rotates = true
			follow.cubic_interp = true
			path.add_child(follow)
			follow.progress_ratio = float(phase)
			var vehicle := VEHICLE_SCENE.instantiate() as DemoTrafficVehicle
			var entry: Dictionary = vehicle_registry[registry_index] if registry_index < vehicle_registry.size() else {}
			vehicle.vehicle_id = String(entry.get("instanceId", "demo_%02d" % registry_index))
			vehicle.display_name = String(entry.get("displayName", "Veículo %02d" % (registry_index + 1)))
			vehicle.characteristic = String(entry.get("characteristic", "Tráfego urbano"))
			vehicle.crop = VEHICLE_CROPS[registry_index % VEHICLE_CROPS.size()]
			vehicle.target_length = VEHICLE_LENGTHS[registry_index % VEHICLE_LENGTHS.size()]
			vehicle.speed = 88.0 + float((registry_index % 4) * 9)
			follow.add_child(vehicle)
			registry_index += 1
			instantiated_vehicle_count += 1

func _create_pedestrians() -> void:
	var container := Node2D.new()
	container.name = "NavigatingPedestrians"
	container.z_index = -1
	add_child(container)
	var routes: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-800, -608), Vector2(-448, -608), Vector2(-96, -608), Vector2(-96, -352), Vector2(-96, -96), Vector2(-448, -96), Vector2(-800, -96), Vector2(-800, -352)]),
		PackedVector2Array([Vector2(-96, -72), Vector2(-60, -72), Vector2(60, -72), Vector2(96, -72), Vector2(96, -250), Vector2(96, -72), Vector2(60, -72), Vector2(-60, -72), Vector2(-96, -72), Vector2(-96, -250)]),
		PackedVector2Array([Vector2(96, -608), Vector2(448, -608), Vector2(800, -608), Vector2(800, -352), Vector2(800, -96), Vector2(448, -96), Vector2(96, -96), Vector2(96, -352)]),
		PackedVector2Array([Vector2(72, -96), Vector2(72, -60), Vector2(72, 60), Vector2(72, 96), Vector2(250, 96), Vector2(72, 96), Vector2(72, 60), Vector2(72, -60), Vector2(72, -96), Vector2(250, -96)]),
		PackedVector2Array([Vector2(-800, 96), Vector2(-448, 96), Vector2(-96, 96), Vector2(-96, 352), Vector2(-96, 608), Vector2(-448, 608), Vector2(-800, 608), Vector2(-800, 352)]),
		PackedVector2Array([Vector2(-96, 72), Vector2(-60, 72), Vector2(60, 72), Vector2(96, 72), Vector2(96, 250), Vector2(96, 72), Vector2(60, 72), Vector2(-60, 72), Vector2(-96, 72), Vector2(-96, 250)]),
		PackedVector2Array([Vector2(96, 96), Vector2(448, 96), Vector2(800, 96), Vector2(800, 352), Vector2(800, 608), Vector2(448, 608), Vector2(96, 608), Vector2(96, 352)]),
		PackedVector2Array([Vector2(-72, -96), Vector2(-72, -60), Vector2(-72, 60), Vector2(-72, 96), Vector2(-250, 96), Vector2(-72, 96), Vector2(-72, 60), Vector2(-72, -60), Vector2(-72, -96), Vector2(-250, -96)])
	]
	for index in range(routes.size()):
		var pedestrian := PEDESTRIAN_SCENE.instantiate() as DemoPedestrian
		pedestrian.position = routes[index][0]
		pedestrian.identity = index % 8
		pedestrian.speed = 50.0 + float((index % 4) * 5)
		pedestrian.patrol_points = routes[index]
		container.add_child(pedestrian)

func _create_status_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "CityDemoStatus"
	panel.position = Vector2(-610, -330)
	panel.z_index = 50
	var label := Label.new()
	label.text = "DISTRITO FIXO · 4 QUADRAS\nTRÁFEGO: %d ATIVOS / %d REGISTRADOS\nPEDESTRES: 8 · NAVEGAÇÃO EM CALÇADAS" % [instantiated_vehicle_count, vehicle_registry.size()]
	label.add_theme_font_size_override("font_size", 12)
	panel.add_child(label)
	add_child(panel)
