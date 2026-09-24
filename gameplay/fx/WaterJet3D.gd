extends Node3D
## Jato d'água de verdade: gotas em arco balístico da boca até o alvo, névoa no
## caminho e respingo onde cai. Usado pelo hidrante quebrado, pela mangueira do
## bombeiro e pelo canhão do caminhão. Antes eram esferas soltas (hidrante) e um
## cilindro azul liso (bombeiro).
##
## aim(origem, alvo) a cada quadro; flight_time controla a altura do arco (mais
## tempo = arco mais alto). As partículas ficam em coordenadas de mundo e cada uma
## é lançada com a velocidade que a leva exatamente ao alvo sob gravidade.

const GRAVITY := 9.8
var flight_time := 0.6
var pressure := 1.0 # 0..1: escala quantidade e respingo (hidrante perdendo força)
var drops: GPUParticles3D
var mist: GPUParticles3D
var splash: GPUParticles3D
var _drop_process: ParticleProcessMaterial
var _mist_process: ParticleProcessMaterial
var end_point := Vector3.ZERO

static var _drop_mesh: QuadMesh
static var _mist_mesh: QuadMesh

static func _meshes() -> void:
	if _drop_mesh != null: return
	var soft := preload("res://gameplay/vehicle_effects/VehicleEffectResources.gd").soft_texture()
	var drop_material := StandardMaterial3D.new()
	drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	drop_material.albedo_texture = soft
	drop_material.vertex_color_use_as_albedo = true
	drop_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_drop_mesh = QuadMesh.new()
	_drop_mesh.size = Vector2(0.16, 0.16)
	_drop_mesh.material = drop_material
	_mist_mesh = QuadMesh.new()
	_mist_mesh.size = Vector2(0.7, 0.7)
	_mist_mesh.material = drop_material

func _ready() -> void:
	_meshes()
	top_level = true
	global_transform = Transform3D.IDENTITY
	drops = _emitter(220, 0.6, _drop_mesh)
	_drop_process = drops.process_material
	_drop_process.spread = 2.5
	_drop_process.scale_min = 0.7
	_drop_process.scale_max = 1.6
	_drop_process.color = Color(0.82, 0.92, 1.0, 0.85)
	mist = _emitter(40, 0.9, _mist_mesh)
	_mist_process = mist.process_material
	_mist_process.spread = 9.0
	_mist_process.color = Color(0.9, 0.95, 1.0, 0.18)
	_mist_process.scale_min = 0.6
	_mist_process.scale_max = 1.4
	splash = _emitter(60, 0.55, _drop_mesh)
	var splash_process: ParticleProcessMaterial = splash.process_material
	splash_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	splash_process.emission_sphere_radius = 0.35
	splash_process.direction = Vector3.UP
	splash_process.spread = 60.0
	splash_process.initial_velocity_min = 1.5
	splash_process.initial_velocity_max = 3.5
	splash_process.gravity = Vector3(0, -GRAVITY, 0)
	splash_process.color = Color(0.88, 0.95, 1.0, 0.7)
	set_active(false)

func _emitter(amount: int, life: float, mesh: Mesh) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = amount
	emitter.lifetime = life
	emitter.local_coords = false
	emitter.draw_pass_1 = mesh
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-20, -6, -20), Vector3(40, 20, 40))
	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3(0, -GRAVITY, 0)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.1, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	emitter.process_material = process
	add_child(emitter)
	return emitter

func set_active(on: bool) -> void:
	visible = on
	for emitter in [drops, mist, splash]:
		if is_instance_valid(emitter): emitter.emitting = on

func aim(origin: Vector3, target: Vector3) -> void:
	end_point = target
	var t := maxf(0.2, flight_time)
	var velocity := (target - origin - Vector3(0, -0.5 * GRAVITY * t * t, 0)) / t
	var speed := velocity.length()
	var direction := velocity / maxf(speed, 0.001)
	drops.global_position = origin
	# Trocar lifetime reinicia o emissor: só quando muda de verdade.
	if absf(drops.lifetime - t) > 0.08:
		drops.lifetime = t
		mist.lifetime = t * 1.2
	_drop_process.direction = direction
	_drop_process.initial_velocity_min = speed * 0.97
	_drop_process.initial_velocity_max = speed * 1.03
	mist.global_position = origin
	_mist_process.direction = direction
	_mist_process.initial_velocity_min = speed * 0.8
	_mist_process.initial_velocity_max = speed * 0.95
	splash.global_position = target
	var strength := clampf(pressure, 0.0, 1.0)
	drops.amount_ratio = strength
	mist.amount_ratio = strength
	splash.amount_ratio = strength
