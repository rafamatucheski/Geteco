class_name VehicleBrakeLights
extends Node2D

## Luzes de freio desenhadas no canvas. Não cria luzes dinâmicas, sombras ou
## atualizações de SubViewport; só redesenha quando o estado muda.

const DECELERATION_THRESHOLD := 70.0
const MIN_BRAKING_SPEED := 12.0
const BRAKE_HOLD_SECONDS := 0.12

static var _shared_additive_material: CanvasItemMaterial

var is_braking := false
var left_lamp_visible := true
var right_lamp_visible := true
var rear_x := -30.0
var lateral_offset := 10.0
var lamp_radius := 2.2
var motorcycle := false
var _lamp_positions := PackedVector2Array()

var _previous_speed := 0.0
var _has_speed_sample := false
var _hold_remaining := 0.0


func _init() -> void:
	name = "BrakeLights"
	z_index = 4
	visible = false
	set_process(false)
	set_physics_process(false)
	if _shared_additive_material == null:
		_shared_additive_material = CanvasItemMaterial.new()
		_shared_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_shared_additive_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = _shared_additive_material


func configure(vehicle_length: float, vehicle_width: float, is_motorcycle := false) -> void:
	motorcycle = is_motorcycle
	_lamp_positions.clear()
	rear_x = -maxf(12.0, vehicle_length * 0.49)
	lateral_offset = 0.0 if motorcycle else maxf(5.0, vehicle_width * 0.27)
	lamp_radius = clampf(vehicle_width * (0.045 if motorcycle else 0.045), 1.25, 2.4)
	queue_redraw()


func set_lamp_positions(positions: PackedVector2Array) -> void:
	var changed := positions.size() != _lamp_positions.size()
	if not changed:
		for index in positions.size():
			if not positions[index].is_equal_approx(_lamp_positions[index]):
				changed = true
				break
	if not changed:
		return
	_lamp_positions = positions.duplicate()
	if is_braking:
		queue_redraw()


func observe_speed(current_speed: float, delta: float, explicit_brake := false) -> void:
	current_speed = maxf(0.0, current_speed)
	var decelerating := false
	if _has_speed_sample and delta > 0.0001 and _previous_speed > MIN_BRAKING_SPEED:
		decelerating = (_previous_speed - current_speed) / delta >= DECELERATION_THRESHOLD
	_previous_speed = current_speed
	_has_speed_sample = true

	if (explicit_brake and current_speed > 2.0) or decelerating:
		_hold_remaining = BRAKE_HOLD_SECONDS
	else:
		_hold_remaining = maxf(0.0, _hold_remaining - delta)
	set_braking(_hold_remaining > 0.0)


func set_braking(active: bool) -> void:
	if is_braking == active:
		return
	is_braking = active
	visible = active and (left_lamp_visible or right_lamp_visible)
	queue_redraw()


func set_lamp_damage(left_broken: bool, right_broken: bool) -> void:
	var next_left := not left_broken
	var next_right := not right_broken
	if left_lamp_visible == next_left and right_lamp_visible == next_right:
		return
	left_lamp_visible = next_left
	right_lamp_visible = next_right
	visible = is_braking and (left_lamp_visible or right_lamp_visible)
	queue_redraw()


func _draw() -> void:
	if not is_braking:
		return
	if not _lamp_positions.is_empty():
		if motorcycle or _lamp_positions.size() == 1:
			if left_lamp_visible or right_lamp_visible:
				_draw_lamp(_lamp_positions[0])
			return
		if left_lamp_visible:
			_draw_lamp(_lamp_positions[0])
		if right_lamp_visible:
			_draw_lamp(_lamp_positions[1])
		return
	if motorcycle:
		if left_lamp_visible or right_lamp_visible:
			_draw_lamp(Vector2(rear_x, 0.0))
		return
	if left_lamp_visible:
		_draw_lamp(Vector2(rear_x, -lateral_offset))
	if right_lamp_visible:
		_draw_lamp(Vector2(rear_x, lateral_offset))


func _draw_lamp(at: Vector2) -> void:
	# Duas camadas dão leitura de brilho sem uma PointLight2D por lanterna.
	draw_circle(at, lamp_radius * 1.75, Color(1.0, 0.02, 0.01, 0.12))
	draw_circle(at, lamp_radius, Color(1.0, 0.055, 0.025, 0.98))
	draw_circle(at + Vector2(-0.25, -0.25), lamp_radius * 0.42, Color(1.0, 0.72, 0.58, 0.95))
