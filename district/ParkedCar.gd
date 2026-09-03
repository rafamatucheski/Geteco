class_name AuthoredParkedCar
extends StaticBody2D

## Lightweight, immobile street prop. It deliberately does not inherit the
## drivable vehicle: no AI, no camera and no update loop can start moving it.
@export var body_color := Color("#284c68")
@export var accent_color := Color("#a8c8d8")
@export var vehicle_length := 48.0
@export var vehicle_width := 22.0

func _ready() -> void:
	add_to_group("authored_parked_car")
	add_to_group("vehicle_obstacle")
	collision_layer = 2
	collision_mask = 0
	z_index = 3

	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(vehicle_length, vehicle_width)
	collision.shape = shape
	add_child(collision)
	queue_redraw()

func _draw() -> void:
	var half_length := vehicle_length * 0.5
	var half_width := vehicle_width * 0.5
	# Offset shadow, chassis, bumpers and glass give the same small procedural
	# top-down language as the current traffic placeholders.
	draw_rect(Rect2(-half_length + 3.0, -half_width + 4.0, vehicle_length, vehicle_width), Color(0.03, 0.04, 0.05, 0.42), true)
	draw_rect(Rect2(-half_length, -half_width, vehicle_length, vehicle_width), Color("#10151b"), true)
	draw_rect(Rect2(-half_length + 2.0, -half_width + 2.0, vehicle_length - 4.0, vehicle_width - 4.0), body_color, true)
	draw_rect(Rect2(-8.0, -half_width + 3.0, 19.0, vehicle_width - 6.0), accent_color.darkened(0.22), true)
	draw_line(Vector2(-8.0, -half_width + 3.0), Vector2(-8.0, half_width - 3.0), Color("#d6e8ee"), 1.2)
	draw_line(Vector2(11.0, -half_width + 3.0), Vector2(11.0, half_width - 3.0), Color("#d6e8ee"), 1.2)
	for wheel_x in [-14.0, 14.0]:
		draw_rect(Rect2(wheel_x - 4.0, -half_width - 2.0, 8.0, 4.0), Color("#07090c"), true)
		draw_rect(Rect2(wheel_x - 4.0, half_width - 2.0, 8.0, 4.0), Color("#07090c"), true)
	# Small warm rear lights / pale headlights make orientation readable.
	draw_rect(Rect2(-half_length + 1.0, -half_width + 3.0, 3.0, 5.0), Color("#d84c3f"), true)
	draw_rect(Rect2(-half_length + 1.0, half_width - 8.0, 3.0, 5.0), Color("#d84c3f"), true)
	draw_rect(Rect2(half_length - 4.0, -half_width + 3.0, 3.0, 5.0), Color("#f1e6bd"), true)
	draw_rect(Rect2(half_length - 4.0, half_width - 8.0, 3.0, 5.0), Color("#f1e6bd"), true)
