extends Node3D
## Impacto de bala por superfície (pedido do jogador em 29/10: "parece tudo muito simples em iluminação,
## impacto"). Antes cada material soltava sete cubinhos e uma nuvem sem luz (CombatEffects.impact): de noite
## a poeira brilhava igual ao dia, nada no impacto iluminava a cena e o tiro não deixava marca.
##
## Receita por superfície (quem decide o material é WeaponSurface.resolve; aqui só a apresentação):
##   metal    faíscas aditivas que caem e QUICAM no chão + clarão curto de luz + marca com borda de metal
##            exposto que fica em brasa ~1 s;
##   concreto pedrinhas, lascas claras e poeira sombreada; às vezes uma ou duas faíscas;
##   madeira  farpas alinhadas ao voo, lasquinhas e pó de serragem;
##   vidro    estilhaços pequenos com o material de vidro da rua (brilho especular) e pó branco;
##   terra, grama, areia, neve  jato estreito do próprio material para fora da superfície;
##   água     tiro que acerta o fundo de um lago (grupo native_water_surface) vira respingo na superfície.
## Pessoa (flesh) não passa por aqui: o sangue continua em CombatEffects.blood.
##
## Orçamento fixo, nada é criado depois do _ready:
##   - emissores CPUParticles3D em rodízio de POOL por família (como CombatEffects.BURST_POOL);
##   - faíscas numa simulação própria de MAX_SPARKS desenhada por um MultiMesh: CPUParticles3D não colide,
##     e a faísca que atravessa o chão era o que mais denunciava o efeito barato;
##   - um OmniLight3D de clarão que passa pelo LightBudget (até 25 m do jogador, dentro do teto de 8 luzes);
##   - MAX_MARKS Decals de marca em anel: a mais antiga cede a vaga; somem sozinhas em MARK_LIFETIME s.
## Malhas, materiais e texturas são estáticos (uma vez por processo, retidos em `resources()`) e o
## CombatEffectsPrewarm dispara tudo sob a cortina, então nenhum shader compila no tiroteio.
## GETECO_IMPACT_FX=0 volta ao impacto antigo (A/B no mesmo export). Custo em release não medido.
const LIGHT_BUDGET := preload("res://gameplay/lights/LightBudget.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const STREET := preload("res://gameplay/street_physics/StreetPhysics.gd")
const SELF_PATH := "res://gameplay/fx/ImpactFx.gd"
const POOL := 6
const GLITTER_POOL := 4
const MAX_SPARKS := 48
const MAX_MARKS := 40
const MARK_LIFETIME := 28.0
const MARK_FADE := 4.0
const MARK_GLOW := 1.3
const MARK_GLOW_ENERGY := 2.6
## Envelhecer e conferir o dono das marcas 10 vezes por segundo basta: o desvanecimento leva 4 s.
const MARK_TICK := 0.1
const FLASH_TIME := 0.075
const FLASH_ENERGY := 2.4
const FLASH_RANGE := 2.8
const SPARK_GRAVITY := 11.0
const SPARK_BOUNCE := 0.36
const SPARK_DRAG := 1.4
const SPARK_WIDTH := 0.011
## Chumbo da escopeta: a partir do quinto impacto no mesmo quadro sai só o essencial (pedrinhas/farpas e
## marca). Oito nuvens translúcidas sobrepostas custavam GPU sem ler melhor que quatro.
const FULL_IMPACTS_PER_FRAME := 4
## Fundo de lago mais fundo que isto não respinga (o tiro já se perdeu na água).
const WATER_DEPTH := 4.0
## Queda do jogador (PlayerAirMovement) também chama impact "concrete" sob os pés: poeira sim, furo de bala não.
const LANDING_RADIUS := 0.3
const TEXTURE_SIZE := 64
const SOIL := ["dirt", "sand", "grass", "snow"]
const MARK_FAMILY := {"metal": "metal", "concrete": "concrete", "world": "concrete", "wood": "wood",
	"dirt": "soil", "grass": "soil", "sand": "soil", "snow": "soil"}
## A cratera de terra é cinza e ganha a cor do chão aqui: uma textura para quatro chãos.
const SOIL_TINT := {"dirt": Color(0.42, 0.31, 0.2), "grass": Color(0.33, 0.27, 0.17),
	"sand": Color(0.7, 0.57, 0.4), "snow": Color(0.6, 0.67, 0.8)}
## Diâmetro (m) mínimo e máximo da marca por família.
const MARK_SIZE := {"metal": Vector2(0.07, 0.1), "concrete": Vector2(0.09, 0.14), "wood": Vector2(0.08, 0.12), "soil": Vector2(0.1, 0.16)}

static var _resources: Dictionary = {}

## CombatEffects dono deste nó (o jogador é `host.carry_source`).
var host: Node3D
## Rodízios que o último impacto disparou, na ordem (para teste e diagnóstico).
var last_recipe := PackedStringArray()
var _pools: Dictionary = {}
var _next: Dictionary = {}
var _frame := -1
var _frame_impacts := 0
var _spark_pos := PackedVector3Array()
var _spark_vel := PackedVector3Array()
var _spark_life := PackedFloat32Array()
var _spark_total := PackedFloat32Array()
var _spark_floor := PackedFloat32Array()
var _spark_next := 0
var _sparks_active := false
var _spark_drawn := 0
var _spark_multimesh: MultiMesh
var _spark_node: MultiMeshInstance3D
var _flash: OmniLight3D
var _flash_time := 0.0
var _flash_peak := FLASH_ENERGY
var _marks: Array[Decal] = []
var _mark_age := PackedFloat32Array()
var _mark_glow := PackedFloat32Array()
var _mark_anchor: Array = []
## Vaga presa a um corpo que se move. Bandeira à parte: no Godot 4 o objeto liberado compara igual a null,
## e o teste `_mark_anchor[i] != null` deixava a marca do carro sumido boiando.
var _mark_moves := PackedByteArray()
var _mark_anchor_id := PackedInt64Array()
var _mark_local: Array[Transform3D] = []
var _mark_last := PackedVector3Array()
var _next_mark := 0
var _visible_marks := 0
var _moving_marks := 0
var _glowing_marks := 0
var _mark_clock := 0.0
var _atlas_keepers: Array[Decal] = []
var _water_frame := -1
var _water_nodes: Array = []

static func enabled() -> bool:
	return OS.get_environment("GETECO_IMPACT_FX") != "0"

## Cria o nó filho de `effects` (CombatEffects._ready); nulo com o interruptor desligado.
static func attach(effects: Node3D) -> Node3D:
	if not enabled(): return null
	var node: Node3D = (load(SELF_PATH) as GDScript).new()
	node.name = "ImpactFx"
	node.host = effects
	effects.add_child(node)
	return node

func _ready() -> void:
	# Tudo aqui é posicionado no _process ou no instante do tiro: a interpolação de física atrasaria as
	# marcas que seguem o carro e as faíscas (mesmo motivo do CombatEffectsPrewarm).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var res := resources()
	_pools["debris"] = _make_pool(POOL, 12, 1.15, res.pebble, {"spin": 420.0, "shrink": true})
	_pools["flakes"] = _make_pool(POOL, 7, 0.95, res.flake, {"spin": 720.0, "shrink": true})
	_pools["splinters"] = _make_pool(POOL, 9, 1.2, res.splinter, {"align": true, "spin": 600.0, "shrink": true})
	_pools["dust"] = _make_pool(POOL, 6, 1.3, res.puff, {"ramp": res.dust_ramp, "scale_curve": res.dust_growth, "damping": 2.2, "explosiveness": 0.82})
	_pools["glints"] = _make_pool(POOL, 12, 0.85, STREET.glass_shard_mesh(), {"override": STREET.glass_shard_material(), "spin": 900.0, "ramp": res.glint_ramp})
	_pools["glitter"] = _make_pool(GLITTER_POOL, 22, 1.1, STREET.glass_shard_mesh(), {"override": STREET.glass_shard_material(), "spin": 900.0, "ramp": res.glint_ramp})
	_pools["drops"] = _make_pool(POOL, 16, 0.9, res.drop, {"align": true, "shrink": true, "explosiveness": 0.88})
	_pools["crown"] = _make_pool(POOL, 14, 0.6, res.drop, {"align": true, "shrink": true, "ring": true})
	for key in _pools: _next[key] = 0
	_spark_pos.resize(MAX_SPARKS)
	_spark_vel.resize(MAX_SPARKS)
	_spark_life.resize(MAX_SPARKS)
	_spark_total.resize(MAX_SPARKS)
	_spark_floor.resize(MAX_SPARKS)
	_spark_multimesh = MultiMesh.new()
	_spark_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_spark_multimesh.use_colors = true
	_spark_multimesh.mesh = res.spark
	_spark_multimesh.instance_count = MAX_SPARKS
	_spark_multimesh.visible_instance_count = 0
	_spark_node = MultiMeshInstance3D.new()
	_spark_node.name = "Sparks"
	_spark_node.multimesh = _spark_multimesh
	_spark_node.top_level = true
	_spark_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spark_node)
	_spark_node.global_transform = Transform3D.IDENTITY
	_flash = OmniLight3D.new()
	_flash.name = "ImpactFlash"
	_flash.light_color = Color(1.0, 0.72, 0.4)
	_flash.omni_range = FLASH_RANGE
	_flash.omni_attenuation = 1.6
	_flash.shadow_enabled = false
	# Clarão de décimos de segundo não alimenta a névoa volumétrica (mesma regra do clarão da explosão).
	_flash.light_volumetric_fog_energy = 0.0
	_flash.light_energy = 0.0
	_flash.top_level = true
	_flash.visible = false
	add_child(_flash)
	var marks: Dictionary = res.marks
	for index in MAX_MARKS:
		var decal := _make_decal(marks.concrete)
		decal.visible = false
		add_child(decal)
		_marks.append(decal)
		_mark_age.append(-1.0)
		_mark_glow.append(0.0)
		_mark_anchor.append(null)
		_mark_moves.append(0)
		_mark_anchor_id.append(0)
		_mark_local.append(Transform3D.IDENTITY)
		_mark_last.append(Vector3.ZERO)
	# Uma Decal escondida por família segura a textura no atlas de decals. Sem ela, a troca de textura
	# de uma vaga podia zerar os usuários de uma família e reconstruir o atlas no meio do tiroteio.
	for family in marks:
		var keeper := _make_decal(marks[family])
		keeper.name = "AtlasKeeper_" + str(family)
		keeper.visible = false
		add_child(keeper)
		_atlas_keepers.append(keeper)
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.register(self)
	set_process(false)

