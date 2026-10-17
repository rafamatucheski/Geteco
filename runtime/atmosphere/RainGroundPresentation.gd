extends Node3D
## World-anchored contact trajectories. Eight probes per 100 ms at peak; the
## GPU animates descent and splash together, without per-drop physics objects.
## Probe rate is spread across physics ticks, with at most two rays per tick.
const CAPACITY := 128
const MAX_PROBES := 8
var rings: MultiMeshInstance3D
var drops: MultiMeshInstance3D
var mist: GPUParticles3D
var _strength := 0.0
var _daylight := 1.0
var _focus := Vector3.ZERO
var _tick := .1
var _probe_budget := 0.0
var _probe_index := 0
var _sample_bounds := AABB(Vector3(-16,0,-16),Vector3(32,10,32))
var _cursor := 0
var _rng := RandomNumberGenerator.new()
var impact_count := 0
var roof_impact_count := 0
var water_impact_count := 0
var _has_contacts := false
var probe_count := 0
var _water_surfaces: Array[Node] = []

func _ready() -> void:
	_rng.randomize()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	rings = MultiMeshInstance3D.new()
	rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rings.multimesh = MultiMesh.new()
	rings.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	rings.multimesh.use_custom_data = true
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(.72,.72)
	var material := ShaderMaterial.new()
	material.shader = preload("res://runtime/atmosphere/rain_impact.gdshader")
	mesh.material = material
	rings.multimesh.mesh = mesh
	rings.multimesh.instance_count = CAPACITY
	add_child(rings)
	drops = MultiMeshInstance3D.new()
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.multimesh = MultiMesh.new()
	drops.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	drops.multimesh.use_custom_data = true
	var drop_mesh := QuadMesh.new()
	drop_mesh.size = Vector2(.055,.64)
	var drop_material := ShaderMaterial.new()
	drop_material.shader = preload("res://runtime/atmosphere/rain_contact_drop.gdshader")
	drop_mesh.material = drop_material
	drops.multimesh.mesh = drop_mesh
	drops.multimesh.instance_count = CAPACITY
	add_child(drops)
	_clear()
	mist = GPUParticles3D.new()
	mist.amount = 24
	mist.lifetime = 1.8
	mist.local_coords = false
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mist.visibility_aabb = AABB(Vector3(-15,-2,-15),Vector3(30,6,30))
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4,.65)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = preload("res://runtime/atmosphere/WeatherParticleTextures.gd").texture("snow")
	quad.material = mat
	mist.draw_pass_1 = quad
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(11,.08,11)
	process.direction = Vector3(1,.08,.3).normalized()
	process.spread = 12
	process.initial_velocity_min = .3
	process.initial_velocity_max = .7
	process.gravity = Vector3.ZERO
	process.scale_min = .65
	process.scale_max = 1.35
	mist.process_material = process
	mist.emitting = false
	mist.visible = false
	add_child(mist)
	set_physics_process(false)
	set_process(false)

func _process(_delta: float) -> void:
	var now := fmod(Time.get_ticks_msec()/1000.0,3600.0)
	rings.multimesh.mesh.material.set_shader_parameter("now_seconds",now)
	drops.multimesh.mesh.material.set_shader_parameter("now_seconds",now)

func _clear() -> void:
	_has_contacts = false
	for i in CAPACITY:
		rings.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
		drops.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
		drops.multimesh.set_instance_custom_data(i,Color(0,0,0,0))

func set_conditions(focus: Vector3, strength: float, daylight: float, covered: bool) -> void:
	if focus.distance_squared_to(_focus)>400.0:
		_clear()
		_tick = .1
		_probe_budget = 0.0
		mist.visible = false
		mist.emitting = false
	_focus = focus
	_strength = 0.0 if covered else strength
	_daylight = daylight
	rings.visible = _strength>.01
	drops.visible = rings.visible
	if not rings.visible and _has_contacts: _clear()
	# Mist needs a validated ground height, set by the bounded physics probe.
	if _strength<.55:
		mist.visible = false
		mist.emitting = false
	set_physics_process(_strength>.01)
	set_process(_strength>.01)
	if _strength<=.01: _probe_budget = 0.0
	mist.draw_pass_1.material.albedo_color = Color(.48,.58,.63,lerpf(.018,.055,daylight)*smoothstep(.55,1.0,_strength))

