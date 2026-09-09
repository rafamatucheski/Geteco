extends Node
## Shared boarding motion; coordinates stay relative to the car, including on bridges.
var active := false
var side := -1.0
var phase := "approach"
var car: CharacterBody2D
var actor: CharacterBody2D
var motion: Tween
var original_color := Color.WHITE
var offset := Vector2.ZERO
var control_was_disabled := false

func begin(vehicle: CharacterBody2D, pedestrian: CharacterBody2D, approach: Vector2, entry_side: float) -> void:
	car = vehicle
	actor = pedestrian
	side = entry_side
	original_color = actor.modulate
	offset = car.to_local(approach)
	active = true
	if "is_control_disabled" in actor:
		control_was_disabled = actor.is_control_disabled
		actor.is_control_disabled = true
	car.set_meta("vehicle_boarding", true)
	actor.show()
	actor.global_position = approach
	actor.global_rotation = car.global_rotation
	var half_width := 18.0
	var collider := car.get_node_or_null("Collision") as CollisionShape2D
	if collider != null and collider.shape is RectangleShape2D:
		half_width = collider.shape.size.y * 0.5
	motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(self, "offset", Vector2(-5, side*(half_width+6)), 0.25)
	motion.tween_callback(func(): phase = "enter")
	motion.tween_property(self, "offset", Vector2(-5, side*7), 0.3)
	motion.parallel().tween_property(actor, "modulate:a", 0.0, 0.3)
	if side > 0:
		motion.tween_callback(func(): phase = "change_seat")
		motion.tween_property(self, "offset", Vector2(-5,-7), 0.35)
	# Keep controls locked through the final door-closing swing.
	motion.tween_interval(0.6)
	motion.tween_callback(_finish)

func _process(_delta: float) -> void:
	if not active: return
	if not is_instance_valid(actor) or not is_instance_valid(car):
		cancel()
		return
	actor.global_position = car.to_global(offset)

func _finish() -> void:
	active = false
	phase = "seated"
	car.remove_meta("vehicle_boarding")
	car._drive_input_armed = false
	actor.hide()
	if "is_control_disabled" in actor: actor.is_control_disabled = control_was_disabled
	actor.modulate = original_color
	actor.global_position = car.global_position
	queue_free()

func cancel() -> void:
	if motion: motion.kill()
	active = false
	if is_instance_valid(car): car.remove_meta("vehicle_boarding")
	if is_instance_valid(actor):
		actor.modulate = original_color
		if "is_control_disabled" in actor: actor.is_control_disabled = control_was_disabled
	queue_free()

func _exit_tree() -> void:
	if not active or not is_instance_valid(actor): return
	actor.modulate = original_color
	if "is_control_disabled" in actor: actor.is_control_disabled = control_was_disabled
	actor.show()
	actor.set_physics_process(true)
	for shape in actor.find_children("", "CollisionShape2D", true, false):
		shape.set_deferred("disabled", false)