func _exit_tree() -> void:
	shutdown()
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.unregister(self)

## Malhas, materiais, curvas e texturas de todo impacto, criados uma vez por processo e retidos aqui:
## material liberado e recriado poderia voltar a compilar no meio do jogo.
static func resources() -> Dictionary:
	if not _resources.is_empty(): return _resources
	var began := STALL_WORK.begin()
	var res := {}
	# Lascas, pedrinhas, farpas e torrões: sombreados, a cor vem da partícula. A luz da rua e o clarão do
	# impacto agora pegam neles; o material antigo de faísca era sem luz e brilhava igual de dia e de noite.
	var chip := StandardMaterial3D.new()
	chip.vertex_color_use_as_albedo = true
	chip.roughness = 0.92
	# Gota d'água lisa: o mesmo shader opaco da lasca (só rugosidade e especular mudam, são uniformes).
	var wet := StandardMaterial3D.new()
	wet.vertex_color_use_as_albedo = true
	wet.roughness = 0.08
	wet.metallic_specular = 0.9
	var spark := StandardMaterial3D.new()
	spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark.vertex_color_use_as_albedo = true
	spark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	spark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var noise := FastNoiseLite.new()
	noise.seed = 291026
	noise.frequency = 0.11
	noise.fractal_octaves = 3
	# Poeira sombreada: de noite fica escura e só aparece onde há luz, como poeira de verdade.
	var dust := StandardMaterial3D.new()
	dust.vertex_color_use_as_albedo = true
	dust.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust.albedo_texture = _puff_texture(noise)
	dust.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dust.roughness = 1.0
	dust.metallic_specular = 0.0
	var pebble := SphereMesh.new()
	pebble.radius = 0.011
	pebble.height = 0.018
	pebble.radial_segments = 5
	pebble.rings = 2
	pebble.material = chip
	var flake := BoxMesh.new()
	flake.size = Vector3(0.028, 0.005, 0.02)
	flake.material = chip
	var splinter := BoxMesh.new()
	splinter.size = Vector3(0.006, 0.08, 0.011)
	splinter.material = chip
	var drop := SphereMesh.new()
	drop.radius = 0.011
	drop.height = 0.045
	drop.radial_segments = 6
	drop.rings = 3
	drop.material = wet
	var puff := QuadMesh.new()
	puff.size = Vector2(0.3, 0.3)
	puff.material = dust
	# Faísca: cubo unitário esticado pela base da instância (comprimento pela velocidade).
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3.ONE
	spark_mesh.material = spark
	res.pebble = pebble
	res.flake = flake
	res.splinter = splinter
	res.drop = drop
	res.puff = puff
	res.spark = spark_mesh
	res.materials = [chip, wet, spark, dust, STREET.glass_shard_material()]
	# Pedaço opaco encolhe no fim em vez de sumir de uma vez.
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.72, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	res.shrink = shrink
	var growth := Curve.new()
	growth.max_value = 2.8
	growth.add_point(Vector2(0.0, 0.55))
	growth.add_point(Vector2(1.0, 2.8))
	res.dust_growth = growth
	var dust_ramp := Gradient.new()
	dust_ramp.offsets = PackedFloat32Array([0.0, 0.08, 0.45, 1.0])
	dust_ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	res.dust_ramp = dust_ramp
	var glint_ramp := Gradient.new()
	glint_ramp.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	glint_ramp.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	res.glint_ramp = glint_ramp
	var marks := {}
	for family in ["metal", "concrete", "wood", "soil"]:
		marks[family] = _mark_textures(family, noise)
	res.marks = marks
	_resources = res
	STALL_WORK.finish_slow("impact_fx.resources", began, 4000)
	return _resources

