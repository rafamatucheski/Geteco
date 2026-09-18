extends "res://world/mountain_pass/MountainStaticModelView.gd"
## One real 3D scene projects architecture, parked and circulating coaches alike.
const TERMINAL_MODEL := preload("res://world/harbor/terminal/HarborTerminalModel3D.gd")
var _animation_active := false
var _on_screen := false
var gate_viewport: SubViewport
var gate_sprite: Sprite2D
var overhead_viewport: SubViewport
var floodlights: Array[Node2D] = []

func _ready() -> void:
	build_view(TERMINAL_MODEL, 40.0, 18.0, Vector3(5.5, 0, -5), Vector3(0, 24, 20))
	viewport_3d.size = Vector2i(1280, 1066)
	var rendered_metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	sprite_3d.scale = Vector2.ONE * 18.0 / rendered_metre
	sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO) - Vector2(viewport_3d.size) * 0.5) * sprite_3d.scale
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	for child in viewport_3d.get_children():
		if child is DirectionalLight3D:
			child.layers = 255
			child.light_cull_mask = 255
			child.shadow_enabled = true
			child.directional_shadow_max_distance = 70.0
			child.light_energy = 0.75
		if child is WorldEnvironment:
			child.environment.ambient_light_energy = 0.45
	_build_gate_view()
	_build_overhead_view()
	_build_floodlights()
	for footprint in model.solids:
		var body := StaticBody2D.new()
		body.name = footprint.name
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionPolygon2D.new()
		var projected := PackedVector2Array()
		for point in footprint.polygon:
			projected.append(project_point(point))
		shape.polygon = projected
		body.add_child(shape)
		add_child(body)
	var visibility := VisibleOnScreenNotifier2D.new()
	visibility.rect = Rect2(-215, -315, 630, 520)
	visibility.screen_entered.connect(_screen_entered)
	visibility.screen_exited.connect(_screen_exited)
	add_child(visibility)

func _build_gate_view() -> void:
	# Portaria and raised barriers stand above the street paving. The floor
	# stays in the base view, so it cannot erase a passing bus or pedestrian.
	gate_viewport = SubViewport.new()
	gate_viewport.name = "GateForegroundViewport"
	gate_viewport.size = Vector2i(768, 384)
	gate_viewport.transparent_bg = true
	gate_viewport.world_3d = viewport_3d.find_world_3d()
	gate_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(gate_viewport)
	var gate_camera := Camera3D.new()
	gate_viewport.add_child(gate_camera)
	gate_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	gate_camera.size = 14.0
	gate_camera.cull_mask = preload("res://world/harbor/terminal/HarborTerminalAccess.gd").FOREGROUND_LAYER
	gate_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var target := floor_from_local(Vector2(305, 110))
	gate_camera.position = target + Vector3(0, 24, 20)
	gate_camera.look_at(target)
	gate_camera.make_current()
	gate_sprite = Sprite2D.new()
	gate_sprite.name = "GateForeground"
	gate_sprite.texture = gate_viewport.get_texture()
	var metre := gate_camera.unproject_position(Vector3.RIGHT).distance_to(gate_camera.unproject_position(Vector3.ZERO))
	gate_sprite.scale = Vector2.ONE * 18.0 / metre
	gate_sprite.position = -(gate_camera.unproject_position(Vector3.ZERO) - Vector2(gate_viewport.size) * 0.5) * gate_sprite.scale
	gate_sprite.z_as_relative = false
	gate_sprite.z_index = 11
	add_child(gate_sprite)

func _build_overhead_view() -> void:
	# Only elevated signage and masts overlay actors; never copy the paving.
	overhead_viewport = SubViewport.new()
	overhead_viewport.name = "TerminalOverheadViewport"
	overhead_viewport.size = viewport_3d.size
	overhead_viewport.transparent_bg = true
	overhead_viewport.world_3d = viewport_3d.find_world_3d()
	overhead_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(overhead_viewport)
	var overhead_camera := Camera3D.new()
	overhead_viewport.add_child(overhead_camera)
	overhead_camera.projection = camera_3d.projection
	overhead_camera.size = camera_3d.size
	overhead_camera.transform = camera_3d.transform
	overhead_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	overhead_camera.cull_mask = TERMINAL_MODEL.OVERHEAD_LAYER
	overhead_camera.make_current()
	camera_3d.cull_mask &= ~TERMINAL_MODEL.OVERHEAD_LAYER
	var overlay := Sprite2D.new()
	overlay.name = "TerminalOverhead"
	overlay.texture = overhead_viewport.get_texture()
	overlay.position = sprite_3d.position
	overlay.scale = sprite_3d.scale
	overlay.z_as_relative = false
	overlay.z_index = 11
	add_child(overlay)

func _build_floodlights() -> void:
	for x in [-260.0, 430.0]:
		var light := preload("res://world/harbor/HarborPortFloodlight.gd").new()
		light.name = "TerminalFloodlight"
		light.position = Vector2(x, 38)
		light.direction = Vector2(90 if x < 0 else -90, -90)
		add_child(light)
		for i in light.glows.size():
			light.glows[i].position = project_point(floor_from_local(Vector2(x + (-19 if i == 0 else 19), 41)) + Vector3.UP * 6.75) - light.position
			light.glows[i].z_as_relative = false
			light.glows[i].z_index = 12
		for pool in light.pools:
			pool.texture_scale = 1.65
			pool.energy = 0.7
		floodlights.append(light)

func floor_from_local(point: Vector2) -> Vector3:
	return TERMINAL_MODEL.floor_from_local(point)

func request_redraw() -> void:
	if not _animation_active and _on_screen:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_animation_active(active: bool) -> void:
	_animation_active = active
	_refresh_render_mode()

func _screen_entered() -> void:
	_on_screen = true
	_refresh_render_mode()

func _screen_exited() -> void:
	_on_screen = false
	_refresh_render_mode()

func _refresh_render_mode() -> void:
	if not _on_screen:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
		gate_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		overhead_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if _animation_active else SubViewport.UPDATE_ONCE
		gate_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		overhead_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func request_gate_redraw() -> void:
	if _on_screen and is_instance_valid(gate_viewport):
		gate_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