func _physics_process(delta: float) -> void:
	_tick += delta
	if _tick>=.1:
		_tick = 0.0
		_update_bounds()
	# A hitch must not queue a burst of catch-up raycasts on the next frame.
	_probe_budget = minf(2.0,_probe_budget+maxf(delta,0.0)*_strength*MAX_PROBES*10.0)
	var count := floori(_probe_budget)
	if count==0: return
	_probe_budget -= count
	var space := get_world_3d().direct_space_state
	for j in count:
		var i := _probe_index
		_probe_index = (_probe_index+1)%MAX_PROBES
		var point := _focus if i==0 else Vector3(_rng.randf_range(_sample_bounds.position.x,_sample_bounds.end.x),_focus.y,_rng.randf_range(_sample_bounds.position.z,_sample_bounds.end.z))
		probe_count += 1
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*40,point+Vector3.DOWN*10,1))
		var water := _water_contact(point, hit)
		if not water.is_empty(): hit = {"position":water.position, "normal":Vector3.UP}
		var valid: bool = not hit.is_empty() and hit.normal.y>.65
		if i==0:
			mist.visible = valid and absf(hit.position.y-_focus.y)<1.2 and _strength>.55
			mist.emitting = mist.visible
			if mist.visible: mist.global_position = hit.position+Vector3.UP*.22
			# This probe positions the mist only. Repeated impacts exactly under
			# the focus would create another visible effect glued to the player.
			continue
		if not valid: continue
		impact_count += 1
		_has_contacts = true
		if water.is_empty() and hit.position.y>_focus.y+1.2: roof_impact_count += 1
		var transform := Transform3D(Basis(Quaternion(Vector3.UP,hit.normal)),hit.position+hit.normal*.04)
		# Up to .65s of actual descent. The ring starts only when this reaches zero.
		var custom := Color(fmod(Time.get_ticks_msec()/1000.0,3600.0),_daylight,_rng.randf_range(.4,.65),0 if water.is_empty() else 1)
		rings.multimesh.set_instance_transform(_cursor,transform)
		rings.multimesh.set_instance_custom_data(_cursor,custom)
		drops.multimesh.set_instance_transform(_cursor,transform)
		drops.multimesh.set_instance_custom_data(_cursor,custom)
		if not water.is_empty() and is_instance_valid(water.surface):
			water_impact_count += 1
			# The surface owns the delayed response; the existing GPU drop and ring
			# share this exact descent duration, with no extra timers or raycasts here.
			water.surface.receive_rain_impact(water.position, _strength, custom.b)
		_cursor = (_cursor+1)%CAPACITY

func _update_bounds() -> void:
	_sample_bounds = preload("res://runtime/atmosphere/PrecipitationCoverage.gd").footprint(get_viewport().get_camera_3d(),_focus)
	var visible_bounds := AABB(Vector3(_sample_bounds.position.x,_focus.y-10,_sample_bounds.position.z),Vector3(_sample_bounds.size.x,60,_sample_bounds.size.z))
	rings.custom_aabb = visible_bounds
	drops.custom_aabb = visible_bounds
	# Streaming can replace a lake while rain is active. Refresh once per 100 ms;
	# probes only visit this small cached list and validate references before use.
	_water_surfaces.clear()
	for surface in get_tree().get_nodes_in_group("native_water_surface"):
		if is_instance_valid(surface) and surface.has_method("contains_water") and surface.has_method("rain_surface_height_at") and surface.has_method("receive_rain_impact"):
			_water_surfaces.append(surface)

func _water_contact(point: Vector3, solid_hit: Dictionary) -> Dictionary:
	var result := {}
	var highest := -INF
	if not solid_hit.is_empty(): highest = float(solid_hit.position.y)
	for surface in _water_surfaces:
		if not is_instance_valid(surface) or surface.is_queued_for_deletion() or not surface.is_inside_tree(): continue
		if not surface.contains_water(point): continue
		var value: Variant = surface.rain_surface_height_at(point)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT]: continue
		var height := float(value)
		# A roof, bridge or bank above the lake still receives the impact. Water
		# must lie inside this existing ray and strictly above its first solid hit.
		if not is_finite(height) or height < point.y - 10.0 or height > point.y + 40.0 or height <= highest: continue
		highest = height
		result = {"surface":surface, "position":Vector3(point.x, height, point.z)}
	return result
