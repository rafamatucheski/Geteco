extends Node3D
## Local quarry wind: two lit batches, no extra environment, light or audio bed.
## The resident region supplies its real ground sampler and suspends this node
## during interiors/unloading. Dormant GPU simulations have speed_scale == 0.
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
const DUST_SHADER := preload("res://world/desert/desert_dust.gdshader")
const WIND_DIRECTION := Vector3(1,.03,-.24)
const PARTICLE_CAPACITY := 64
const UPDATE_INTERVAL := .1
const EDGE_FADE_START := 8.0
const EDGE_FADE_END := 38.0
const MAX_LIFETIME := 4.6
const TELEPORT_DISTANCE := 72.0
var _ground_height: Callable
var _low: GPUParticles3D
var _fine: GPUParticles3D
var _focus := Vector3.INF
var _last_focus := Vector3.INF
var _active := false
var _target_strength := 0.0
var _strength := 0.0
var _clock := 0.0
var _tick := 0.0
var _outside_age := 0.0
var _source_ground := Vector2.ZERO

func configure(height_at: Callable) -> void:
	_ground_height=height_at
	if is_node_ready() and _focus.is_finite(): set_focus(_focus)

func _ready() -> void:
	name="MiningDust"
	process_mode=Node.PROCESS_MODE_PAUSABLE
	var material := ShaderMaterial.new()
	material.shader=DUST_SHADER
	_low=_emitter("LowSandGusts",36,MAX_LIFETIME,Vector3(4.2,.12,3.2),Vector2(2.3,.7),.105,material)
	_fine=_emitter("AirborneSand",28,3.5,Vector3(4.5,.65,3.8),Vector2(.85,.32),.072,material)
	suspend()
	if _focus.is_finite(): set_focus(_focus)

func set_focus(point: Vector3) -> void:
	_focus=point
	if not is_node_ready(): return
	var benchmark_off := OS.is_debug_build() and bool(Engine.get_meta("mining_dust_benchmark_disabled",false))
	if benchmark_off or not LAYOUT.enabled() or not point.is_finite() or not _ground_height.is_valid():
		suspend()
		return
	var nearest := Vector2(clampf(point.x,LAYOUT.BOUNDS.position.x,LAYOUT.BOUNDS.end.x),clampf(point.z,LAYOUT.BOUNDS.position.y,LAYOUT.BOUNDS.end.y))
	var distance := Vector2(point.x,point.z).distance_to(nearest)
	_target_strength=1.0-smoothstep(EDGE_FADE_START,EDGE_FADE_END,distance)
	if _target_strength<=0.0 and not _active: return
	var reset_particles := not _active or (_last_focus.is_finite() and _last_focus.distance_to(point)>TELEPORT_DISTANCE)
	_last_focus=point
	if not _active:
		_active=true
		visible=true
		set_physics_process(true)
		_low.speed_scale=1.0
		_fine.speed_scale=1.0
	if reset_particles:
		# Move origins before restarting. World-space particles left behind by an
		# ordinary walk keep their trajectories instead of following the camera.
		_strength=0.0
		_tick=0.0
		_outside_age=0.0
		_move_sources()
		_low.amount_ratio=0.0
		_fine.amount_ratio=0.0
		_low.restart()
		_fine.restart()
		_low.emitting=false
		_fine.emitting=false

func suspend() -> void:
	_active=false
	_target_strength=0.0
	_strength=0.0
	_outside_age=0.0
	_tick=0.0
	visible=false
	set_physics_process(false)
	for emitter in [_low,_fine]:
		if emitter==null: continue
		emitter.emitting=false
		emitter.speed_scale=0.0
		emitter.amount_ratio=0.0

func _physics_process(delta: float) -> void:
	_clock+=delta
	_tick+=delta
	if _target_strength<=0.0:
		_outside_age+=delta
		# Allow already emitted particles to fade before sleeping outside the
		# quarry. Explicit region/interior suspension remains immediate.
		if _outside_age>MAX_LIFETIME+.6:
			suspend()
			return
	else:
		_outside_age=0.0
	if _tick<UPDATE_INTERVAL: return
	var step := _tick
	_tick=0.0
	_strength=move_toward(_strength,_target_strength,step*.85)
	if _target_strength>0.0: _move_sources()
	var gust := .68+.20*sin(_clock*.38)+.08*sin(_clock*.91)
	_low.amount_ratio=clampf(_strength*gust,0.0,1.0)
	_fine.amount_ratio=clampf(_strength*(gust+.08),0.0,1.0)
	# No hard gust toggle: density changes smoothly and each particle has a
	# transparent birth/death ramp. Last particles expire during edge drain.
	_low.emitting=_target_strength>0.0
	_fine.emitting=_target_strength>0.0

func _move_sources() -> void:
	if not _ground_height.is_valid():
		suspend()
		return
	var low_at := _focus+Vector3(-8,0,3.5)
	var fine_at := _focus+Vector3(-6,0,-3)
	_source_ground=Vector2(float(_ground_height.call(Vector2(low_at.x,low_at.z))),float(_ground_height.call(Vector2(fine_at.x,fine_at.z))))
	low_at.y=_source_ground.x+.28
	fine_at.y=_source_ground.y+1.45
	_low.global_position=low_at
	_fine.global_position=fine_at

func _emitter(label: String, count: int, seconds: float, spread: Vector3, size: Vector2, opacity: float, material: ShaderMaterial) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name=label
	emitter.amount=count
	emitter.lifetime=seconds
	emitter.emitting=false
	emitter.local_coords=false
	emitter.fixed_fps=20
	emitter.visibility_aabb=AABB(Vector3(-16,-5,-20),Vector3(62,16,38))
	emitter.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var particle := ParticleProcessMaterial.new()
	particle.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	particle.emission_box_extents=spread
	particle.direction=WIND_DIRECTION
	particle.spread=10.0
	particle.initial_velocity_min=3.6
	particle.initial_velocity_max=6.4
	particle.gravity=Vector3(0,.045,0)
	particle.damping_min=.10
	particle.damping_max=.22
	particle.scale_min=.75
	particle.scale_max=1.8
	var gradient := Gradient.new()
	gradient.offsets=PackedFloat32Array([0,.22,.60,1])
	gradient.colors=PackedColorArray([Color(.66,.56,.40,0),Color(.66,.56,.40,opacity),Color(.66,.56,.40,opacity*.65),Color(.66,.56,.40,0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient=gradient
	particle.color_ramp=ramp
	emitter.process_material=particle
	var quad := QuadMesh.new()
	quad.size=size
	quad.material=material
	emitter.draw_pass_1=quad
	add_child(emitter)
	return emitter

func debug_snapshot() -> Dictionary:
	var sources: Array[Dictionary]=[]
	for emitter in [_low,_fine]:
		if emitter==null: continue
		sources.append({"name":str(emitter.name),"position":emitter.global_position,"capacity":emitter.amount,"emitting":emitter.emitting,"speed_scale":emitter.speed_scale,"amount_ratio":emitter.amount_ratio})
	return {"active":_active,"visible":visible,"processing":is_physics_processing(),"configured":_ground_height.is_valid(),"target_strength":_target_strength,"strength":_strength,"outside_age":_outside_age,"ground_y":_source_ground,"wind_direction":WIND_DIRECTION,"particle_capacity":PARTICLE_CAPACITY,"draw_batches":sources.size(),"peak_particle_alpha":.105,"fog_volumes":0,"lights":0,"sources":sources}
