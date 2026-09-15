extends Node2D
## World-owned prop: moving, hiding or rebuilding Dante cannot move the discard.
const GROUND_SECONDS := 10.0
const FADE_SECONDS := 1.5
const FLIGHT_SECONDS := .55
var elapsed := 0.0
var sprite: Sprite2D
var shell: Node3D
var viewport: SubViewport
var release_offset := Vector2.ZERO
var travel := Vector2.ZERO

func setup(actor: CharacterBody2D) -> void:
	name = "DroppedMotorcycleHelmet"
	add_to_group("dropped_motorcycle_helmets")
	global_position = actor.global_position
	z_index = actor.z_index
	viewport = SubViewport.new()
	viewport.size = actor.viewport_3d.size
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	for child in actor.viewport_3d.get_children():
		if child is Camera3D or child is Light3D or child is WorldEnvironment:
			viewport.add_child(child.duplicate())
	var original: Node3D = actor.head_node.get_node("MotorcycleHelmet")
	shell = original.duplicate()
	viewport.add_child(shell)
	shell.transform = original.global_transform
	var camera := viewport.get_camera_3d()
	var center := Vector2(viewport.size) * .5
	release_offset = (camera.unproject_position(shell.position) - center) * actor.sprite_3d_display.scale
	# Center the mesh in its own viewport, preserving its screen scale.
	var depth := -camera.to_local(shell.position).z
	shell.position = camera.project_position(center, depth)
	shell.show()
	sprite = Sprite2D.new()
	sprite.texture = viewport.get_texture()
	sprite.scale = actor.sprite_3d_display.scale
	add_child(sprite)
	travel = Vector2.from_angle(-actor.model_root.rotation.y - PI * .5 - .7) * 13.0
	sprite.position = release_offset

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	elapsed += delta
	var t := clampf(elapsed / FLIGHT_SECONDS, 0.0, 1.0)
	sprite.position = release_offset.lerp(travel, t) + Vector2(0, -9.0 * sin(PI * t))
	if elapsed < FLIGHT_SECONDS:
		shell.rotate_x(delta * 7.0)
		shell.rotate_z(delta * 3.0)
	else:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS else SubViewport.UPDATE_DISABLED
	modulate.a = 1.0 - smoothstep(FLIGHT_SECONDS + GROUND_SECONDS, FLIGHT_SECONDS + GROUND_SECONDS + FADE_SECONDS, elapsed)
	if elapsed >= FLIGHT_SECONDS + GROUND_SECONDS + FADE_SECONDS:
		queue_free()
