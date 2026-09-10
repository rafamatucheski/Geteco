@tool
class_name BuildingEntrance
extends Node2D

## Reusable facade entrance for buildings, shops and garages.
## It never calls Player methods. Consumers may connect [signal destination_requested]
## or use EntranceRouter for same-scene transfers.

signal actor_approached(entrance: BuildingEntrance, actor: Node2D)
signal actor_departed(entrance: BuildingEntrance, actor: Node2D)
signal destination_requested(
	entrance: BuildingEntrance,
	actor: Node2D,
	destination_id: StringName,
	destination_scene: PackedScene,
	destination_spawn: StringName
)
signal door_state_changed(entrance: BuildingEntrance, is_open: bool)
signal transition_started(entrance: BuildingEntrance, actor: Node2D)

enum EntranceKind {
	BUILDING,
	SHOP,
	GARAGE,
}

@export_group("Identity")
@export var entrance_kind: EntranceKind = EntranceKind.BUILDING:
	set(value):
		entrance_kind = value
		_refresh_prompt()
@export var display_name: String = "PRÉDIO":
	set(value):
		display_name = value
		_refresh_prompt()
@export var custom_prompt_text: String = "":
	set(value):
		custom_prompt_text = value
		_refresh_prompt()

@export_group("Destination API")
@export var destination_id: StringName = &""
@export var destination_scene: PackedScene
@export var destination_spawn: StringName = &"EntranceSpawn"

@export_group("Interaction")
@export var actor_group: StringName = &"player"
@export var input_action: StringName = &"interact"
@export var handle_input_locally: bool = true
@export var enabled: bool = true:
	set(value):
		enabled = value
		_refresh_prompt()

@export_group("Door Animation")
@export_range(0.05, 2.0, 0.05) var open_duration: float = 0.22
@export_range(0.05, 2.0, 0.05) var close_duration: float = 0.18
@export_range(2.0, 48.0, 1.0) var panel_slide_distance: float = 13.0
@export_range(0.0, 4.0, 0.1) var auto_close_delay: float = 0.8

@onready var _sensor: Area2D = $InteractionArea
@onready var _door_left: Polygon2D = $Facade/DoorLeft
@onready var _door_right: Polygon2D = $Facade/DoorRight
@onready var _interior_glow: Polygon2D = $Facade/InteriorGlow
@onready var _prompt: Label = $Prompt

var _nearby_actors: Array[Node2D] = []
var _door_tween: Tween
var _door_open: bool = false
var _busy: bool = false
var _left_closed_position: Vector2
var _right_closed_position: Vector2


func _ready() -> void:
	add_to_group(&"building_entrance")
	_left_closed_position = _door_left.position
	_right_closed_position = _door_right.position
	if not Engine.is_editor_hint():
		_sensor.body_entered.connect(_on_body_entered)
		_sensor.body_exited.connect(_on_body_exited)
	_refresh_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not handle_input_locally or not enabled or _busy:
		return
	if not InputMap.has_action(input_action):
		return
	if event.is_action_pressed(input_action) and not event.is_echo():
		var actor := get_nearest_actor()
		if actor != null:
			get_viewport().set_input_as_handled()
			request_interaction(actor)


## Public interaction API. It can be called by any interaction manager.
## Returns false when the actor is out of range, the entrance is disabled or busy.
func request_interaction(actor: Node2D) -> bool:
	if not enabled or _busy or actor == null or not is_actor_in_range(actor):
		return false
	_begin_transition(actor)
	return true


func is_actor_in_range(actor: Node2D) -> bool:
	return is_instance_valid(actor) and actor in _nearby_actors


func get_nearest_actor() -> Node2D:
	var nearest: Node2D
	var nearest_distance := INF
	for actor in _nearby_actors:
		if not is_instance_valid(actor):
			continue
		var distance := global_position.distance_squared_to(actor.global_position)
		if distance < nearest_distance:
			nearest = actor
			nearest_distance = distance
	return nearest


func open_door() -> void:
	_set_door_open(true)


func close_door() -> void:
	_set_door_open(false)


func _begin_transition(actor: Node2D) -> void:
	_busy = true
	_refresh_prompt()
	transition_started.emit(self, actor)
	_set_door_open(true)
	await get_tree().create_timer(open_duration).timeout
	if is_instance_valid(actor):
		destination_requested.emit(
			self,
			actor,
			destination_id,
			destination_scene,
			destination_spawn
		)
	if auto_close_delay > 0.0:
		await get_tree().create_timer(auto_close_delay).timeout
	_set_door_open(false)
	await get_tree().create_timer(close_duration).timeout
	_busy = false
	_refresh_prompt()


func _set_door_open(value: bool) -> void:
	if _door_open == value and _door_tween != null and _door_tween.is_running():
		return
	_door_open = value
	if _door_tween != null:
		_door_tween.kill()
	_door_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var duration := open_duration if value else close_duration
	var left_target := _left_closed_position + Vector2(-panel_slide_distance if value else 0.0, 0.0)
	var right_target := _right_closed_position + Vector2(panel_slide_distance if value else 0.0, 0.0)
	_door_tween.tween_property(_door_left, "position", left_target, duration)
	_door_tween.parallel().tween_property(_door_right, "position", right_target, duration)
	_interior_glow.visible = value
	door_state_changed.emit(self, value)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(actor_group) or body in _nearby_actors:
		return
	_nearby_actors.append(body)
	actor_approached.emit(self, body)
	_refresh_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body not in _nearby_actors:
		return
	_nearby_actors.erase(body)
	actor_departed.emit(self, body)
	_refresh_prompt()


func _refresh_prompt() -> void:
	if not is_node_ready() or _prompt == null:
		return
	_prompt.visible = enabled and not _busy and not _nearby_actors.is_empty()
	if not custom_prompt_text.is_empty():
		_prompt.text = custom_prompt_text
	else:
		var verb := "ENTRAR"
		if entrance_kind == EntranceKind.GARAGE:
			verb = "USAR GARAGEM"
		_prompt.text = "[E] %s · %s" % [verb, display_name.to_upper()]

