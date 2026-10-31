extends Node3D
## Impactos locais e limitados de granizo. A névoa no chão está desligada em toda região.
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
var _desert := 0.0
var _shards_alive := false

func _ready() -> void:
	_rng.randomize()
	name = "WeatherSurfaceEffects"
	# Os fragmentos balísticos são animados na cadência do render, não na da física.
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
	mist.emitting = false
	mist.visible = false
	mist.speed_scale = 0.0
	add_child(mist)
	set_process(false)
	set_physics_process(false)

func set_conditions(focus: Vector3, hail_strength: float, _haze: float, _tint: Color, covered: bool, desert := 0.0, _wind_strength := 0.0) -> void:
	# Teleports cannot leave a trail at the previous region or inside a room.
	if (covered and not _covered) or focus.distance_squared_to(_focus)>1600.0:
		_clear_shards()
	_covered = covered
	_desert = desert
	_focus = focus
	_hail_strength = 0.0 if covered else clampf(hail_strength,0,1)
	set_physics_process(_hail_strength>.001)
	follow_focus(focus)
	# A névoa distante pertence ao RegionalAtmosphere3D; chuva/neve têm emissores separados.
	mist.visible = false
	mist.emitting = false
	shards.visible = not covered
	set_process(_shards_alive)

func follow_focus(focus: Vector3) -> void:
	# Chamado na cadência do render: a antiga realocação a 5Hz deixava poeira atrás dos carros.
	mist.position = focus+Vector3.UP*lerpf(1.8,1.1,_desert)

func _clear_shards() -> void:
	set_process(false)
	_shards_alive = false
	for i in SHARD_COUNT:
		_ages[i] = SHARD_LIFETIME
		shards.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))

func _physics_process(delta: float) -> void:
	_tick += delta
	if _hail_strength<=.001 or _tick<.1: return
	_tick = 0.0
	# No máximo quatro raios curtos ao chão a cada 100 ms, só durante granizo local.
	var space := get_world_3d().direct_space_state
	for j in ceili(_hail_strength*4.0):
		var point := _focus+Vector3(_rng.randf_range(-12,12),0,_rng.randf_range(-12,12))
		var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*5,point+Vector3.DOWN*8,1)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.normal.y<.65: continue
		# Recusa telhados acima do chão local; os impactos ficam em sólidos reais.
		if hit.position.y>_focus.y+1.0: continue
		impact_count += 1
		_shards_alive = true
		set_process(true)
		for k in 3:
			_origins[_cursor] = hit.position+hit.normal*.04
			_velocities[_cursor] = Vector3(_rng.randf_range(-1.2,1.2),_rng.randf_range(1.5,3),_rng.randf_range(-1.2,1.2))
			_ages[_cursor] = 0
			_cursor = (_cursor+1)%SHARD_COUNT

func _process(delta: float) -> void:
	if not _shards_alive: return
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
	_shards_alive = alive
	if not alive: set_process(false)
