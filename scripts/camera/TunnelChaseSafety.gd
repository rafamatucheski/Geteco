extends RefCounted
## A volume sweep protects the rendered lens, including the blended street pose.
## Mountain distance haze belongs to this camera; the weather resource stays intact.
const LENS_RADIUS := .25
const CLEARANCE := .02
const ENVIRONMENT_SYNC_INTERVAL := .1
const STREAM_CELL_SIZE := 64.0
const MAX_FOG_DEPTH := 55.0

var _lens := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _camera: Camera3D
var _original_environment: Environment
var _source_environment: Environment
var _local_environment: Environment
var _sync_elapsed := ENVIRONMENT_SYNC_INTERVAL
var clear_origin_found := true

func _init() -> void:
	_lens.radius = LENS_RADIUS
	_query.shape = _lens
	_query.collision_mask = 1
	_query.collide_with_areas = false
	_query.margin = CLEARANCE

func solve(camera: Camera3D, target: Node3D, eye: Vector3, candidate: Vector3) -> Vector3:
	if not is_instance_valid(camera) or not camera.is_inside_tree(): return candidate
	var excluded: Array[RID] = []
	if target is CollisionObject3D: excluded.append(target.get_rid())
	return resolve_position(camera.get_world_3d().direct_space_state, eye, candidate, excluded)

func resolve_position(space: PhysicsDirectSpaceState3D, eye: Vector3, candidate: Vector3, excluded: Array[RID] = []) -> Vector3:
	if space == null: return candidate
	_query.exclude = excluded
	var origin := eye
	clear_origin_found = _clear_at(space, origin)
	if not clear_origin_found:
		# cast_motion intentionally ignores shapes overlapping its origin. A
		# shoulder brushing a wall must first retreat into nearby free space.
		var retreat := (eye-candidate).normalized()
		var lateral := retreat.cross(Vector3.UP).normalized()
		if lateral.length_squared() < .01: lateral = Vector3.RIGHT
		for step in [1.0, 2.0, 3.0]:
			for direction in [retreat, Vector3.DOWN, Vector3.UP, lateral, -lateral, -retreat]:
				var probe: Vector3 = eye + direction * (LENS_RADIUS + CLEARANCE) * step
				if _clear_at(space, probe):
					origin = probe
					clear_origin_found = true
					break
			if clear_origin_found: break
		# A deeply embedded target has no valid nearby lens origin. Do not cast
		# through its containing solid and place the lens on the far side of it.
		if not clear_origin_found: return eye
	var motion := candidate-origin
	if motion.length_squared() < .000001: return origin
	_query.transform = Transform3D(Basis.IDENTITY, origin)
	_query.motion = motion
	var fractions := space.cast_motion(_query)
	var fraction := fractions[0] if fractions.size() >= 2 else 0.0
	if fraction < 1.0: fraction = maxf(0.0, fraction-CLEARANCE/motion.length())
	return origin+motion*fraction

func _clear_at(space: PhysicsDirectSpaceState3D, point: Vector3) -> bool:
	_query.transform = Transform3D(Basis.IDENTITY, point)
	_query.motion = Vector3.ZERO
	return space.intersect_shape(_query, 1).is_empty()

## Call only with the mountain contribution, after the final camera transform.
## Passing zero (including locked/interior views) restores its original environment.
func update_environment(camera: Camera3D, mountain_blend: float, delta: float, target_position: Vector3) -> void:
	if not is_instance_valid(camera) or mountain_blend <= .001 or not camera.is_inside_tree():
		restore_environment()
		return
	if is_instance_valid(_camera) and _camera != camera: restore_environment()
	if not is_instance_valid(_camera):
		_camera = camera
		_original_environment = camera.environment
	var source := _original_environment if _original_environment != null else camera.get_world_3d().environment
	if source == null:
		restore_environment()
		return
	if _source_environment != source or _local_environment == null:
		_source_environment = source
		_local_environment = source.duplicate() as Environment
		_sync_elapsed = ENVIRONMENT_SYNC_INTERVAL
	camera.environment = _local_environment
	_sync_elapsed += maxf(0.0, delta)
	if _sync_elapsed >= ENVIRONMENT_SYNC_INTERVAL:
		_sync_elapsed = 0.0
		_sync_weather(source)
	# Lightning's short envelope changes this one field every frame.
	_local_environment.ambient_light_energy = source.ambient_light_energy
	var strength := smoothstep(.05, .65, clampf(mountain_blend, 0.0, 1.0))
	var reach := Vector2(camera.global_position.x-target_position.x, camera.global_position.z-target_position.z).length()
	var depth_end := clampf(STREAM_CELL_SIZE-reach-4.0, 12.0, MAX_FOG_DEPTH)
	_local_environment.fog_enabled = source.fog_enabled or strength > .001
	_local_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_local_environment.fog_density = lerpf(source.fog_density if source.fog_enabled else 0.0, 1.0, strength)
	_local_environment.fog_light_color = source.fog_light_color.lerp(_local_environment.background_color, strength)
	_local_environment.fog_light_energy = lerpf(source.fog_light_energy, 1.0, strength)
	_local_environment.fog_sun_scatter = lerpf(source.fog_sun_scatter, 0.0, strength)
	_local_environment.fog_depth_begin = lerpf(source.fog_depth_begin, depth_end*.55, strength)
	_local_environment.fog_depth_end = lerpf(source.fog_depth_end, depth_end, strength)
	_local_environment.fog_depth_curve = lerpf(source.fog_depth_curve, 1.25, strength)
	_local_environment.fog_sky_affect = lerpf(source.fog_sky_affect, 1.0, strength)

func _sync_weather(source: Environment) -> void:
	# Explicit bounded fields: no property enumeration or per-frame duplication.
	_local_environment.background_mode = source.background_mode
	_local_environment.background_color = source.background_color
	_local_environment.background_energy_multiplier = source.background_energy_multiplier
	_local_environment.ambient_light_source = source.ambient_light_source
	_local_environment.ambient_light_color = source.ambient_light_color
	_local_environment.ambient_light_sky_contribution = source.ambient_light_sky_contribution
	_local_environment.reflected_light_source = source.reflected_light_source
	_local_environment.tonemap_mode = source.tonemap_mode
	_local_environment.tonemap_exposure = source.tonemap_exposure
	_local_environment.tonemap_white = source.tonemap_white
	_local_environment.adjustment_enabled = source.adjustment_enabled
	_local_environment.adjustment_brightness = source.adjustment_brightness
	_local_environment.adjustment_contrast = source.adjustment_contrast
	_local_environment.adjustment_saturation = source.adjustment_saturation

func restore_environment() -> void:
	if is_instance_valid(_camera) and _camera.environment == _local_environment:
		_camera.environment = _original_environment
	_camera = null
	_original_environment = null
	_source_environment = null
	_local_environment = null
	_sync_elapsed = ENVIRONMENT_SYNC_INTERVAL
