@tool
class_name CityParkingLot
extends Node2D

enum ParkingLayout {
	SINGLE_ROW,
	DOUBLE_ROW_FACING,
	PERIMETER_GRID
}

enum BayAngle {
	DEGREE_90,
	DEGREE_60,
	DEGREE_45
}

const VEHICLE_ATLAS: Texture2D = preload("res://city_demo/art/vehicle-atlas.png")
const LAMP_SCENE: PackedScene = preload("res://StreetLamp.tscn")

@export var parking_layout: ParkingLayout = ParkingLayout.DOUBLE_ROW_FACING:
	set(pl):
		parking_layout = pl
		_update_lot()

@export var bay_angle: BayAngle = BayAngle.DEGREE_90:
	set(ba):
		bay_angle = ba
		_update_lot()

@export_range(2, 20, 1) var spots_per_row: int = 6:
	set(spr):
		spots_per_row = spr
		_update_lot()

@export var spot_width: float = 34.0:
	set(sw):
		spot_width = maxf(sw, 20.0)
		_update_lot()

@export var spot_length: float = 58.0:
	set(sl):
		spot_length = maxf(sl, 30.0)
		_update_lot()

@export var aisle_width: float = 64.0:
	set(aw):
		aisle_width = maxf(aw, 30.0)
		_update_lot()

@export_range(0, 4, 1) var handicapped_spots: int = 1:
	set(hs):
		handicapped_spots = hs
		queue_redraw()

@export var has_wheel_stops: bool = true:
	set(val):
		has_wheel_stops = val
		queue_redraw()

@export var has_painted_arrows: bool = true:
	set(val):
		has_painted_arrows = val
		queue_redraw()

@export var has_perimeter_curb: bool = true:
	set(val):
		has_perimeter_curb = val
		queue_redraw()

@export var curb_sidewalk_width: float = 16.0:
	set(csw):
		curb_sidewalk_width = maxf(csw, 4.0)
		_update_lot()

@export var has_lot_lighting: bool = true:
	set(val):
		has_lot_lighting = val
		_update_lighting()

# --- COLORS ---
@export_group("Colors")
@export var asphalt_color: Color = Color("282c34"):
	set(c):
		asphalt_color = c
		queue_redraw()

@export var curb_color: Color = Color("cbd5e1"):
	set(c):
		curb_color = c
		queue_redraw()

@export var line_color: Color = Color("f1f5f9"):
	set(c):
		line_color = c
		queue_redraw()

@export var handicapped_blue: Color = Color("0284c7"):
	set(c):
		handicapped_blue = c
		queue_redraw()

var lighting_container: Node2D

func _ready() -> void:
	_update_lot()
	add_to_group("city_parking_lot")

func _update_lot() -> void:
	_update_lighting()
	queue_redraw()

func _update_lighting() -> void:
	if lighting_container == null:
		lighting_container = get_node_or_null("LightingContainer") as Node2D
		if lighting_container == null:
			lighting_container = Node2D.new()
			lighting_container.name = "LightingContainer"
			add_child(lighting_container)

	for child in lighting_container.get_children():
		child.queue_free()

	if has_lot_lighting and LAMP_SCENE != null:
		var row_w := spot_width * float(spots_per_row)
		var half_w := row_w * 0.5
		# Corner & median light poles
		var lamp_l = LAMP_SCENE.instantiate()
		lamp_l.position = Vector2(-half_w + 12, 0)
		lighting_container.add_child(lamp_l)

		var lamp_r = LAMP_SCENE.instantiate()
		lamp_r.position = Vector2(half_w - 12, 0)
		lighting_container.add_child(lamp_r)

func _get_lot_dimensions() -> Vector2:
	var total_w := spot_width * float(spots_per_row)
	var rows_count := 2 if parking_layout == ParkingLayout.DOUBLE_ROW_FACING else 1
	var total_h := (spot_length * float(rows_count)) + (aisle_width if rows_count > 1 else aisle_width * 0.5)
	return Vector2(total_w, total_h)