func _make_pool(count: int, amount: int, life: float, mesh: Mesh, options: Dictionary) -> Array[CPUParticles3D]:
	var res := resources()
	var list: Array[CPUParticles3D] = []
	for slot in count:
		var emitter := CPUParticles3D.new()
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = float(options.get("explosiveness", 1.0))
		emitter.amount = amount
		emitter.lifetime = life
		emitter.lifetime_randomness = 0.4
		emitter.local_coords = false
		emitter.mesh = mesh
		emitter.direction = Vector3.UP
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if options.has("override"): emitter.material_override = options.override
		if options.get("align", false): emitter.particle_flag_align_y = true
		if options.has("spin"):
			# Gira no eixo Y da partícula (com align_y, o eixo do voo): pedra e farpa rolando, não carimbo.
			emitter.particle_flag_rotate_y = true
			emitter.angle_min = -180.0
			emitter.angle_max = 180.0
			emitter.angular_velocity_min = -float(options.spin)
			emitter.angular_velocity_max = float(options.spin)
		if options.get("shrink", false): emitter.scale_amount_curve = res.shrink
		if options.has("scale_curve"): emitter.scale_amount_curve = options.scale_curve
		if options.has("ramp"): emitter.color_ramp = options.ramp
		if options.has("damping"):
			emitter.damping_min = float(options.damping) * 0.6
			emitter.damping_max = float(options.damping)
		if options.get("ring", false):
			# Coroa do respingo: as gotas nascem num anel e se abrem para fora.
			emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			emitter.emission_ring_axis = Vector3.UP
			emitter.emission_ring_radius = 0.07
			emitter.emission_ring_inner_radius = 0.03
			emitter.emission_ring_height = 0.0
			emitter.radial_accel_min = 3.0
			emitter.radial_accel_max = 7.0
		add_child(emitter)
		list.append(emitter)
	return list

func _make_decal(textures: Dictionary) -> Decal:
	var decal := Decal.new()
	decal.size = Vector3(0.1, 0.12, 0.1)
	decal.texture_albedo = textures.albedo
	decal.texture_normal = textures.normal
	# Toda vaga leva a brasa da marca de metal; fora do metal a energia fica em zero.
	decal.texture_emission = (resources().marks.metal as Dictionary).glow
	decal.emission_energy = 0.0
	# Face virada para longe (o outro lado de um poste fino) não recebe a marca.
	decal.normal_fade = 0.45
	decal.upper_fade = 0.25
	decal.lower_fade = 0.25
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 30.0
	decal.distance_fade_length = 12.0
	decal.top_level = true
	return decal

## Devolve false quando o material não é deste módulo (pessoa): CombatEffects segue o caminho antigo.
func impact(point: Vector3, normal: Vector3, material: String, damage: float) -> bool:
	if material == "flesh": return false
	last_recipe = PackedStringArray()
	# Posição ou normal não finita: nada a desenhar (crash de 29/10 na ordenação da lista alfa).
	if not point.is_finite() or not normal.is_finite() or not is_finite(damage): return true
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_frame_impacts = 0
	_frame_impacts += 1
	var full := _frame_impacts <= FULL_IMPACTS_PER_FRAME
	var strength := clampf(0.75 + damage / 50.0, 0.75, 1.6)
	var level := _water_level(point)
	if not is_nan(level):
		_splash(_water_entry(point, level), strength, full)
		return true
	var landing := material == "concrete" and n.y > 0.7 and _near_player_feet(point)
	match material:
		"metal": _metal(point, n, strength, full)
		"wood": _wood(point, n, strength, full)
		"glass": _glass(point, n, strength, full)
		"dirt", "grass", "sand", "snow": _soil(point, n, material, strength, full)
		_: _concrete(point, n, strength, full, landing)
	# Vidro do carro já tem a rachadura Decal de VehicleGlassDamage; a queda do jogador não fura o chão.
	if material != "glass" and not landing: _mark(point, n, material, strength)
	set_process(true)
	return true

## Painel que cai (CombatEffects.glass_shatter): a chuva de cacos grande continua lá; aqui o brilho miúdo
## e o pó de vidro que dão leitura de estilhaço.
func glass_shatter(point: Vector3, normal: Vector3) -> void:
	last_recipe = PackedStringArray()
	if not point.is_finite() or not normal.is_finite(): return
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	_emit("glitter", point + n * 0.05, _tilt(n + Vector3.UP * 0.3, 0.3), Color(0.9, 0.97, 1.0, 0.95), 1.5, 4.5, 70.0, 0.2, 0.5, -11.0)
	_emit("dust", point + n * 0.05, n, Color(0.93, 0.96, 1.0, 0.3), 0.3, 1.0, 40.0, 0.35, 0.7, -0.3)

