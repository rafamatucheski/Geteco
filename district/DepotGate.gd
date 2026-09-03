class_name DepotGate
extends Node2D

## Procedural double gate. The depot emits signals, so this can later be
## replaced by a richer firehouse/police door without touching dispatch code.

@export var opening_distance := 28.0
@export var animation_seconds := 0.35
var _left_closed := Vector2.ZERO
var _right_closed := Vector2.ZERO

func _ready() -> void:
	var depot := get_parent() as EmergencyDepotMarker
	if depot:
		depot.gate_open_requested.connect(_on_gate_open_requested)
		depot.gate_close_requested.connect(_on_gate_close_requested)
	_left_closed = $LeftDoor.position
	_right_closed = $RightDoor.position

func _on_gate_open_requested(_depot_id: String) -> void:
	_move_doors(_left_closed + Vector2(-opening_distance, 0), _right_closed + Vector2(opening_distance, 0))

func _on_gate_close_requested(_depot_id: String) -> void:
	_move_doors(_left_closed, _right_closed)

func _move_doors(left_target: Vector2, right_target: Vector2) -> void:
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property($LeftDoor, "position", left_target, animation_seconds)
	tween.tween_property($RightDoor, "position", right_target, animation_seconds)
