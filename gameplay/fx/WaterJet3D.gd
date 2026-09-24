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
## Tamanho das gotas: jatos longos (canhão) precisam de gotas maiores para o arco
## inteiro aparecer vista de cima.
var drop_scale := 1.0
var pressure := 1.0 # 0..1: escala quantidade e respingo (hidrante perdendo força)
## CPUParticles3D: a versão em GPU parava as gotas na metade do arco (medido em
## 2026-09-24, causa não isolada); em CPU a trajetória é a calculada em aim().
var drops: CPUParticles3D
var mist: CPUParticles3D
var splash: CPUParticles3D
var _drop_process: CPUParticles3D
var _mist_process: CPUParticles3D
var end_point := Vector3.ZERO

static var _drop_mesh: QuadMesh
static var _mist_mesh: QuadMesh

static func _meshes() -> void:
	if _drop_mesh != null: return
	# Gota cheia com borda macia. A textura macia comum (alfa (1-r)²) deixava só um
	# ponto de 3 px por gota e o fim do arco sumia vista de cima.
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var r := Vector2(x - 15.5, y - 15.5).length() / 15.5
			image.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - pow(r, 3.0), 0.0, 1.0)))
	var soft := ImageTexture.create_from_image(image)
	var drop_material := StandardMaterial3D.new()
	drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	drop_material.albedo_texture = soft
	# Cor fixa no material: com cor de vértice as gotas recém-nascidas saíam pretas
	# (disco escuro na boca do jato, captura de 2026-09-24).
	drop_material.albedo_color = Color(0.84, 0.92, 1.0, 0.8)
	drop_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_drop_mesh = QuadMesh.new()
	_drop_mesh.size = Vector2(0.24, 0.24)
	_drop_mesh.material = drop_material
	_mist_mesh = QuadMesh.new()
	_mist_mesh.size = Vector2(0.7, 0.7)
	_mist_mesh.material = drop_material

func _ready() -> void:
	_meshes()
	top_level = true
	global_transform = Transform3D.IDENTITY
	# O CPUParticles ignora scale_amount com billboard de partícula: o tamanho vem
	# do quad (cópia por jato quando drop_scale muda).
	var drop_mesh := _drop_mesh
	if not is_equal_approx(drop_scale, 1.0):
		drop_mesh = _drop_mesh.duplicate()
		drop_mesh.size = _drop_mesh.size * drop_scale
	drops = _emitter(360, flight_time, drop_mesh)
	_drop_process = drops
	_drop_process.spread = 2.5
	_drop_process.scale_amount_min = 0.7 * drop_scale
	_drop_process.scale_amount_max = 1.6 * drop_scale
	_drop_process.color = Color(0.82, 0.92, 1.0, 0.85)
	mist = _emitter(40, flight_time * 1.2, _mist_mesh)
	_mist_process = mist
	_mist_process.spread = 9.0
	_mist_process.color = Color(0.9, 0.95, 1.0, 0.18)
	_mist_process.scale_amount_min = 0.6
	_mist_process.scale_amount_max = 1.4
	splash = _emitter(60, 0.55, _drop_mesh)
	var splash_process := splash
	splash_process.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	splash_process.emission_sphere_radius = 0.35
	splash_process.direction = Vector3.UP
	splash_process.spread = 60.0
	splash_process.initial_velocity_max = 3.5
	splash_process.initial_velocity_min = 1.5
	splash_process.gravity = Vector3(0, -GRAVITY, 0)
	splash_process.color = Color(0.88, 0.95, 1.0, 0.7)
	set_active(false)

func _emitter(amount: int, life: float, mesh: Mesh) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.amount = amount
	emitter.lifetime = life
	emitter.local_coords = false
	emitter.mesh = mesh
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.gravity = Vector3(0, -GRAVITY, 0)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.1, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	emitter.color_ramp = fade
	add_child(emitter)
	return emitter

func set_active(on: bool) -> void:
	visible = on
	for emitter in [drops, mist, splash]:
		if is_instance_valid(emitter): emitter.emitting = on

## Máximo antes do mínimo: com o máximo ainda menor, o Godot rebaixa o mínimo e as
## gotas saíam com velocidade de 0 até o alvo; a maioria caía no meio do caminho.
func aim(origin: Vector3, target: Vector3) -> void:
	end_point = target
	var t := maxf(0.2, flight_time)
	var velocity := (target - origin - Vector3(0, -0.5 * GRAVITY * t * t, 0)) / t
	var speed := velocity.length()
	var direction := velocity / maxf(speed, 0.001)
	drops.global_position = origin
	# Vida da gota = tempo de voo, senão ela morre antes do alvo. O CPUParticles só
	# aplica lifetime novo ao reiniciar: troca só quando muda de verdade.
	if absf(drops.lifetime - t) > 0.08:
		drops.lifetime = t
		mist.lifetime = t * 1.2
		if drops.emitting:
			drops.restart()
			mist.restart()
	_drop_process.direction = direction
	_drop_process.initial_velocity_max = speed * 1.03
	_drop_process.initial_velocity_min = speed * 0.97
	mist.global_position = origin
	_mist_process.direction = direction
	_mist_process.initial_velocity_max = speed * 0.95
	_mist_process.initial_velocity_min = speed * 0.8
	splash.global_position = target
	var strength := clampf(pressure, 0.0, 1.0)
	# Pressão caindo (hidrante): gotas menores e arco mais baixo (flight_time do chamador).
	drops.scale_amount_min = 0.7 * drop_scale * maxf(strength, 0.3)
	drops.scale_amount_max = 1.6 * drop_scale * maxf(strength, 0.3)