func _metal(point: Vector3, n: Vector3, strength: float, full: bool) -> void:
	_sparks(point, n, int(randf_range(7.0, 12.0) * strength), 1.0)
	_flash_at(point + n * 0.12, strength)
	if full: _emit("dust", point + n * 0.03, _tilt(n, 0.3), Color(0.34, 0.33, 0.33, 0.4), 0.15, 0.5, 25.0, 0.25, 0.45, 0.4)

func _concrete(point: Vector3, n: Vector3, strength: float, full: bool, landing: bool) -> void:
	var shade := randf_range(-0.05, 0.05)
	var base := Color(0.56 + shade, 0.55 + shade, 0.52 + shade)
	_emit("debris", point + n * 0.02, _tilt(n, 0.25), base.darkened(randf_range(0.0, 0.3)), 1.4 * strength, 4.2 * strength, randf_range(28.0, 42.0), 0.5, 1.35, -9.8)
	if full:
		# Lasca clara do concreto novo exposto, mais aberta e mais lenta que as pedrinhas.
		_emit("flakes", point + n * 0.02, _tilt(n, 0.4), Color(0.8, 0.78, 0.74).darkened(randf_range(0.0, 0.12)), 0.9 * strength, 2.8 * strength, 60.0, 0.6, 1.3, -9.8)
		_emit("dust", point + n * 0.05, _tilt(n, 0.2), Color(base.r + 0.12, base.g + 0.11, base.b + 0.1, 0.55), 0.35, 1.25 * strength, 26.0, 0.45, 0.9, 0.25)
	if not landing and randf() < 0.4: _sparks(point, n, randi_range(1, 3), 0.7)

func _wood(point: Vector3, n: Vector3, strength: float, full: bool) -> void:
	_emit("splinters", point + n * 0.02, _tilt(n, 0.3), Color(0.74, 0.57, 0.36).darkened(randf_range(0.0, 0.22)), 1.6 * strength, 4.2 * strength, randf_range(30.0, 45.0), 0.6, 1.5, -9.8)
	if full:
		_emit("debris", point + n * 0.02, _tilt(n, 0.35), Color(0.42, 0.28, 0.16), 0.8 * strength, 2.4 * strength, 50.0, 0.35, 0.8, -9.8)
		_emit("dust", point + n * 0.04, _tilt(n, 0.2), Color(0.66, 0.55, 0.4, 0.4), 0.25, 0.8 * strength, 30.0, 0.35, 0.7, 0.15)

func _glass(point: Vector3, n: Vector3, strength: float, full: bool) -> void:
	_emit("glints", point + n * 0.02, _tilt(n, 0.35), Color(0.85, 0.95, 1.0, 0.9), 1.0 * strength, 3.2 * strength, 50.0, 0.22, 0.55, -9.8)
	if full: _emit("dust", point + n * 0.03, n, Color(0.92, 0.96, 1.0, 0.32), 0.2, 0.7, 30.0, 0.25, 0.45, 0.1)

## Jato estreito do chão mole: torrão/grão/neve sai quase reto da superfície e cai em volta.
func _soil(point: Vector3, n: Vector3, material: String, strength: float, full: bool) -> void:
	var jet := _tilt(n, 0.12)
	match material:
		"sand":
			_emit("debris", point + n * 0.02, jet, Color(0.78, 0.66, 0.46).darkened(randf_range(0.0, 0.15)), 2.5 * strength, 5.5 * strength, randf_range(12.0, 18.0), 0.25, 0.6, -9.8)
			if full: _emit("dust", point + n * 0.05, jet, Color(0.82, 0.72, 0.54, 0.6), 0.8, 2.2 * strength, 16.0, 0.5, 1.1, -0.8)
		"snow":
			_emit("debris", point + n * 0.02, jet, Color(0.9, 0.93, 0.97), 1.8 * strength, 4.2 * strength, randf_range(16.0, 22.0), 0.6, 1.4, -9.8)
			if full: _emit("dust", point + n * 0.05, jet, Color(0.96, 0.97, 1.0, 0.8), 1.0, 2.6 * strength, 18.0, 0.5, 1.0, -1.5)
		_:
			var soil := Color(0.34, 0.25, 0.16) if material == "dirt" else Color(0.3, 0.23, 0.15)
			_emit("debris", point + n * 0.02, jet, soil.darkened(randf_range(0.0, 0.2)), 2.2 * strength, 5.2 * strength, randf_range(12.0, 20.0), 0.6, 1.5, -9.8)
			if full:
				if material == "grass": _emit("flakes", point + n * 0.03, _tilt(n, 0.3), Color(0.32, 0.45, 0.18).darkened(randf_range(0.0, 0.2)), 1.2 * strength, 3.0 * strength, 35.0, 0.5, 1.0, -7.0)
				_emit("dust", point + n * 0.05, jet, Color(0.5, 0.4, 0.28, 0.55), 0.7, 2.0 * strength, 18.0, 0.45, 0.95, -0.4)

func _splash(entry: Vector3, strength: float, full: bool) -> void:
	_emit("drops", entry, _tilt(Vector3.UP, 0.08), Color(0.78, 0.86, 0.9), 2.2 * strength, 5.0 * strength, randf_range(8.0, 16.0), 0.6, 1.3, -9.8)
	_emit("crown", entry, Vector3.UP, Color(0.85, 0.9, 0.95), 0.9 * strength, 2.0 * strength, 35.0, 0.5, 1.0, -9.8)
	if full: _emit("dust", entry + Vector3.UP * 0.05, Vector3.UP, Color(0.92, 0.95, 1.0, 0.5), 0.3, 1.0, 25.0, 0.35, 0.75, -0.6)

