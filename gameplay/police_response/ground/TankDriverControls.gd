extends Node
## Player controls are distinct from the police AI and the accelerator.
var vehicle: CharacterBody3D
var _reticle: Control
var _aim := Vector3.ZERO

class CannonReticle extends Control:
	var point := Vector2.ZERO
	var reloading := false
	func _draw() -> void:
		var tint := Color("f4c36d") if reloading else Color("f3f1df")
		draw_arc(point, 9.0, 0, TAU, 24, tint, 1.5, true)
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(point + direction * 12.0, point + direction * 17.0, tint, 1.5, true)

func configure(car: CharacterBody3D) -> void:
	vehicle = car

func _ready() -> void:
	name = "TankDriverControls"
	var layer := CanvasLayer.new()
	layer.layer = 7
	add_child(layer)
	_reticle = CannonReticle.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.hide()
	layer.add_child(_reticle)

func active_gameplay() -> Node3D:
	if not is_instance_valid(vehicle) or vehicle.health <= 0 or not vehicle.controlled or vehicle.external_input or vehicle.input_locked or vehicle.engine_disabled: return null
	if get_tree().paused: return null
	var world := vehicle.get_parent()
	if not is_instance_valid(world): return null
	var driving: Variant = world.get("driving")
	var gameplay: Variant = world.get("gameplay")
	if not is_instance_valid(driving) or not is_instance_valid(gameplay): return null
	if not driving.occupied or driving.car != vehicle or driving.is_body_transition_active(): return null
	if driving.has_method("_external_transition_blocked") and driving._external_transition_blocked(): return null
	if not gameplay.enabled or gameplay.health <= 0 or gameplay.state == null or not gameplay.state.weapons_allowed(): return null
	var controls := get_node_or_null("/root/GameInput")
	if controls != null and controls.remapping: return null
	return gameplay as Node3D

func _physics_process(delta: float) -> void:
	var gameplay := active_gameplay()
	_reticle.visible = gameplay != null
	if gameplay == null or not is_instance_valid(vehicle.tank_cannon): return
	var camera := vehicle.get_viewport().get_camera_3d()
	if camera == null: _reticle.hide(); return
	var controls := get_node_or_null("/root/GameInput")
	if controls != null and (controls.using_gamepad or not controls.touch_aim.is_zero_approx()):
		_aim = controls.aim_target_3d(vehicle, camera, delta, false)
		_aim.y = vehicle.global_position.y + 1.0
	else:
		var mouse := vehicle.get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mouse)
		var direction := camera.project_ray_normal(mouse)
		var hit: Variant = Plane(Vector3.UP, vehicle.global_position.y + 1.0).intersects_ray(origin, direction)
		if hit is Vector3: _aim = hit
	gameplay.aim_point = _aim
	vehicle.tank_cannon.aim_at(_aim, delta)
	if InputMap.has_action("tank_fire") and Input.is_action_pressed("tank_fire"):
		vehicle.tank_cannon.fire(gameplay, false)
	_reticle.visible = not camera.is_position_behind(_aim)
	_reticle.set("point", camera.unproject_position(_aim))
	_reticle.set("reloading", vehicle.tank_cannon.cooldown > 0.0)
	_reticle.queue_redraw()
