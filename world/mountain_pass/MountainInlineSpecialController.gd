class_name MountainInlineSpecialController
extends Node

var room: Node2D
var facade: Node2D
var manager: Node
var sprite: Sprite2D
var camera_3d: Camera3D
var floor_polygon := PackedVector2Array()
var occupied := false
var actor_presentation: Node
var saved_camera_position := Vector2.ZERO
var rear_ski_exit := false

func install(host: Node2D, exterior: Node2D, interior_manager: Node, display: Sprite2D, camera: Camera3D, floor: PackedVector2Array, ski_exit := false) -> void:
	room = host
	facade = exterior
	manager = interior_manager
	sprite = display
	camera_3d = camera
	floor_polygon = floor
	rear_ski_exit = ski_exit
	room.global_position = facade.global_position
	room.z_as_relative = false
	room.z_index = 20 if room.get("interior_id") == &"mountain_mystery_cave" else 6
	room.show()
	sprite.hide()
	set_process(true)

func contains_world_point(point: Vector2) -> bool:
	return is_instance_valid(room) and floor_polygon.size() >= 3 and Geometry2D.is_point_in_polygon(room.to_local(point), floor_polygon)

func _process(_delta: float) -> void:
	if not is_instance_valid(room) or not is_instance_valid(manager): return
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	var inside: bool = is_instance_valid(actor) and actor.get("is_dead") != true and contains_world_point(actor.global_position)
	if inside and not occupied: _enter(actor)
	elif not inside and occupied: _leave(actor)

func _enter(actor: Node2D) -> void:
	occupied = true
	sprite.show()
	if is_instance_valid(facade) and facade.has_method("set_inline_occupied"):
		facade.call("set_inline_occupied", true)
	if actor.has_method("stop_skiing"): actor.stop_skiing()
	actor.set_meta("mountain_interior", true)
	actor.set_meta("mountain_interior_id", room.get("interior_id"))
	manager.call("set_active_interior", room)
	manager.emit_signal("actor_entered_interior", actor, room.get("interior_id"))
	actor_presentation = preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	room.add_child(actor_presentation)
	actor_presentation.call("configure", actor, camera_3d, sprite)
	var cam := actor.get_node_or_null("Camera") as Camera2D
	if cam:
		saved_camera_position = cam.position
		cam.set_meta("compact_interior", room.call("get_camera_rect"))
		cam.limit_left = -10000000
		cam.limit_top = -10000000
		cam.limit_right = 10000000
		cam.limit_bottom = 10000000
		cam.reset_smoothing()

func _leave(actor: Node2D) -> void:
	occupied = false
	room.call("set_npc_rendering_active", false)
	sprite.hide()
	if is_instance_valid(facade) and facade.has_method("set_inline_occupied"):
		facade.call("set_inline_occupied", false)
	if is_instance_valid(actor):
		var leaving_rear := rear_ski_exit and room.to_local(actor.global_position).y < floor_polygon[0].y
		actor.remove_meta("mountain_interior")
		actor.remove_meta("mountain_interior_id")
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam:
			cam.remove_meta("compact_interior")
			cam.position = saved_camera_position
			cam.make_current()
			cam.reset_smoothing()
		if leaving_rear and actor.get("ski_equipment_ready") == true and actor.has_method("start_skiing"):
			actor.start_skiing(Vector2.UP)
	if is_instance_valid(actor_presentation):
		actor_presentation.call("restore")
		actor_presentation.queue_free()
		actor_presentation = null
	manager.call("set_active_interior", null)
	manager.emit_signal("actor_returned_to_exterior", actor, room.get("interior_id"))

func _exit_tree() -> void:
	if occupied: _leave(get_tree().get_first_node_in_group("player") as Node2D)
