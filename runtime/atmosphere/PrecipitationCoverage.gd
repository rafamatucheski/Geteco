extends RefCounted
## Fit the near weather volume to the actual view, including driving zoom/orbit.
## Local simulation keeps living drops with the volume at any vehicle speed.
const MARGIN := 8.0

static func configure(emitter: GPUParticles3D) -> void:
	emitter.local_coords = true
	emitter.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.preprocess = emitter.lifetime

static func footprint(camera: Camera3D, focus: Vector3) -> AABB:
	var bounds := AABB(focus-Vector3(16,0,16),Vector3(32,10,32))
	if not is_instance_valid(camera): return bounds
	var viewport_size := camera.get_viewport().get_visible_rect().size
	# A low perspective camera sees the horizon. Limit this local volume to the
	# foreground; projecting horizon rays to the ground would make it unbounded.
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		var center := camera.global_position-camera.global_basis.z*12.0
		center.y = focus.y
		return AABB(center-Vector3(18,0,18),Vector3(36,10,36))
	for corner in [Vector2.ZERO,Vector2(viewport_size.x,0),viewport_size,Vector2(0,viewport_size.y)]:
		var origin := camera.project_ray_origin(corner)
		var ray := camera.project_ray_normal(corner)
		if ray.y >= -.1: continue
		for height in [focus.y-2.0,focus.y+10.0]:
			var point: Vector3 = origin+ray*((height-origin.y)/ray.y)
			bounds = bounds.expand(point)
	return bounds

static func follow(emitter: GPUParticles3D, camera: Camera3D, focus: Vector3) -> void:
	var bounds := footprint(camera,focus)
	var extent := bounds.size*.5+Vector3(MARGIN,0,MARGIN)
	var center := bounds.get_center()
	emitter.global_position = Vector3(center.x,focus.y+10.0,center.z)
	var material := emitter.process_material as ParticleProcessMaterial
	var box := Vector3(extent.x,1,extent.z)
	if not material.emission_box_extents.is_equal_approx(box):
		material.emission_box_extents = box
		# Includes the full fall and wind drift, rather than the old 36m box.
		emitter.visibility_aabb = AABB(Vector3(-extent.x-8,-36,-extent.z-8),Vector3(extent.x*2+16,40,extent.z*2+16))
