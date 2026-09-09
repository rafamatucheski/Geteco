class_name ProceduralVehicleDoor
extends Node2D

## Top-down door panel. The origin is the front outer hinge of the car,
## allowing a normal swing away from the roof instead of a loose rectangle.

const OPEN_ANGLE := deg_to_rad(64.0)

var _door_length := 32.0
var _shadow: Polygon2D
var _panel: Polygon2D
var _window: Polygon2D
var _edge_highlight: Line2D
var _seam: Line2D
var _handle: Line2D
var _hinge: Polygon2D
var _active_tween: Tween


func configure(hinge_position: Vector2, door_length: float) -> void:
	position = hinge_position
	_door_length = clampf(door_length, 26.0, 42.0)
	if is_inside_tree():
		_rebuild_geometry()


func _ready() -> void:
	# Vehicles use z=10. Keeping the door just above it makes the panel read as
	# part of the side bodywork, rather than as a foreground prop.
	z_index = 12
	visible = false
	_rebuild_geometry()


func play(body_color: Color, side: float = -1.0, hold_seconds: float = 0.42) -> void:
	if _active_tween != null and _active_tween.is_running():
		_active_tween.kill()
	position.y = absf(position.y)*side
	scale.y = -side
	_apply_palette(body_color)
	visible = true
	rotation = 0.0
	_play_door_sound(ProceduralAudio.get_car_door_open_stream(), -8.0)

	# The configured hinge is on the upper/passenger side of vehicles. Positive
	# rotation swings the long edge outward (towards -Y), never across the roof.
	_active_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "rotation", OPEN_ANGLE * -side, 0.28)
	_active_tween.tween_property(self, "rotation", (OPEN_ANGLE - deg_to_rad(3.0)) * -side, 0.06)
	_active_tween.tween_interval(hold_seconds)
	_active_tween.set_ease(Tween.EASE_IN)
	_active_tween.tween_property(self, "rotation", 0.0, 0.26)
	_active_tween.tween_callback(_finish_close)


func _rebuild_geometry() -> void:
	for child in get_children():
		child.queue_free()

	# Closed: a shallow strip following the car side. The front hinge remains at
	# x=0; the rear of the door extends backwards along the vehicle's local X.
	var outer_edge := 6.8
	var body_panel := PackedVector2Array([
		Vector2(1.2, -1.2),
		Vector2(-_door_length * 0.18, -2.1),
		Vector2(-_door_length * 0.90, -2.0),
		Vector2(-_door_length, 0.6),
		Vector2(-_door_length * 0.92, outer_edge),
		Vector2(-_door_length * 0.16, outer_edge + 0.7),
		Vector2(1.2, 4.2),
	])

	_shadow = Polygon2D.new()
	_shadow.name = "DoorContactShadow"
	_shadow.polygon = body_panel
	_shadow.position = Vector2(1.2, 2.2)
	_shadow.z_index = -1
	add_child(_shadow)

	_panel = Polygon2D.new()
	_panel.name = "PaintedDoorPanel"
	_panel.polygon = body_panel
	add_child(_panel)

	# A small glazed insert keeps the car readable but never overwhelms the
	# painted sheet (the old large black surface looked like a detached object).
	_window = Polygon2D.new()
	_window.name = "DoorGlass"
	_window.polygon = PackedVector2Array([
		Vector2(-_door_length * 0.25, -0.85),
		Vector2(-_door_length * 0.73, -0.76),
		Vector2(-_door_length * 0.80, 1.20),
		Vector2(-_door_length * 0.31, 1.35),
	])
	_window.z_index = 1
	add_child(_window)

	_edge_highlight = Line2D.new()
	_edge_highlight.name = "DoorPaintEdge"
	_edge_highlight.width = 1.15
	_edge_highlight.antialiased = true
	_edge_highlight.points = PackedVector2Array([
		Vector2(-_door_length * 0.10, 4.5),
		Vector2(-_door_length * 0.88, 6.15),
	])
	_edge_highlight.z_index = 2
	add_child(_edge_highlight)

	_seam = Line2D.new()
	_seam.name = "DoorSeam"
	_seam.width = 1.0
	_seam.antialiased = true
	_seam.points = PackedVector2Array([
		Vector2(-_door_length * 0.93, -0.9),
		Vector2(-_door_length * 0.98, 3.8),
	])
	_seam.z_index = 2
	add_child(_seam)

	_handle = Line2D.new()
	_handle.name = "DoorHandle"
	_handle.width = 1.25
	_handle.antialiased = true
	_handle.points = PackedVector2Array([
		Vector2(-_door_length * 0.68, 3.35),
		Vector2(-_door_length * 0.53, 3.12),
	])
	_handle.z_index = 3
	add_child(_handle)

	_hinge = Polygon2D.new()
	_hinge.name = "DoorHinge"
	_hinge.polygon = PackedVector2Array([
		Vector2(-1.2, -2.7), Vector2(1.8, -2.7),
		Vector2(1.8, 2.7), Vector2(-1.2, 2.7),
	])
	_hinge.z_index = 3
	add_child(_hinge)

	_apply_palette(Color("#3c6382"))


func _apply_palette(body_color: Color) -> void:
	if _panel == null:
		return
	var paint := body_color
	paint.a = 1.0
	_panel.color = paint
	_shadow.color = Color(0.015, 0.02, 0.03, 0.44)
	_window.color = Color("#24394a").lerp(paint.darkened(0.34), 0.15)
	_edge_highlight.default_color = paint.lightened(0.30)
	_seam.default_color = paint.darkened(0.56)
	_handle.default_color = paint.lightened(0.48)
	_hinge.color = paint.darkened(0.48)


func _finish_close() -> void:
	visible = false
	_play_door_sound(ProceduralAudio.get_car_door_close_stream(), -5.0)


func _play_door_sound(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = 500.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
