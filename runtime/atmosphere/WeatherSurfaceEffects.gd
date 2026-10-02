extends Node3D
## Bounded local hail impacts and moving mist; no new lights or screen copies.
const SHARD_COUNT := 120
const SHARD_LIFETIME := 0.28 # Original V1 IceStormManager lifetime.
var mist: GPUParticles3D
var shards: MultiMeshInstance3D
var _ages := PackedFloat32Array()
var _origins := PackedVector3Array()
var _velocities := PackedVector3Array()
var _cursor := 0
var _tick := 0.0
var _hail_strength := 0.0
var _focus := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var impact_count := 0
var _covered := false

func _ready() -> void:
	_rng.randomize()
	name = "WeatherSurfaceEffects"
	# Ballistic fragments are animated at render cadence, not physics cadence.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	shards = MultiMeshInstance3D.new()
	shards.multimesh = MultiMesh.new()
	shards.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := PrismMesh.new()
	mesh.size = Vector3(.045,.11,.035)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.68,.86,.94)
	material.roughness = .28
	mesh.material = material
	shards.multimesh.mesh = mesh
	shards.multimesh.instance_count = SHARD_COUNT
	shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shards)
	_ages.resize(SHARD_COUNT)
	_origins.resize(SHARD_COUNT)
	_velocities.resize(SHARD_COUNT)
	_clear_shards()
	mist = GPUParticles3D.new()
	mist.amount = 16
	mist.lifetime = 8.0
	mist.preprocess = 0.0
	mist.visibility_aabb = AABB(Vector3(-28,-6,-28),Vector3(56,18,56))
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(9,3)
	var fog_material := StandardMaterial3D.new()
	fog_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fog_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fog_material.albedo_texture = _mist_texture()
	quad.material = fog_material
	mist.draw_pass_1 = quad
	var particles := ParticleProcessMaterial.new()
	particles.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(18,1.0,18)
	particles.direction = Vector3(1,0,.25).normalized()
	particles.spread = 12
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = .3
	particles.initial_velocity_max = .7
	var gradient := Gradient.new()
	gradient.set_color(0,Color(1,1,1,0))
	gradient.set_color(1,Color(1,1,1,0))
	gradient.add_point(.25,Color.WHITE)
	gradient.add_point(.7,Color.WHITE)
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	particles.color_ramp = ramp
	mist.process_material = particles
	mist.emitting = false
	add_child(mist)
	set_process(false)
	set_physics_process(false)

func _mist_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 913
	noise.frequency = .09
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var p := (Vector2(x,y)-Vector2(31.5,31.5))/31.5
			var edge := pow(maxf(0,1.0-p.length_squared()),2.0)
			image.set_pixel(x,y,Color(1,1,1,edge*(.55+.45*noise.get_noise_2d(x,y))))
	return ImageTexture.create_from_image(image)

func set_conditions(focus: Vector3, hail_strength: float, haze: float, tint: Color, covered: bool) -> void:
	# Teleports cannot leave a trail at the previous region or inside a room.
	if (covered and not _covered) or focus.distance_squared_to(_focus)>1600.0:
		_clear_shards()
		mist.restart()
	_covered = covered
	_focus = focus
	_hail_strength = 0.0 if covered else clampf(hail_strength,0,1)
	set_physics_process(_hail_strength>.001)
	mist.position = focus + Vector3.UP*1.8
	mist.visible = not covered and haze>.001
	mist.emitting = mist.visible
	mist.amount_ratio = clampf(haze*5.0,.15,1.0)
	mist.draw_pass_1.material.albedo_color = Color(tint.r,tint.g,tint.b,clampf(haze*.6,0,.12))
	shards.visible = not covered

func _clear_shards() -> void:
	set_process(false)
	for i in SHARD_COUNT:
		_ages[i] = SHARD_LIFETIME
		shards.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))

func _physics_process(delta: float) -> void:
	_tick += delta
	if _hail_strength<=.001 or _tick<.1: return
	_tick = 0.0
	# At most four short ground rays per 100 ms, only during local hail.
	var space := get_world_3d().direct_space_state
	for j in ceili(_hail_strength*4.0):
		var point := _focus+Vector3(_rng.randf_range(-12,12),0,_rng.randf_range(-12,12))
		var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*5,point+Vector3.DOWN*8,1)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.normal.y<.65: continue
		# Reject roofs above the local ground; impacts remain on actual solids.
		if hit.position.y>_focus.y+1.0: continue
		impact_count += 1
		set_process(true)
		for k in 3:
			_origins[_cursor] = hit.position+hit.normal*.04
			_velocities[_cursor] = Vector3(_rng.randf_range(-1.2,1.2),_rng.randf_range(1.5,3),_rng.randf_range(-1.2,1.2))
			_ages[_cursor] = 0
			_cursor = (_cursor+1)%SHARD_COUNT

func _process(delta: float) -> void:
	var alive := false
	for i in SHARD_COUNT:
		if _ages[i]>=SHARD_LIFETIME: continue
		alive = true
		_ages[i] = minf(_ages[i]+delta,SHARD_LIFETIME)
		var t := _ages[i]
		var local_scale := 1.0-smoothstep(.14,SHARD_LIFETIME,t)
		var point := _origins[i]+_velocities[i]*t+Vector3.DOWN*5*t*t
		var local_basis := Basis(Vector3(1,0,1).normalized(),t*12+i).scaled(Vector3.ONE*local_scale)
		shards.multimesh.set_instance_transform(i,Transform3D(local_basis,point))
	if not alive: set_process(false)
