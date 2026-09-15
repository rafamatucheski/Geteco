extends RefCounted
var previous: Array[Vector2] = []
var elapsed := 0.0
var ink: Node

func reset() -> void:
	previous.clear()
	elapsed = 0.0

func update(car: Node2D, delta: float, slipping: bool, intensity: float) -> void:
	if not slipping or not car.is_visible_in_tree() or car.get("is_flying") == true:
		reset()
		return
	elapsed += delta
	if elapsed < 0.05: return
	elapsed = 0.0
	var direction := car.global_transform.x.normalized()
	var collision := car.get_node_or_null("Collision") as CollisionShape2D
	if collision == null: collision = car.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var half_length := 23.0
	var half_width := 10.0
	if collision and collision.shape:
		var bounds := collision.shape.get_rect()
		half_length = bounds.size.x * absf(collision.scale.x * car.scale.x) * 0.5
		half_width = bounds.size.y * absf(collision.scale.y * car.scale.y) * 0.5
	var axle := car.global_position - direction * half_length * 0.60
	var contacts: Array[Vector2] = [axle + direction.orthogonal() * half_width * 0.78, axle - direction.orthogonal() * half_width * 0.78]
	# Use the actual authored wheels and the same camera as the body sprite.
	# The oblique 3D camera projects ground below the physical body's origin.
	var model = car.get("body_model")
	var viewport = car.get("body_viewport")
	var rig = car.get("wheel_rig")
	var display = car.get("sprite") if car.get("sprite") != null else car.get("visual")
	if model is Node3D and viewport is SubViewport and display is Sprite2D and rig != null and not rig.pivots.is_empty():
		var camera: Camera3D = viewport.get_camera_3d()
		if camera:
			var rear_z := -INF
			for pivot in rig.pivots: rear_z = maxf(rear_z, pivot.position.z)
			contacts.clear()
			for pivot in rig.pivots:
				if pivot.position.z < rear_z - 0.1: continue
				var ground := Vector3(pivot.position.x, 0, pivot.position.z)
				var projected := camera.unproject_position(model.to_global(ground)) - Vector2(viewport.size) * 0.5
				contacts.append(display.global_position + projected * display.global_scale)
	if previous.size() == contacts.size():
		if previous[0].distance_squared_to(contacts[0]) < 4.0: return
		if not is_instance_valid(ink): ink = preload("res://cars/VehicleSkidMarks.gd").ensure(car)
		for i in contacts.size(): ink.add_segment(previous[i], contacts[i], intensity)
	previous = contacts
