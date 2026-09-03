@tool
class_name CityGridBuilder
extends Node2D

const ROAD_SEGMENT_SCRIPT = preload("res://city_demo/scripts/roads/CityRoadSegment.gd")
const INTERSECTION_SCRIPT = preload("res://city_demo/scripts/roads/CityIntersection.gd")
const BUILDING_SCENE = preload("res://city_demo/scenes/CityBuilding.tscn")
const PARKING_LOT_SCRIPT = preload("res://city_demo/scripts/roads/CityParkingLot.gd")

@export_group("Grid Dimensions")
@export_range(1, 10, 1) var grid_columns: int = 3:
	set(c):
		grid_columns = c
		queue_redraw()

@export_range(1, 10, 1) var grid_rows: int = 2:
	set(r):
		grid_rows = r
		queue_redraw()

@export var block_size: Vector2 = Vector2(420.0, 320.0):
	set(bs):
		block_size = bs
		queue_redraw()

@export var street_width: float = 96.0:
	set(sw):
		street_width = maxf(sw, 32.0)
		queue_redraw()

@export var sidewalk_width: float = 28.0:
	set(sw):
		sidewalk_width = maxf(sw, 8.0)
		queue_redraw()

@export_group("Spawning Options")
@export var auto_spawn_intersections: bool = true
@export var auto_spawn_road_segments: bool = true
@export var auto_spawn_buildings: bool = true
@export var zone_archetypes: bool = true

@export_group("Actions")
@export var build_grid_now: bool = false:
	set(v):
		if v:
			build_grid_now = false
			generate_grid()

@export var clear_grid_now: bool = false:
	set(v):
		if v:
			clear_grid_now = false
			clear_grid()

func clear_grid() -> void:
	for child in get_children():
		child.queue_free()

func generate_grid() -> void:
	clear_grid()

	var streets_root := Node2D.new()
	streets_root.name = "GeneratedStreets"
	add_child(streets_root)
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		streets_root.owner = get_tree().edited_scene_root

	var buildings_root := Node2D.new()
	buildings_root.name = "GeneratedBuildings"
	buildings_root.y_sort_enabled = true
	add_child(buildings_root)
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		buildings_root.owner = get_tree().edited_scene_root

	var cell_step_x := block_size.x + street_width
	var cell_step_y := block_size.y + street_width
	var total_w := float(grid_columns) * cell_step_x
	var total_h := float(grid_rows) * cell_step_y
	var origin := Vector2(-total_w * 0.5 + cell_step_x * 0.5, -total_h * 0.5 + cell_step_y * 0.5)

	# 1. Spawn Intersections & Road Segments
	for row in range(grid_rows + 1):
		for col in range(grid_columns + 1):
			var node_pos := origin + Vector2(float(col) * cell_step_x - cell_step_x * 0.5, float(row) * cell_step_y - cell_step_y * 0.5)

			# Intersections at junctions
			if auto_spawn_intersections:
				var inter = INTERSECTION_SCRIPT.new()
				inter.name = "Intersection_%d_%d" % [col, row]
				inter.position = node_pos
				inter.road_width = street_width
				inter.sidewalk_width = sidewalk_width
				streets_root.add_child(inter)
				if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
					inter.owner = get_tree().edited_scene_root

			# Horizontal Road Segments
			if auto_spawn_road_segments and col < grid_columns:
				var road_h = ROAD_SEGMENT_SCRIPT.new()
				road_h.name = "Road_H_%d_%d" % [col, row]
				road_h.position = node_pos + Vector2(cell_step_x * 0.5, 0.0)
				road_h.length = block_size.x
				road_h.road_width = street_width
				road_h.sidewalk_width = sidewalk_width
				road_h.orientation = 0 # Horizontal
				streets_root.add_child(road_h)
				if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
					road_h.owner = get_tree().edited_scene_root

			# Vertical Road Segments
			if auto_spawn_road_segments and row < grid_rows:
				var road_v = ROAD_SEGMENT_SCRIPT.new()
				road_v.name = "Road_V_%d_%d" % [col, row]
				road_v.position = node_pos + Vector2(0.0, cell_step_y * 0.5)
				road_v.length = block_size.y
				road_v.road_width = street_width
				road_v.sidewalk_width = sidewalk_width
				road_v.orientation = 1 # Vertical
				streets_root.add_child(road_v)
				if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
					road_v.owner = get_tree().edited_scene_root

	# 2. Spawn Block Buildings by Archetype Zone
	if auto_spawn_buildings:
		for row in range(grid_rows):
			for col in range(grid_columns):
				var block_center := origin + Vector2(float(col) * cell_step_x, float(row) * cell_step_y)
				_populate_block(buildings_root, block_center, col, row)