## Dispara o próximo emissor do rodízio `pool` em `point`, com o eixo +Y local em `direction`.
func _emit(pool: String, point: Vector3, direction: Vector3, color: Color, speed_min: float, speed_max: float, spread: float, scale_min: float, scale_max: float, gravity_y: float) -> void:
	if not point.is_finite() or not direction.is_finite(): return
	var list: Array = _pools[pool]
	var index: int = _next[pool]
	_next[pool] = (index + 1) % list.size()
	var emitter: CPUParticles3D = list[index]
	emitter.color = color
	emitter.initial_velocity_min = speed_min
	emitter.initial_velocity_max = speed_max
	emitter.spread = spread
	emitter.scale_amount_min = scale_min
	emitter.scale_amount_max = scale_max
	emitter.gravity = Vector3(0.0, gravity_y, 0.0)
	var up := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	emitter.global_transform = Transform3D(Basis(side, up, side.cross(up)), point)
	if not emitter.visible: emitter.visible = true
	emitter.restart()
	last_recipe.append(pool)

## Direção `n` com desvio aleatório (`amount` ~ seno do ângulo): cada impacto sai diferente.
static func _tilt(n: Vector3, amount: float) -> Vector3:
	var jitter := Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0))
	var tilted := n + jitter.normalized() * amount if jitter.length_squared() > 0.0001 else n
	return tilted.normalized() if tilted.length_squared() > 0.0001 else Vector3.UP

## Faíscas que caem e quicam no plano do chão achado por um raio só, no instante do impacto.
func _sparks(point: Vector3, n: Vector3, count: int, heat: float) -> void:
	var floor_y := point.y - 60.0
	if n.y > 0.6:
		floor_y = point.y
	else:
		# Camada 1 (mundo): a lataria do carro (camada 4) não segura a faísca que cai da porta.
		var below := _ray(point + n * 0.04, point + n * 0.04 + Vector3.DOWN * 4.0, 1)
		if not below.is_empty(): floor_y = (below.position as Vector3).y
	for i in count:
		var index := _spark_next
		_spark_next = (index + 1) % MAX_SPARKS
		var life := randf_range(0.22, 0.65) * (0.6 + 0.4 * heat)
		_spark_pos[index] = point + n * 0.02
		_spark_vel[index] = _tilt(n, 0.9) * randf_range(3.0, 8.5) * heat
		_spark_life[index] = life
		_spark_total[index] = life
		_spark_floor[index] = floor_y
	_sparks_active = true
	set_process(true)
	last_recipe.append("sparks")

func _flash_at(point: Vector3, strength: float) -> void:
	if not point.is_finite(): return
	var reference := _reference()
	if not reference.is_finite() or reference.distance_to(point) > LIGHT_BUDGET.LIGHT_RADIUS: return
	var was_lit := _flash.visible and _flash_time > 0.0
	_flash.global_position = point
	_flash.omni_range = FLASH_RANGE * randf_range(0.9, 1.1)
	_flash_peak = FLASH_ENERGY * clampf(strength, 0.8, 1.4) * randf_range(0.85, 1.15)
	_flash_time = FLASH_TIME
	if LIGHT_BUDGET.enabled:
		# Só o primeiro clarão de uma rajada força a rodada do orçamento; os seguintes só mudam a luz de lugar.
		if not was_lit: LIGHT_BUDGET.refresh(true)
	else:
		_flash.light_energy = _flash_peak
		_flash.visible = true
	set_process(true)
	last_recipe.append("flash")

## Pedido ao LightBudget como luz "transient": só ocupa vaga que sobrou e nunca apaga farol/giroflex
## por um quadro (aviso do MuzzleFx, 29/10).
func _budget_request() -> Dictionary:
	var lights: Array[Light3D] = [_flash]
	var wanted: Array[Dictionary] = []
	if _flash_time > 0.0 and is_visible_in_tree():
		_flash.set_meta("budget_energy", _flash_energy())
		wanted.append({"light": _flash, "headlight": false, "transient": true})
	return {"lights": lights, "wanted": wanted, "player": false, "camera": _reference()}

func _flash_energy() -> float:
	return _flash_peak * pow(clampf(_flash_time / FLASH_TIME, 0.0, 1.0), 1.5)

func _reference() -> Vector3:
	var player: Variant = host.get("carry_source") if is_instance_valid(host) else null
	if is_instance_valid(player) and player is Node3D: return (player as Node3D).global_position
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if is_instance_valid(camera) else Vector3.INF

func _near_player_feet(point: Vector3) -> bool:
	var player: Variant = host.get("carry_source") if is_instance_valid(host) else null
	return is_instance_valid(player) and player is Node3D and (player as Node3D).global_position.distance_to(point) < LANDING_RADIUS

