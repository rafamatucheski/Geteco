extends CharacterBody2D
## Ground-plane physics paired with an independently rendered 3D object.
var cargo_material := "wood"
var mass_kg := 45.0
var resistance := 65.0
var friction := 110.0
var health := 65.0
var dent := 0.0
var broken := false
var extent := Vector2(24, 22)
var view: Node2D
var _impact_cooldown := 0.0
var _undamaged_model := Transform3D.IDENTITY
var _model_damage_captured := false

func _ready() -> void:
	preload("res://ContactShadow.gd").add_box(self, extent * 1.05, 0.48)
	motion_mode = MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	collision_layer = 1
	collision_mask = 3
	add_to_group("damageable")
	add_to_group("physical_cargo")
	set_meta("impact_material", "wood" if cargo_material == "plastic" else cargo_material)

func push_by_person(direction: Vector2, speed: float) -> void:
	if broken: return
	velocity = direction.normalized() * minf(speed, 1600.0 / mass_kg)

func receive_vehicle_impact(speed: float, direction: Vector2) -> void:
	if broken or not direction.is_finite() or not is_finite(speed): return
	velocity = (velocity + direction.normalized() * speed * 90.0 / (mass_kg + 30.0)).limit_length(330.0)
	if speed < 25.0 or _impact_cooldown > 0.0: return
	_impact_cooldown = 0.18
	_damage(maxf(0.0, speed - 25.0) * 0.6, direction)

func take_damage(amount: int, _player_attacker := false) -> void:
	if broken: return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var direction := Vector2.RIGHT if player == null else player.global_position.direction_to(global_position)
	velocity += direction * minf(65.0, float(amount) * 60.0 / mass_kg)
	_damage(float(amount), direction)

func _damage(amount: float, direction: Vector2) -> void:
	if is_instance_valid(view) and not _model_damage_captured:
		_undamaged_model = view.model.transform
		_model_damage_captured = true
	health -= amount
	if cargo_material == "metal":
		dent = minf(0.65, dent + amount / (resistance * 3.0))
		if is_instance_valid(view):
			view.model.scale = Vector3(1.0 - dent * 0.5, 1.0 - dent * 0.28, 1.0 + dent * 0.2)
			view.model.rotation.z = dent * 0.2 * signf(direction.x)
			view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	elif health <= 0.0:
		broken = true
		if has_node("ContactShadow"): $ContactShadow.hide()
		collision_layer = 0
		collision_mask = 0
		if is_instance_valid(view): view.hide()
		preload("res://guns/ImpactDebris.gd").spawn(get_parent(), global_position, direction, velocity.length(), cargo_material, extent)
		velocity = Vector2.ZERO

func restore_world_prop() -> void:
	broken = false
	if has_node("ContactShadow"): $ContactShadow.show()
	health = resistance
	dent = 0.0
	velocity = Vector2.ZERO
	if is_instance_valid(view):
		view.show()
		if _model_damage_captured:
			view.model.transform = _undamaged_model
			view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	_model_damage_captured = false

func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	if broken or velocity.is_zero_approx(): return
	var incoming := velocity
	var hit := move_and_collide(velocity * delta)
	if hit:
		var other := hit.get_collider()
		if other != null and other.has_method("receive_vehicle_impact"):
			other.receive_vehicle_impact(maxf(0.0, -incoming.dot(hit.get_normal())) * 0.6, incoming.normalized())
		velocity = incoming.slide(hit.get_normal()) * 0.65
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
