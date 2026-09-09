extends Node
## Calibrate the existing animated player sprite against a 1.8 m person in the
## room camera. Scale only the visual and footprint, never movement or controls.
const HUMAN_HEIGHT := 1.8
const RIG_HEIGHT := 1.45
var actor: Node2D
var room_camera: Camera3D
var room_display: Sprite2D
var old_viewport_size := Vector2i.ZERO
var old_scale := Vector2.ONE
var old_position := Vector2.ZERO
var old_collision_scale := Vector2.ONE
var collider: CollisionShape2D

func configure(target: Node2D, camera: Camera3D, display: Sprite2D) -> void:
	actor = target
	room_camera = camera
	room_display = display
	old_viewport_size = actor.viewport_3d.size
	actor.viewport_3d.size = Vector2i(384, 384)
	old_scale = actor.sprite_3d_display.scale
	old_position = actor.sprite_3d_display.position
	collider = actor.get_node_or_null("Collision") as CollisionShape2D
	if collider:
		old_collision_scale = collider.scale
	process_priority = 50
	_update_scale()

func _process(_delta: float) -> void:
	_update_scale()

func _update_scale() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(room_camera):
		return
	var image_point: Vector2 = room_display.to_local(actor.global_position) + room_display.texture.get_size() * 0.5
	var origin := room_camera.project_ray_origin(image_point)
	var direction := room_camera.project_ray_normal(image_point)
	if absf(direction.y) < 0.001:
		return
	var foot := origin + direction * (-origin.y / direction.y)
	var projected_height := room_camera.unproject_position(foot + Vector3.UP * HUMAN_HEIGHT).distance_to(room_camera.unproject_position(foot)) * room_display.scale.y
	var player_camera: Camera3D = actor.viewport_3d.get_camera_3d()
	if not player_camera:
		return
	var player_height := player_camera.unproject_position(Vector3.UP * RIG_HEIGHT).distance_to(player_camera.unproject_position(Vector3.ZERO))
	var factor := clampf(projected_height / maxf(player_height, 1.0), 0.05, 2.0)
	actor.sprite_3d_display.scale = Vector2.ONE * factor
	# Ground contact stays at the physics body, not the middle of its texture.
	actor.sprite_3d_display.position = -(player_camera.unproject_position(Vector3.ZERO) - Vector2(actor.viewport_3d.size) * 0.5) * factor
	if collider:
		var metre := room_camera.unproject_position(foot + Vector3.RIGHT).distance_to(room_camera.unproject_position(foot)) * room_display.scale.x
		var depth := room_camera.unproject_position(foot + Vector3.BACK).distance_to(room_camera.unproject_position(foot)) * room_display.scale.y
		collider.scale = old_collision_scale * Vector2(clampf(metre * 0.23 / 5.0, 1.0, 3.0), clampf(depth * 0.23 / 8.0, 0.7, 3.0))

func restore() -> void:
	if is_instance_valid(actor):
		actor.viewport_3d.size = old_viewport_size
		actor.sprite_3d_display.scale = old_scale
		actor.sprite_3d_display.position = old_position
		if is_instance_valid(collider):
			collider.scale = old_collision_scale
	actor = null
	set_process(false)
