extends StaticBody2D
## Only vehicle contacts drive the pole's reaction; walking remains solid.
const FALL_SPEED := 35.0
var broken := false
var _impact_tween: Tween
var _next_wobble := 0

func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("obstacle")
	add_to_group("metal_prop")
	add_to_group("fragile_road_post")
	var shape := CollisionShape2D.new()
	var base := RectangleShape2D.new()
	base.size = Vector2(8, 4)
	shape.shape = base
	shape.position = Vector2(0, 9)
	add_child(shape)

func receive_vehicle_impact(speed: float, direction: Vector2) -> void:
	if broken or not is_finite(speed) or not direction.is_finite() or speed < 15:
		return
	if speed < FALL_SPEED and Time.get_ticks_msec() < _next_wobble:
		return
	_next_wobble = Time.get_ticks_msec() + 650
	if _impact_tween: _impact_tween.kill()
	_impact_tween = create_tween()
	var lean := 1.0 if direction.x >= 0 else -1.0
	if speed >= FALL_SPEED:
		broken = true
		collision_layer = 0
		for child in get_children():
			if child is CollisionShape2D: child.set_deferred("disabled", true)
		for bulb in get_node("SignalBox").get_children():
			bulb.color = Color("202428")
		_impact_tween.tween_property(self, "rotation", lean * PI * .49, .45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		_impact_tween.tween_property(self, "rotation", lean * .09, .12)
		_impact_tween.tween_property(self, "rotation", 0.0, .35)

func restore_world_prop() -> void:
	if _impact_tween: _impact_tween.kill()
	broken = false
	rotation = 0
	_next_wobble = 0
	collision_layer = 1
	for child in get_children():
		if child is CollisionShape2D: child.set_deferred("disabled", false)
	var manager := get_tree().root.get_node_or_null("TrafficLightManager")
	if manager: manager._update_visuals()
