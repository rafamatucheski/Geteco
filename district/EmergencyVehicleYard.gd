class_name EmergencyVehicleYard
extends Node2D

## Collision-free operational forecourt for police/fire vehicles.
## The building remains a solid ProceduralBuilding; this sibling node belongs
## in the reserved outdoor portion of its lot.

@export_enum("police", "fire_station") var service_kind := "police"
@export var yard_size := Vector2(180, 80)
@export var road_direction := Vector2.DOWN
@export var debug_markers := false

var exit_marker: Marker2D
var return_marker: Marker2D
var bay_marker: Marker2D

func _ready() -> void:
	_create_markers()
	queue_redraw()

func _create_markers() -> void:
	if exit_marker != null:
		return
	var forward := road_direction.normalized()
	if forward.is_zero_approx():
		forward = Vector2.DOWN
	var across := Vector2(-forward.y, forward.x)
	var road_edge := forward * maxf(yard_size.x, yard_size.y) * 0.42
	exit_marker = Marker2D.new()
	exit_marker.name = "ExitMarker"
	exit_marker.position = road_edge + across * 20.0
	add_child(exit_marker)
	return_marker = Marker2D.new()
	return_marker.name = "ReturnMarker"
	return_marker.position = road_edge - across * 20.0
	add_child(return_marker)
	bay_marker = Marker2D.new()
	bay_marker.name = "BayMarker"
	bay_marker.position = -forward * minf(yard_size.x, yard_size.y) * 0.22
	add_child(bay_marker)

func get_exit_position() -> Vector2:
	return exit_marker.global_position if exit_marker != null else global_position

func get_return_position() -> Vector2:
	return return_marker.global_position if return_marker != null else global_position

func get_bay_position() -> Vector2:
	return bay_marker.global_position if bay_marker != null else global_position

func _draw() -> void:
	var bounds := Rect2(-yard_size * 0.5, yard_size)
	var accent := Color("#438fc0") if service_kind == "police" else Color("#d55042")
	draw_rect(bounds, Color("#4b504f"))
	draw_rect(bounds, Color("#272e30"), false, 2.0)
	# Concrete joints and numbered-looking bay bars provide scale without text.
	for y in range(int(bounds.position.y + 20), int(bounds.end.y), 24):
		draw_line(Vector2(bounds.position.x, y), Vector2(bounds.end.x, y), Color("#414746"), 1.0)
	var stall_width := yard_size.x / 3.0
	for i in 3:
		var x := bounds.position.x + stall_width * i
		draw_line(Vector2(x + 5, bounds.position.y + 5), Vector2(x + 5, bounds.end.y - 8), Color("#c7bd82"), 2.0)
	# Separate color-coded exit/return arrows: outgoing on the left, returning on
	# the right when facing the street.
	if exit_marker != null and return_marker != null:
		_draw_arrow(exit_marker.position, road_direction.normalized(), accent)
		_draw_arrow(return_marker.position, -road_direction.normalized(), accent.darkened(0.25))
	if debug_markers and bay_marker != null:
		draw_circle(bay_marker.position, 5, Color("#64e38a"))

func _draw_arrow(at: Vector2, direction: Vector2, color: Color) -> void:
	var forward := direction if not direction.is_zero_approx() else Vector2.DOWN
	var side := Vector2(-forward.y, forward.x)
	draw_colored_polygon(PackedVector2Array([
		at + forward * 9.0,
		at - forward * 7.0 + side * 6.0,
		at - forward * 3.0,
		at - forward * 7.0 - side * 6.0,
	]), color)