func _populate_block(parent: Node2D, center: Vector2, col: int, row: int) -> void:
	var block_idx := row * grid_columns + col
	# Archetype zoning
	if block_idx == 0:
		# Financial / Skyscraper block
		_spawn_building(parent, center + Vector2(-block_size.x * 0.25, 0), DemoCityBuilding.Archetype.SKYSCRAPER, "FINANCIAL TOWER", 190.0)
		_spawn_building(parent, center + Vector2(block_size.x * 0.25, 0), DemoCityBuilding.Archetype.SKYSCRAPER, "CITICORP CENTER", 180.0)
	elif block_idx == 1:
		# Central Park Plaza
		_spawn_building(parent, center, DemoCityBuilding.Archetype.PARK_PLAZA, "PRAÇA CENTRAL DA CIDADE", block_size.x * 0.75)
	elif block_idx == 2:
		# Commercial Strip
		_spawn_building(parent, center + Vector2(-block_size.x * 0.3, 0), DemoCityBuilding.Archetype.COMMERCIAL_SHOP, "AMMU-NATION", 100.0)
		_spawn_building(parent, center, DemoCityBuilding.Archetype.COMMERCIAL_SHOP, "AUTO PEÇAS", 95.0)
		_spawn_building(parent, center + Vector2(block_size.x * 0.3, 0), DemoCityBuilding.Archetype.COMMERCIAL_SHOP, "SUPERMERCADO", 105.0)
	elif block_idx == 3:
		# Industrial Warehouse & Garage
		_spawn_building(parent, center + Vector2(-block_size.x * 0.2, 0), DemoCityBuilding.Archetype.WAREHOUSE, "GALPÃO CENTRAL #1", 210.0)
		# Parking Lot
		var lot = PARKING_LOT_SCRIPT.new()
		lot.position = center + Vector2(block_size.x * 0.3, 0)
		lot.spots_per_row = 4
		parent.add_child(lot)
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			lot.owner = get_tree().edited_scene_root
	elif block_idx == 4:
		# Medium Residential Apartments
		_spawn_building(parent, center + Vector2(-block_size.x * 0.25, 0), DemoCityBuilding.Archetype.MEDIUM_APARTMENT, "RESIDENCIAL SOLAR", 155.0)
		_spawn_building(parent, center + Vector2(block_size.x * 0.25, 0), DemoCityBuilding.Archetype.MEDIUM_APARTMENT, "CONDOMÍNIO HORIZONTE", 160.0)
	else:
		# Suburban Houses
		_spawn_building(parent, center + Vector2(-block_size.x * 0.32, 0), DemoCityBuilding.Archetype.SUBURBAN_HOUSE, "", 85.0)
		_spawn_building(parent, center, DemoCityBuilding.Archetype.SUBURBAN_HOUSE, "", 85.0)
		_spawn_building(parent, center + Vector2(block_size.x * 0.32, 0), DemoCityBuilding.Archetype.SUBURBAN_HOUSE, "", 85.0)

func _spawn_building(parent: Node2D, pos: Vector2, archetype: DemoCityBuilding.Archetype, title: String, width: float) -> void:
	var b := BUILDING_SCENE.instantiate() as DemoCityBuilding
	b.position = pos
	b.archetype = archetype
	b.visual_width = width
	b.building_title = title
	parent.add_child(b)
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		b.owner = get_tree().edited_scene_root

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# Draw editor preview bounding boxes for level design reference
	var cell_step_x := block_size.x + street_width
	var cell_step_y := block_size.y + street_width
	var total_w := float(grid_columns) * cell_step_x
	var total_h := float(grid_rows) * cell_step_y
	var origin := Vector2(-total_w * 0.5 + cell_step_x * 0.5, -total_h * 0.5 + cell_step_y * 0.5)

	for row in range(grid_rows):
		for col in range(grid_columns):
			var bcenter := origin + Vector2(float(col) * cell_step_x, float(row) * cell_step_y)
			var brect := Rect2(bcenter.x - block_size.x * 0.5, bcenter.y - block_size.y * 0.5, block_size.x, block_size.y)
			draw_rect(brect, Color(0.2, 0.6, 1.0, 0.08))
			draw_rect(brect, Color(0.2, 0.6, 1.0, 0.4), false, 1.5)
