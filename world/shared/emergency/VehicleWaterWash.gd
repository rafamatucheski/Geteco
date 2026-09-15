extends Node2D
## Washing removes tire residue without repairing damage or changing paint.
var wetness := 0.0
var _phase := 0.0
var _size := Vector2(62, 26)

static func apply(vehicle: Node) -> void:
	preload("res://world/shared/combat/BloodTransferSystem.gd").wash(vehicle)
	if "bloody_tires_timer" in vehicle:
		vehicle.bloody_tires_timer = 0.0
		var skid: Line2D = vehicle.get("skid_line")
		if is_instance_valid(skid):
			skid.clear_points()
			skid.default_color = Color(0.1, 0.1, 0.1, 0.5)
	var wet := vehicle.get_node_or_null("WaterWash")
	if wet == null:
		wet = load("res://world/shared/emergency/VehicleWaterWash.gd").new()
		wet.name = "WaterWash"
		vehicle.add_child(wet)
	wet.wetness = 1.0
	wet.queue_redraw()

func _ready() -> void:
	z_index = 2
	var collision := get_parent().get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null: collision = get_parent().get_node_or_null("Collision") as CollisionShape2D
	if collision and collision.shape is RectangleShape2D: _size = collision.shape.size * 0.70

func _process(delta: float) -> void:
	wetness = maxf(0.0, wetness - delta / 3.5)
	_phase += delta
	queue_redraw()
	if wetness <= 0.0: queue_free()

func _draw() -> void:
	for i in 8:
		var point := Vector2(sin(float(i) * 17.3) * _size.x * 0.42, cos(float(i) * 5.7) * _size.y * 0.40)
		var alpha := wetness * (0.28 + 0.20 * sin(_phase * 5 + i))
		draw_line(point - Vector2(2.5, 0), point + Vector2(2.5, 0), Color(0.78, 0.94, 1, alpha), 1.2, true)
		draw_circle(point + Vector2(1, 2), 1.2, Color(0.6, 0.85, 1, wetness * 0.30))
