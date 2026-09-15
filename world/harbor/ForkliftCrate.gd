extends CharacterBody2D
var collision: CollisionShape2D
var visual: Node2D
var _heading := INF
var broken := false

func _ready() -> void:
	add_to_group("forklift_cargo")
	collision_layer = 2
	collision_mask = 3
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	z_index = 5
	collision = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24, 22)
	collision.shape = shape
	add_child(collision)
	visual = preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	add_child(visual)
	visual.build_view(preload("res://world/harbor/ForkliftCrateModel.gd"),3.2,17.0,Vector3(0,.45,0),Vector3(0,7.55,4))
	visual.viewport_3d.size = Vector2i(192,160)
	# build_view calibrated at 960x800; keep the same world scale at this size.
	visual.sprite_3d.scale *= 5.0
	# Match the vehicle cameras' .45 m target, including their ground offset.
	visual.sprite_3d.position = Vector2.ZERO
	update_orientation()

func update_orientation() -> void:
	visual.global_rotation = 0
	if not is_equal_approx(_heading, global_rotation):
		visual.model.rotation.y = -global_rotation
		visual.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
		_heading = global_rotation

func receive_vehicle_impact(speed: float, direction: Vector2) -> void:
	if broken: return
	if speed >= 65:
		broken = true
		remove_from_group("forklift_cargo")
		collision_layer = 0
		collision_mask = 0
		visual.hide()
		preload("res://guns/ImpactDebris.gd").spawn(get_parent(),global_position,direction,speed,"wood")
		velocity = Vector2.ZERO
		return
	velocity += direction * minf(speed * .5, 70)

func restore_world_prop() -> void:
	broken = false
	velocity = Vector2.ZERO
	add_to_group("forklift_cargo")
	visual.show()
	update_orientation()

func _physics_process(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 100 * delta)
	if not velocity.is_zero_approx(): move_and_slide()
	update_orientation()