func _draw() -> void:
	var lot_size := _get_lot_dimensions()
	var half_w := lot_size.x * 0.5
	var half_h := lot_size.y * 0.5

	# 1. Perimeter Curb & Sidewalk
	if has_perimeter_curb:
		var curb_rect := Rect2(-half_w - curb_sidewalk_width, -half_h - curb_sidewalk_width, lot_size.x + curb_sidewalk_width * 2.0, lot_size.y + curb_sidewalk_width * 2.0)
		draw_rect(curb_rect, Color("94a3b8"))
		draw_rect(curb_rect, curb_color, false, 2.0)

	# 2. Main Asphalt Surface
	var asphalt_rect := Rect2(-half_w, -half_h, lot_size.x, lot_size.y)
	draw_rect(asphalt_rect, asphalt_color)

	# 3. Parking Bays
	var is_double := parking_layout == ParkingLayout.DOUBLE_ROW_FACING

	# North Row (Facing Down)
	var top_y := -half_h
	for i in range(spots_per_row):
		var bx := -half_w + float(i) * spot_width
		var spot_rect := Rect2(bx, top_y, spot_width, spot_length)
		_draw_parking_spot(spot_rect, i < handicapped_spots, true)

	# South Row (Facing Up)
	if is_double:
		var bot_y := half_h - spot_length
		for i in range(spots_per_row):
			var bx := -half_w + float(i) * spot_width
			var spot_rect := Rect2(bx, bot_y, spot_width, spot_length)
			_draw_parking_spot(spot_rect, false, false)

	# 4. Drive Aisle Direction Arrows
	if has_painted_arrows:
		var arrow_y := 0.0 if is_double else (-half_h + spot_length + aisle_width * 0.25)
		_draw_drive_arrow(Vector2(-half_w * 0.4, arrow_y), Vector2.RIGHT)
		_draw_drive_arrow(Vector2(half_w * 0.4, arrow_y), Vector2.RIGHT)

func _draw_parking_spot(rect: Rect2, is_hc: bool, is_facing_south: bool) -> void:
	# Stall white borders
	draw_line(rect.position, Vector2(rect.position.x, rect.end.y), line_color, 2.0)
	draw_line(Vector2(rect.end.x, rect.position.y), rect.end, line_color, 2.0)

	# Handicapped blue box & symbol
	if is_hc:
		var hc_rect := rect.grow(-4.0)
		draw_rect(hc_rect, handicapped_blue)
		var center := hc_rect.get_center()
		# Wheelchair icon (circle head + lines)
		draw_circle(center + Vector2(0, -6), 3.0, Color.WHITE)
		draw_line(center + Vector2(0, -3), center + Vector2(0, 4), Color.WHITE, 2.0)
		draw_line(center + Vector2(0, 1), center + Vector2(5, 1), Color.WHITE, 2.0)
		draw_arc(center + Vector2(0, 4), 4.5, 0, PI * 0.8, 16, Color.WHITE, 2.0)

	# Concrete Wheel Stops (bumper blocks)
	if has_wheel_stops:
		var bumper_w := spot_width * 0.7
		var bumper_h := 5.0
		var by := rect.position.y + 6.0 if is_facing_south else rect.end.y - 11.0
		var bx := rect.position.x + (spot_width - bumper_w) * 0.5
		draw_rect(Rect2(bx, by, bumper_w, bumper_h), Color("cbd5e1"))
		draw_rect(Rect2(bx, by, bumper_w, bumper_h), Color("475569"), false, 1.0)

func _draw_drive_arrow(pos: Vector2, dir: Vector2) -> void:
	var stem_len := 18.0
	var head_len := 8.0
	var arrow_col := Color(1.0, 1.0, 1.0, 0.85)
	# Shaft
	draw_line(pos - dir * (stem_len * 0.5), pos + dir * (stem_len * 0.5), arrow_col, 3.0)
	# Arrowhead
	var perp := Vector2(-dir.y, dir.x)
	var tip := pos + dir * (stem_len * 0.5)
	var left := tip - dir * head_len + perp * head_len * 0.6
	var right := tip - dir * head_len - perp * head_len * 0.6
	draw_line(tip, left, arrow_col, 3.0)
	draw_line(tip, right, arrow_col, 3.0)
