extends Node3D
## Papel e folhas levados pelas rajadas do clima (WindField), no porto, na costa e na serra.
## Um emissor só, em coordenadas de mundo: nasce a barlavento do foco, rente ao chão,
## e cruza a tela girando. Quase nada no calmo; a rajada é que levanta o lixo.
## O deserto tem a própria areia (DesertAmbientLife, que também lê o WindField).
## GETECO_WIND_DEBRIS=0 desliga (A/B): Weather nem cria o nó.
const TEXTURES := preload("res://runtime/atmosphere/WeatherParticleTextures.gd")
static var enabled := OS.get_environment("GETECO_WIND_DEBRIS") != "0"
const AMOUNT := 56
const LIFETIME := 3.0
## O meio da caixa fica a barlavento: o papel atravessa a vista em vez de nascer no fim dela.
const UPWIND := 10.0
const SPREAD := Vector3(20,.45,20)
const LIFT := .6
var emitter: GPUParticles3D
var process: ParticleProcessMaterial
## Pré-aquecimento (RainPrewarm) solta tudo sob a cortina, com vento de mentira se preciso.
var force := false
var ratio := 0.0
var _desert := 0.0
var _hidden := true

func _ready() -> void:
	name = "WindDebris"
	emitter = GPUParticles3D.new()
	emitter.name = "Litter"
	emitter.amount = AMOUNT
	emitter.lifetime = LIFETIME
	emitter.local_coords = false
	emitter.fixed_fps = 30
	emitter.emitting = false
	emitter.visibility_aabb = AABB(Vector3(-45,-5,-45),Vector3(90,10,90))
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	process = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = SPREAD
	process.direction = Vector3(1,.06,0)
	process.spread = 12.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 4.0
	# Quase sem queda: o papel corre rente ao chão; sem colisão, então não pode afundar.
	process.gravity = Vector3(0,-.15,0)
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -540.0
	process.angular_velocity_max = 540.0
	process.scale_min = .8
	process.scale_max = 1.3
	# Quadro sorteado no atlas (papel, jornal, duas folhas), sem animar.
	process.anim_offset_max = 1.0
	# Nasce e some encolhendo: recorte alfa não esvai, então a escala faz a entrada e a saída.
	var curve := Curve.new()
	curve.add_point(Vector2(0,0))
	curve.add_point(Vector2(.08,1))
	curve.add_point(Vector2(.85,1))
	curve.add_point(Vector2(1,0))
	var scale_curve := CurveTexture.new()
	scale_curve.curve = curve
	process.scale_curve = scale_curve
	var shade := Gradient.new()
	shade.colors = PackedColorArray([Color(.72,.72,.72),Color.WHITE])
	var shade_ramp := GradientTexture1D.new()
	shade_ramp.gradient = shade
	process.color_initial_ramp = shade_ramp
	emitter.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(.45,.45)
	var material := StandardMaterial3D.new()
	material.albedo_texture = TEXTURES.litter()
	material.vertex_color_use_as_albedo = true
	# Recorte em vez de mistura: sem ordenação entre papéis e sem custo de transparência.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = .5
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.particles_anim_h_frames = 4
	material.particles_anim_v_frames = 1
	material.particles_anim_loop = false
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.roughness = 1.0
	quad.material = material
	emitter.draw_pass_1 = quad
	add_child(emitter)

## Fração do emissor ligada: rajada e vento de verdade; nada no deserto nem abrigado.
static func amount_for(gust: float, speed: float, desert: float) -> float:
	return clampf((1.0-desert)*smoothstep(.12,.6,gust)*smoothstep(1.5,4.0,speed),0.0,1.0)

## Chamado pelo Weather a cada atualização do clima (5 Hz).
func set_conditions(desert: float, hidden: bool) -> void:
	_desert = desert
	_hidden = hidden

## Todo quadro, depois do vento andar.
func advance(wind: Vector3, gust: float, focus: Vector3) -> void:
	var speed := wind.length()
	if force and speed < 3.0:
		wind = Vector3(5,0,0)
		speed = 5.0
		gust = 1.0
	ratio = 1.0 if force else 0.0 if _hidden else amount_for(gust,speed,_desert)
	# Abrigo esconde no mesmo quadro, como a chuva; papel que já voava não fica no telhado.
	var shown := force or not _hidden
	if visible != shown: visible = shown
	var emit := ratio > .02
	if emitter.emitting != emit: emitter.emitting = emit
	if not shown or speed < .1: return
	emitter.amount_ratio = ratio
	var direction := wind/speed
	process.direction = Vector3(direction.x,.06,direction.z).normalized()
	process.initial_velocity_min = speed*.7
	process.initial_velocity_max = speed*1.15
	emitter.global_position = focus-direction*UPWIND+Vector3.UP*LIFT
