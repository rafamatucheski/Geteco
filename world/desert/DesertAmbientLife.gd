extends Node3D
## One bounded emitter pair and one distant flock per resident desert.
## Caller must suspend when the resident region becomes quiet or releases chunks.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
var _wind: GPUParticles3D
var _wake: GPUParticles3D
var _birds: MultiMeshInstance3D
var _focus := Vector3.ZERO
var _flock_center := Vector3.ZERO
var _active := false
var _elapsed := 0.0
var _tick := 0.0
var _wake_age := 10.0
var _last_focus := Vector3.INF
var _reset_flock := true

func _ready() -> void:
	name="DesertAmbientLife"
	_wind=_dust("LowWindDust",20,4.0,Vector3(8,.02,4),.12)
	_wake=_dust("VehicleSandWake",14,1.6,Vector3(.55,.06,.55),.18)
	_make_birds()
	set_active(_active)

func set_focus(point: Vector3) -> void:
	_focus=point
	if not LAYOUT.contains(point):
		suspend()
		return
	if _last_focus==Vector3.INF or _last_focus.distance_squared_to(point)>10000:
		_last_focus=point
		_flock_center=point+Vector3(48,32,-35)
		_reset_flock=true
		if _wind!=null: _wind.restart()
	set_active(true)

func set_active(enabled: bool) -> void:
	_active=enabled
	visible=enabled
	set_physics_process(enabled)
	if _wind!=null: _wind.emitting=enabled
	if not enabled and _wake!=null: _wake.emitting=false
	if _wind!=null: _wind.speed_scale=1.0 if enabled else 0.0
	if _wake!=null: _wake.speed_scale=1.0 if enabled else 0.0

func suspend() -> void:
	set_active(false)
	_wake_age=10.0
	# GPU simulation sleeps with the region, not merely hidden transparent quads.
	if _wind!=null: _wind.speed_scale=0.0
	if _wake!=null: _wake.speed_scale=0.0

func set_activity_position(point: Vector3, speed_mps: float, on_sand: bool) -> void:
	if _wake==null: return
	_wake_age=0.0
	_wake.global_position=point+Vector3(0,.16,0)
	_wake.emitting=_active and on_sand and speed_mps>2.5
	_wake.amount_ratio=clampf(speed_mps/18.0,.15,1.0)

func _physics_process(delta: float) -> void:
	_elapsed+=delta
	_wake_age+=delta
	# Three gliders move on physics ticks so engine interpolation sees coherent
	# previous/current poses. The more expensive emitter work remains at 10 Hz.
	for i in 3:
		var angle := _elapsed*.095+float(i)*.36
		var radius := 18.0+float(i)*5.0
		var position := _flock_center+Vector3(cos(angle)*radius,sin(angle*1.7+float(i))*.7,sin(angle)*radius)
		var basis := Basis(Vector3.UP,-angle).rotated(Vector3.FORWARD,.14)
		_birds.multimesh.set_instance_transform(i,Transform3D(basis,position))
		if _reset_flock: _birds.multimesh.reset_instance_physics_interpolation(i)
	_reset_flock=false
	_tick+=delta
	if _tick<.1: return
	_tick=0.0
	_wind.speed_scale=1.0
	_wake.speed_scale=1.0
	if _wake_age>.35: _wake.emitting=false
	# Breathing gusts, not a permanent screen-wide haze. No new light or fog volume.
	_wind.emitting=sin(_elapsed*.39)>-.25
	var at := _focus+Vector3(-9,0,5)
	at.y=LAYOUT.surface_height(Vector2(at.x,at.z))+preload("res://world/desert/DesertTerrainMesh.gd").surface_height(Vector2(at.x,at.z))+.18
	_wind.global_position=at

func _dust(label: String, count: int, seconds: float, spread: Vector3, opacity: float) -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.name=label
	node.amount=count
	node.lifetime=seconds
	node.emitting=false
	node.local_coords=false
	node.fixed_fps=20
	node.visibility_aabb=AABB(Vector3(-14,-2,-10),Vector3(32,8,20))
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents=spread
	process.direction=Vector3(1,.03,-.24)
	process.spread=13.0
	process.initial_velocity_min=1.4
	process.initial_velocity_max=2.8
	process.gravity=Vector3(0,.045,0)
	process.damping_min=.12
	process.damping_max=.25
	process.scale_min=.8
	process.scale_max=2.0
	var gradient := Gradient.new()
	gradient.offsets=PackedFloat32Array([0,.18,.55,1])
	gradient.colors=PackedColorArray([Color(.64,.53,.36,0),Color(.64,.53,.36,opacity),Color(.64,.53,.36,opacity*.7),Color(.64,.53,.36,0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient=gradient
	process.color_ramp=ramp
	node.process_material=process
	var quad := QuadMesh.new()
	quad.size=Vector2(1.6,.65)
	var material := ShaderMaterial.new()
	material.shader=preload("res://world/desert/desert_dust.gdshader")
	quad.material=material
	node.draw_pass_1=quad
	add_child(node)
	return node

func _make_birds() -> void:
	var mesh := preload("res://world/desert/DesertGliderMesh.gd").build()
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("4c463d")
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.roughness=1.0
	mesh.surface_set_material(0,material)
	var batch := MultiMesh.new()
	batch.transform_format=MultiMesh.TRANSFORM_3D
	batch.mesh=mesh
	batch.instance_count=3
	for i in 3: batch.set_instance_transform(i,Transform3D(Basis.IDENTITY,_flock_center))
	_birds=MultiMeshInstance3D.new()
	_birds.name="DistantThermalGliders"
	_birds.multimesh=batch
	_birds.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_birds)
