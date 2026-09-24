extends "res://systems/interiors/InteriorActorPresentation.gd"
## Outdoor calibration stays continuous while the original rig shares station depth.
var station: Node2D
var street_rig_scale := 1.0
var street_basis := Basis.IDENTITY
var street_screen_correction := Vector2.ONE
var street_foot_offset := Vector2.ZERO
var personal_lighting := preload("res://scripts/player/ActorSharedLighting.gd").new()

func allows_population_sleep() -> bool:
	# This adapter is outdoors and follows the city's proximity budget. Interior
	# adapters intentionally remain pinned while the player occupies a room.
	return true

func set_population_active(active: bool) -> void:
	set_process(active)
	if is_instance_valid(anchor): anchor.visible = active and is_instance_valid(actor) and actor.is_visible_in_tree()
	if is_instance_valid(hit_area): hit_area.collision_layer = 4 if active and actor.get("is_dead") != true else 0
	if active: _update_scale()

func configure(target: Node2D, camera: Camera3D, sprite: Sprite2D) -> void:
	var personal: SubViewport = target.get("viewport_3d") if target.get("viewport_3d") != null else target.get("viewport")
	var personal_display: Sprite2D = target.get("sprite_3d_display")
	var personal_camera := personal.get_camera_3d()
	# Match the original viewing angle as well as the complete standing body.
	# A one-unit ruler underestimates perspective height, and using the station's
	# steeper/different camera directly squeezes the torso and changes the face.
	street_basis = camera.global_basis * personal_camera.global_basis.inverse()
	var native_rig: Node3D = target.get("model_root")
	var reference_height := float(native_rig.get_meta("standing_rig_height", RIG_HEIGHT)) * native_rig.scale.y
	var reference := Vector3.UP * reference_height
	var height := personal_camera.unproject_position(reference).distance_to(personal_camera.unproject_position(Vector3.ZERO)) * personal_display.scale.y
	var stage_height := camera.unproject_position(street_basis * reference).distance_to(camera.unproject_position(Vector3.ZERO)) * sprite.scale.y
	street_rig_scale = height / stage_height
	# The personal perspective and station orthographic camera have different
	# screen aspect magnification. Calibrate in camera space, outside the actor's
	# rotating rig, so turning cannot swap the width and height corrections.
	var points := PackedVector3Array()
	for mesh in native_rig.find_children("*", "MeshInstance3D", true, false):
		if not mesh.visible: continue
		for corner in 8: points.append(mesh.to_global(mesh.get_aabb().get_endpoint(corner)))
	var minimum := Vector2(INF, INF)
	var maximum := Vector2.ZERO
	# Balance front/profile/back without changing the live pose or recalibrating
	# every frame. Otherwise turning after admission can reintroduce squeezing.
	for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
		var native_bounds := Rect2()
		var stage_bounds := Rect2()
		var first := true
		for point in points:
			var world_point: Vector3 = point.rotated(Vector3.UP, yaw)
			var native_point := personal_camera.unproject_position(world_point) * personal_display.scale
			var stage_point := camera.unproject_position(street_basis * world_point * street_rig_scale) * sprite.scale
			if first:
				native_bounds = Rect2(native_point, Vector2.ZERO)
				stage_bounds = Rect2(stage_point, Vector2.ZERO)
				first = false
			else:
				native_bounds = native_bounds.expand(native_point)
				stage_bounds = stage_bounds.expand(stage_point)
		if not first and stage_bounds.size.x > 0.001 and stage_bounds.size.y > 0.001:
			var ratio := native_bounds.size / stage_bounds.size
			minimum = minimum.min(ratio)
			maximum = maximum.max(ratio)
	if minimum.is_finite():
		street_screen_correction = Vector2(sqrt(minimum.x * maximum.x), sqrt(minimum.y * maximum.y))
	street_foot_offset = personal_display.position
	super.configure(target, camera, sprite)
	personal_lighting.configure(target, room_viewport, street_basis)
	# No portrait resize is needed for a street fixture: only its existing rig moves.
	actor_viewport.size = old_viewport_size
	_update_scale()

func restore() -> void:
	personal_lighting.restore()
	super.restore()

func floor_position(canvas_position: Vector2) -> Vector3:
	var local := station.to_local(canvas_position)
	return station.view.model.floor_point(local, station.floor_height(local))

func pixels_per_rig_unit(direction: Vector2) -> float:
	var axis := Vector3(direction.x, 0, direction.y).normalized() * 0.01
	return project_world(anchor.to_global(axis)).distance_to(project_world(anchor.to_global(-axis))) / 0.02

func _update_scale() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(room_camera): return
	var screen_scale := Basis.from_scale(Vector3(street_screen_correction.x, street_screen_correction.y, 1.0))
	anchor.basis = room_camera.global_basis * screen_scale * room_camera.global_basis.inverse() * street_basis.scaled(Vector3.ONE * street_rig_scale)
	anchor.global_position = floor_position(actor.global_position + street_foot_offset)
	anchor.visible = actor.is_visible_in_tree()
	# Use the displayed body, not the interior's fixed 1.8 m capsule. Keep the
	# original street collider, sprite calibration and viewport resolution intact.
	var foot := actor.to_local(project_world(anchor.global_position))
	var head := actor.to_local(project_world(anchor.to_global(Vector3.UP * standing_rig_height * rig.scale.y)))
	var axis := head - foot
	hit_area.position = (head + foot) * 0.5
	hit_area.rotation = axis.angle() + PI * 0.5
	hit_shape.shape.radius = maxf(2.0, axis.length() * 0.15)
	hit_shape.shape.height = maxf(hit_shape.shape.radius * 2.0, axis.length())
	hit_area.collision_layer = 0 if actor.get("is_dead") == true else 4
	actor_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