func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	if not is_inside_tree() or not from.is_finite() or not to.is_finite(): return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var player: Variant = host.get("carry_source") if is_instance_valid(host) else null
	if is_instance_valid(player) and player is CollisionObject3D: query.exclude = [(player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

## Altura do espelho d'água acima de `point` (fundo de lago atingido), ou NAN. Mesma conta de
## VehicleSurfaceProbe.water_level, com folga de profundidade maior: o tiro acerta o fundo, não a roda.
func _water_level(point: Vector3) -> float:
	if not is_inside_tree(): return NAN
	var frame := Engine.get_process_frames()
	if frame != _water_frame:
		_water_frame = frame
		_water_nodes = get_tree().get_nodes_in_group("native_water_surface")
	for node in _water_nodes:
		if not is_instance_valid(node) or not node is Node3D or not node.has_method("contains_water"): continue
		if not (node as Node3D).is_visible_in_tree(): continue
		var level: float = (node as Node3D).global_position.y + (float(node.ALPINE_WATER_Y) if str(node.get("variant")) == "alpine" else 0.05)
		if point.y > level + 0.03 or level - point.y > WATER_DEPTH: continue
		if node.contains_water(point): return level
	return NAN

## Onde a bala entrou na água: a reta do jogador até o fundo cortando o espelho. O tiro chega aqui sem a
## direção (CombatEffects.impact só recebe ponto e normal); para a bala da polícia isto é aproximado.
func _water_entry(point: Vector3, level: float) -> Vector3:
	var entry := Vector3(point.x, level + 0.01, point.z)
	var shooter := _reference() + Vector3.UP * 1.35
	if shooter.is_finite() and shooter.y > level + 0.05 and shooter.y - point.y > 0.01:
		var t := (shooter.y - level) / (shooter.y - point.y)
		var crossing := shooter.lerp(point, t)
		if crossing.is_finite() and Vector2(crossing.x - point.x, crossing.z - point.z).length() < 8.0:
			entry = Vector3(crossing.x, level + 0.01, crossing.z)
	return entry

## Marca de bala: a vaga mais antiga do anel cede o lugar. Carro e objeto solto carregam a marca junto.
func _mark(point: Vector3, n: Vector3, material: String, strength: float) -> void:
	var family: String = MARK_FAMILY.get(material, "concrete")
	var textures: Dictionary = resources().marks[family]
	var tangent := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized().rotated(n, randf() * TAU)
	var xform := Transform3D(Basis(tangent, n, tangent.cross(n)), point)
	if not xform.origin.is_finite() or not xform.basis.x.is_finite() or not xform.basis.z.is_finite(): return
	var index := _next_mark
	_next_mark = (index + 1) % MAX_MARKS
	if _mark_age[index] < 0.0: _visible_marks += 1
	_release(index)
	var decal := _marks[index]
	var span: Vector2 = MARK_SIZE[family]
	var size := randf_range(span.x, span.y) * clampf(0.85 + strength * 0.15, 0.9, 1.1)
	var aspect := randf_range(0.85, 1.18)
	decal.size = Vector3(size * aspect, 0.12, size / aspect)
	decal.texture_albedo = textures.albedo
	decal.texture_normal = textures.normal
	var tint: Color = SOIL_TINT.get(material, Color.WHITE) if family == "soil" else Color.WHITE
	var lift := randf_range(0.9, 1.05)
	decal.modulate = Color(tint.r * lift, tint.g * lift, tint.b * lift, 1.0)
	decal.emission_energy = MARK_GLOW_ENERGY if family == "metal" else 0.0
	decal.global_transform = xform
	decal.visible = true
	_mark_age[index] = 0.0
	if family == "metal":
		_mark_glow[index] = MARK_GLOW
		_glowing_marks += 1
	var hit := _ray(point + n * 0.05, point - n * 0.07, 7)
	var body: Variant = hit.get("collider")
	_mark_anchor_id[index] = (body as Object).get_instance_id() if is_instance_valid(body) else 0
	if is_instance_valid(body) and (body is CharacterBody3D or body is RigidBody3D or body is AnimatableBody3D):
		var anchor := body as Node3D
		_mark_anchor[index] = anchor
		_mark_moves[index] = 1
		_mark_local[index] = anchor.global_transform.affine_inverse() * xform
		_mark_last[index] = anchor.global_position
		_moving_marks += 1
	last_recipe.append("mark_" + family)

## Solta os contadores da vaga (brasa, dono que se move) sem mexer na visibilidade.
func _release(index: int) -> void:
	if _mark_glow[index] > 0.0:
		_mark_glow[index] = 0.0
		_glowing_marks -= 1
	if _mark_moves[index] != 0:
		_mark_moves[index] = 0
		_moving_marks -= 1
	_mark_anchor[index] = null
	_mark_anchor_id[index] = 0

func _hide_mark(index: int) -> void:
	if _mark_age[index] < 0.0: return
	_release(index)
	_marks[index].visible = false
	_marks[index].emission_energy = 0.0
	_mark_age[index] = -1.0
	_visible_marks -= 1

func _process(delta: float) -> void:
	var began := STALL_WORK.begin()
	var active := false
	if _sparks_active: _update_sparks(delta)
	active = _sparks_active
	if _flash_time > 0.0:
		active = true
		_flash_time -= delta
		if _flash_time <= 0.0:
			_flash_time = 0.0
			_flash.visible = false
			_flash.light_energy = 0.0
		elif LIGHT_BUDGET.enabled:
			LIGHT_BUDGET.refresh()
		else:
			_flash.light_energy = _flash_energy()
	if _moving_marks > 0 or _glowing_marks > 0: _follow_marks(delta)
	_mark_clock += delta
	if _mark_clock >= MARK_TICK:
		_age_marks(_mark_clock)
		_mark_clock = 0.0
	if _visible_marks > 0: active = true
	if not active: set_process(false)
	STALL_WORK.finish_slow("impact_fx.process", began, 2000, self)

func _update_sparks(delta: float) -> void:
	var drag := maxf(0.0, 1.0 - SPARK_DRAG * delta)
	var drawn := 0
	for index in MAX_SPARKS:
		var life := _spark_life[index]
		if life <= 0.0: continue
		life -= delta
		var velocity := _spark_vel[index]
		velocity.y -= SPARK_GRAVITY * delta
		velocity *= drag
		var at := _spark_pos[index] + velocity * delta
		var floor_y := _spark_floor[index]
		if at.y < floor_y:
			at.y = floor_y + 0.003
			if velocity.y < 0.0:
				# Quique: perde mais de metade da subida e escorrega; faísca que bateu esfria mais rápido.
				velocity = Vector3(velocity.x * 0.6, -velocity.y * SPARK_BOUNCE, velocity.z * 0.6)
				life *= 0.8
		if life <= 0.0 or not at.is_finite() or not velocity.is_finite():
			_spark_life[index] = 0.0
			continue
		_spark_life[index] = life
		_spark_pos[index] = at
		_spark_vel[index] = velocity
		var speed := velocity.length()
		var heading := velocity / speed if speed > 0.05 else Vector3.UP
		var length := clampf(speed * 0.022, 0.012, 0.16)
		var side := heading.cross(Vector3.UP if absf(heading.y) < 0.95 else Vector3.RIGHT).normalized()
		var axis := heading * length
		var frame := Basis(side * SPARK_WIDTH, axis, side.cross(heading) * SPARK_WIDTH)
		_spark_multimesh.set_instance_transform(drawn, Transform3D(frame, at - axis * 0.5))
		# Esfria do branco-amarelo ao laranja e some; acima de 1 para o glow da noite pegar.
		var heat := life / _spark_total[index]
		_spark_multimesh.set_instance_color(drawn, Color(2.4, 1.1 + 1.0 * heat, 0.3 + 0.8 * heat * heat, clampf(heat * 1.8, 0.0, 1.0)))
		drawn += 1
	if drawn != _spark_drawn:
		_spark_multimesh.visible_instance_count = drawn
		_spark_drawn = drawn
	_sparks_active = drawn > 0

func _follow_marks(delta: float) -> void:
	for index in MAX_MARKS:
		if _mark_age[index] < 0.0: continue
		var anchor: Variant = _mark_anchor[index]
		if _mark_moves[index] != 0:
			if not is_instance_valid(anchor) or not (anchor as Node3D).is_inside_tree():
				_hide_mark(index)
				continue
			var body := anchor as Node3D
			var at := body.global_position
			# Carro do trânsito reciclado reaparece longe: a marca não vai junto.
			if not at.is_finite() or at.distance_squared_to(_mark_last[index]) > 400.0:
				_hide_mark(index)
				continue
			_mark_last[index] = at
			var follow := body.get_global_transform_interpolated() * _mark_local[index]
			if follow.origin.is_finite() and follow.basis.x.is_finite() and follow.basis.y.is_finite() and follow.basis.z.is_finite():
				_marks[index].global_transform = follow
		if _mark_glow[index] > 0.0:
			_mark_glow[index] -= delta
			if _mark_glow[index] <= 0.0:
				_mark_glow[index] = 0.0
				_glowing_marks -= 1
				_marks[index].emission_energy = 0.0
			else:
				_marks[index].emission_energy = MARK_GLOW_ENERGY * pow(_mark_glow[index] / MARK_GLOW, 2.0)

func _age_marks(step: float) -> void:
	for index in MAX_MARKS:
		if _mark_age[index] < 0.0: continue
		_mark_age[index] += step
		var age := _mark_age[index]
		if age >= MARK_LIFETIME:
			_hide_mark(index)
			continue
		# Chão de trecho descarregado ou objeto quebrado: a marca não fica boiando no ar.
		var id := _mark_anchor_id[index]
		if id != 0 and not is_instance_id_valid(id):
			_hide_mark(index)
			continue
		# Carro guardado no rodízio do trânsito fica escondido: a marca sai com ele. Corpo parado não
		# entra nesta conta: há colisor só de física, escondido, e a marca nele sumiria na hora.
		var anchor: Variant = _mark_anchor[index]
		if _mark_moves[index] != 0 and is_instance_valid(anchor) and not (anchor as Node3D).is_visible_in_tree():
			_hide_mark(index)
			continue
		if age > MARK_LIFETIME - MARK_FADE:
			var color := _marks[index].modulate
			color.a = clampf((MARK_LIFETIME - age) / MARK_FADE, 0.0, 1.0)
			_marks[index].modulate = color

## Sob a cortina (CombatEffectsPrewarm): cada rodízio, as faíscas, o clarão e uma marca de cada família
## uma vez diante da câmera. CombatEffects.clear apaga tudo depois.
func prewarm(origin: Vector3, view: Basis) -> void:
	if not origin.is_finite(): return
	var right := view.x.normalized()
	var toward := view.z.normalized()
	var slot := 0
	for key in _pools.keys():
		_emit(str(key), origin + right * (float(slot) - 3.5) * 0.8, toward, Color.WHITE, 0.4, 0.9, 30.0, 1.0, 1.0, 0.0)
		slot += 1
	_sparks(origin + view.y * 0.6, toward, 12, 1.0)
	# O clarão aparece mesmo fora do orçamento aqui: é a única vez, sob a cortina.
	_flash.global_position = origin + toward * 1.0
	_flash.light_energy = FLASH_ENERGY
	_flash.visible = true
	_flash_time = 0.2
	slot = 0
	for family in ["metal", "concrete", "wood", "dirt"]:
		_mark(origin - view.y * 0.6 + right * (float(slot) - 1.5) * 0.5, toward, family, 1.0)
		slot += 1
	set_process(true)

## Troca de região/descarga do combate: PARA e LIMPA as partículas, esconde marcas, faíscas e o clarão.
func clear() -> void:
	for list in _pools.values():
		for emitter: CPUParticles3D in list:
			if not is_instance_valid(emitter): continue
			# Sem restart(): no Godot 4.7 `restart(); emitting = false` dispara o emissor onde ele estava
			# (defeito visto no CombatEffects.clear). Escondido some na hora; o próximo _emit reacende.
			emitter.emitting = false
			emitter.visible = false
	_spark_life.fill(0.0)
	_sparks_active = false
	if _spark_multimesh != null:
		_spark_multimesh.visible_instance_count = 0
	_spark_drawn = 0
	for index in _marks.size():
		_hide_mark(index)
	_flash_time = 0.0
	if is_instance_valid(_flash):
		_flash.visible = false
		_flash.light_energy = 0.0
	set_process(false)

## Saída da árvore: sem restart (os emissores podem já ter saído), só para e esconde.
func shutdown() -> void:
	for list in _pools.values():
		for emitter: CPUParticles3D in list:
			if is_instance_valid(emitter): emitter.emitting = false
	_spark_life.fill(0.0)
	_sparks_active = false
	if _spark_multimesh != null: _spark_multimesh.visible_instance_count = 0
	_spark_drawn = 0
	for decal in _marks:
		if is_instance_valid(decal): decal.visible = false
	for index in _mark_age.size():
		_mark_age[index] = -1.0
		_mark_glow[index] = 0.0
		_mark_anchor[index] = null
		_mark_moves[index] = 0
		_mark_anchor_id[index] = 0
	_visible_marks = 0
	_moving_marks = 0
	_glowing_marks = 0
	_flash_time = 0.0
	if is_instance_valid(_flash): _flash.visible = false
	set_process(false)

## Quantos rodízios, emissores e vagas existem (o teste confere que nada cresce com o tiroteio).
func budget_counts() -> Dictionary:
	var emitters := 0
	for list in _pools.values(): emitters += (list as Array).size()
	return {"emitters": emitters, "sparks": MAX_SPARKS, "marks": _marks.size(), "visible_marks": _visible_marks, "children": get_child_count()}

## Nuvem macia com borda irregular para a poeira (64×64 com mipmaps, uma vez por processo).
static func _puff_texture(noise: FastNoiseLite) -> ImageTexture:
	var size := TEXTURE_SIZE
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var cloud := 0.62 + 0.38 * noise.get_noise_2d(float(x) * 1.7, float(y) * 1.7)
			var alpha := pow(clampf(1.0 - r, 0.0, 1.0), 1.4) * cloud
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## Textura de cor, relevo (normal) e, no metal, brasa de uma marca. A altura monta a normal: com ela a
## cratera pega a luz do poste, do farol e do clarão em vez de ser um adesivo chapado.
static func _mark_textures(family: String, noise: FastNoiseLite) -> Dictionary:
	var size := TEXTURE_SIZE
	var height := PackedFloat32Array()
	height.resize(size * size)
	var albedo := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var glow: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8) if family == "metal" else null
	var spokes := PackedFloat32Array([0.4, 1.7, 2.6, 3.9, 5.1])
	var reach := PackedFloat32Array([0.82, 0.62, 0.95, 0.7, 0.78])
	for y in size:
		for x in size:
			var u := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var angle := atan2(v, u)
			# Ruído pelo ângulo (círculo no espaço do ruído): borda irregular sem emenda.
			var jag := noise.get_noise_2d(cos(angle) * 9.0, sin(angle) * 9.0)
			var jag2 := noise.get_noise_2d(cos(angle) * 14.0 + 40.0, sin(angle) * 14.0)
			var grain := noise.get_noise_2d(float(x) * 2.0, float(y) * 2.0)
			var color := Color(0, 0, 0, 0)
			var h := 0.0
			var hot := 0.0
			match family:
				"metal":
					var hole := 0.15 + 0.035 * jag
					var ring := 0.42 + 0.09 * jag2
					if r < hole:
						color = Color(0.05, 0.05, 0.055, 1.0)
						h = -1.0
						hot = 0.55
					elif r < ring:
						var t := (r - hole) / (ring - hole)
						var bright := lerpf(0.9, 0.6, t) * (0.92 + 0.12 * grain)
						color = Color(bright, bright * 0.99, bright * 0.96, 1.0 - 0.3 * t)
						h = sin(t * PI) * 0.45 - (1.0 - t) * 0.3
						hot = 1.0 - t
					else:
						var t := clampf((r - ring) / (1.0 - ring), 0.0, 1.0)
						color = Color(0.1, 0.09, 0.085, 0.45 * pow(1.0 - t, 2.0) * (0.75 + 0.25 * grain))
				"concrete":
					var core := 0.11 + 0.03 * jag
					var crater := 0.33 + 0.12 * jag2
					if r < core:
						color = Color(0.06, 0.06, 0.06, 1.0)
						h = -1.0
					elif r < crater:
						var t := (r - core) / (crater - core)
						var c := lerpf(0.2, 0.36, t) * (0.85 + 0.3 * grain)
						color = Color(c, c * 0.98, c * 0.95, 1.0)
						h = -0.75 * (1.0 - t) + 0.1 * grain
					else:
						var t := clampf((r - crater) / (1.0 - crater), 0.0, 1.0)
						# Lascas soltas do concreto novo em volta da cratera, e uma poeira clara bem fraca.
						if grain > 0.05 and t < 0.6:
							color = Color(0.82, 0.8, 0.76, 0.9 * (1.0 - t / 0.6))
							h = 0.15
						else:
							color = Color(0.75, 0.73, 0.7, 0.16 * (1.0 - t))
						for k in spokes.size():
							var off := absf(wrapf(angle - spokes[k], -PI, PI)) * r
							if r < reach[k] and off < 0.022 * (1.0 - r) + 0.006:
								color = Color(0.14, 0.13, 0.12, 0.85 * (1.0 - r / reach[k]))
								h = -0.3
				"wood":
					var hole := 0.14 + 0.03 * jag
					# Farpas compridas no sentido do veio (eixo v da textura).
					var spike := 0.3 + 0.32 * pow(absf(sin(angle)), 3.0) * (0.6 + 0.4 * jag2)
					var streak := noise.get_noise_2d(float(x) * 0.6, float(y) * 6.0)
					if r < hole:
						color = Color(0.07, 0.045, 0.03, 1.0)
						h = -1.0
					elif r < spike:
						var t := (r - hole) / (spike - hole)
						var fresh := 0.85 + 0.25 * streak
						color = Color(0.8 * fresh, 0.64 * fresh, 0.42 * fresh, 1.0 - 0.5 * t)
						h = 0.25 * (1.0 - t)
					else:
						var t := clampf((r - spike) / (1.0 - spike), 0.0, 1.0)
						color = Color(0.12, 0.08, 0.05, 0.25 * pow(1.0 - t, 2.0))
				_:
					var crater := 0.3 + 0.1 * jag
					if r < crater:
						var t := r / crater
						var c := lerpf(0.22, 0.42, t)
						color = Color(c, c, c, 0.92)
						h = -0.9 * (1.0 - t * t)
					else:
						var t := clampf((r - crater) / (1.0 - crater), 0.0, 1.0)
						if grain > 0.1:
							color = Color(0.55, 0.55, 0.55, 0.6 * (1.0 - t))
							h = 0.2
						else:
							color = Color(0.4, 0.4, 0.4, 0.12 * (1.0 - t))
			color.a = clampf(color.a, 0.0, 1.0)
			albedo.set_pixel(x, y, color)
			height[y * size + x] = h
			if glow != null:
				var g := hot * hot
				glow.set_pixel(x, y, Color(1.0 * g, 0.42 * g, 0.08 * g, 1.0))
	var strength := 3.0 if family == "metal" else 4.0
	var normal := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var left := height[y * size + maxi(x - 1, 0)]
			var right := height[y * size + mini(x + 1, size - 1)]
			var up := height[maxi(y - 1, 0) * size + x]
			var down := height[mini(y + 1, size - 1) * size + x]
			var facing := Vector3((left - right) * strength, (up - down) * strength, 1.0).normalized()
			normal.set_pixel(x, y, Color(facing.x * 0.5 + 0.5, facing.y * 0.5 + 0.5, facing.z * 0.5 + 0.5, 1.0))
	var result := {}
	for pair in [["albedo", albedo], ["normal", normal], ["glow", glow]]:
		var image: Image = pair[1]
		if image == null: continue
		image.generate_mipmaps()
		result[pair[0]] = ImageTexture.create_from_image(image)
	return result
