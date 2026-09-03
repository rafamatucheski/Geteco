class_name EntranceRouter
extends Node

## Optional destination registry for entrances that lead to locations already
## present in the same scene. Cross-scene requests remain available through
## [signal external_destination_requested].

signal actor_transferred(actor: Node2D, destination_id: StringName, marker: Node2D)
signal external_destination_requested(
	actor: Node2D,
	destination_id: StringName,
	destination_scene: PackedScene,
	destination_spawn: StringName
)
signal unresolved_destination(actor: Node2D, destination_id: StringName)

@export var auto_bind_scene_entrances: bool = true

var _destinations: Dictionary = {}


func _ready() -> void:
	if auto_bind_scene_entrances:
		call_deferred("bind_scene_entrances")


func bind_scene_entrances() -> void:
	for node in get_tree().get_nodes_in_group(&"building_entrance"):
		if node is BuildingEntrance:
			bind_entrance(node)


func bind_entrance(entrance: BuildingEntrance) -> void:
	if not entrance.destination_requested.is_connected(_on_destination_requested):
		entrance.destination_requested.connect(_on_destination_requested)


func register_destination(destination_id: StringName, marker: Node2D) -> void:
	if destination_id == &"" or marker == null:
		return
	_destinations[destination_id] = marker


func unregister_destination(destination_id: StringName) -> void:
	_destinations.erase(destination_id)


func has_destination(destination_id: StringName) -> bool:
	return _resolve_marker(destination_id) != null


func _resolve_marker(destination_id: StringName) -> Node2D:
	var marker: Node2D = _destinations.get(destination_id)
	if marker != null and is_instance_valid(marker):
		return marker
	_destinations.erase(destination_id)
	return null


func _on_destination_requested(
	_entrance: BuildingEntrance,
	actor: Node2D,
	destination_id: StringName,
	destination_scene: PackedScene,
	destination_spawn: StringName
) -> void:
	var marker := _resolve_marker(destination_id)
	if marker != null:
		actor.global_position = marker.global_position
		actor_transferred.emit(actor, destination_id, marker)
		return
	if destination_scene != null:
		external_destination_requested.emit(
			actor,
			destination_id,
			destination_scene,
			destination_spawn
		)
		return
	unresolved_destination.emit(actor, destination_id)

