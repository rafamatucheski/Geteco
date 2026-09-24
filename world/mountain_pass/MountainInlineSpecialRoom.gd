extends "res://world/harbor/interiors/HarborInteriorBase.gd"

var inline_mode := false
var inline_facade: Node2D
var inline_controller: Node
var inline_scale := Vector2.ONE
var inline_pixels_per_metre := 18.0
var inline_bounds := Rect2(-5.0, -4.0, 10.0, 8.0)

func _build_blackout() -> void:
	if not inline_mode: super._build_blackout()

func attach_inline_facade(facade: Node2D, _entrance: BuildingEntrance, manager: Node) -> void:
	if not inline_mode: return
	inline_facade = facade
	inline_controller = preload("res://world/mountain_pass/MountainInlineSpecialController.gd").new()
	inline_controller.name = "InlineOccupancy"
	add_child(inline_controller)
	var floor := PackedVector2Array()
	for point in _inline_floor_vertices(): floor.append(call("project_floor", point))
	inline_controller.install(self, facade, manager, get("sprite_3d") as Sprite2D, get("camera_3d") as Camera3D, floor, interior_id == &"ski_lodge")

func _inline_floor_vertices() -> Array[Vector2]:
	return [inline_bounds.position, Vector2(inline_bounds.end.x, inline_bounds.position.y), inline_bounds.end, Vector2(inline_bounds.position.x, inline_bounds.end.y)]

func contains_point(point: Vector2) -> bool:
	if inline_mode:
		return is_instance_valid(inline_controller) and inline_controller.contains_world_point(point)
	return super.contains_point(point)

func contains_actor(actor: Node2D) -> bool:
	if inline_mode: return is_instance_valid(actor) and contains_point(actor.global_position)
	return super.contains_actor(actor)

func apply_inline_projection(display: Sprite2D, model_camera: Camera3D, render_target: SubViewport) -> void:
	if not inline_mode: return
	var metre := model_camera.unproject_position(Vector3.RIGHT).distance_to(model_camera.unproject_position(Vector3.ZERO))
	display.scale = Vector2.ONE * inline_pixels_per_metre / maxf(metre, .001)
	display.position = -(model_camera.unproject_position(Vector3.ZERO) - Vector2(render_target.size) * .5) * display.scale
	display.hide()
	room_size = inline_bounds.size * inline_scale * inline_pixels_per_metre
