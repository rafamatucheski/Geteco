extends Node
## Aparência do dano no veículo: desgaste progressivo, incêndio no motor e carcaça carbonizada.
##
## Antes a destruição trocava TODAS as peças (vidro, farol, pneu, lataria) por um único
## material chapado #292728. Esse cinza quente, sob a luz amarela da cidade, lia como marrom:
## o carro "enferrujava" em vez de explodir. Aqui cada superfície é tratada pelo que ela é.
##
## Regras deliberadas:
## - O desgaste NÃO escurece a cor da pintura. Escurecer um amarelo ou laranja mantendo o
##   matiz dá exatamente oliva/marrom. O dano aparece como riscos de metal nu, amassados
##   (mapa de normal) e perda de brilho.
## - Abaixo de BURN_RATIO o motor pega fogo e a vida escoa até explodir, como o
##   `_begin_combustion` da V1. O escoamento passa pelo `receive_damage` normal, então a
##   explosão continua saindo do sinal `destroyed` já ligado pelos mundos.

const RESOURCES := preload("res://gameplay/vehicle_effects/VehicleEffectResources.gd")
const STREET_PHYSICS := preload("res://gameplay/street_physics/StreetPhysics.gd")
const BURN_RATIO := .2
## Segundos entre o limiar de fogo e a explosão, com o carro parado de levar tiro.
const BURN_SECONDS := 3.5
const WEAR_STAGES := 3
const SAG := .14
## A carcaça continua queimando depois da explosão, com o fogo minguando até apagar.
const WRECK_FIRE_SECONDS := 11.0
const HOP_GRAVITY := 20.0

static var _scratch_textures: Array[Texture2D] = []
static var _dent_normal: Texture2D
static var _char_albedo: Texture2D
static var _char_embers: Texture2D

var vehicle: CharacterBody3D
var burning := false
var _flame_ignited := false
var wrecked := false
var _stage := 0
var _paint_base: Dictionary = {}
var _saved: Array = []
var _last_source: WeakRef
var _fire: GPUParticles3D
var _fire_light: OmniLight3D
var _smoke: GPUParticles3D
var _ember: StandardMaterial3D
var _tween: Tween
var _rng := RandomNumberGenerator.new()
var _hop_active := false
var _hop_height := 0.0
var _hop_velocity := 0.0
var _hop_tilt := Vector2.ZERO
var _hop_spin := Vector2.ZERO
var _hop_rest := Vector2.ZERO
var _hop_bounces := 0
var _hop_landed := false
var _wreck_fire_time := 0.0

func configure(car: CharacterBody3D) -> void:
	vehicle = car
	_rng.seed = 9173 + car.get_instance_id()

func _ready() -> void:
	set_physics_process(false)

func note_source(source: Node) -> void:
	if source != null: _last_source = weakref(source)

## Chamado a cada dano recebido (vivo) e a cada reparo.
func refresh() -> void:
	var ratio: float = clampf(vehicle.health / maxf(1.0, vehicle.max_health), 0.0, 1.0)
	_apply_wear(1.0 - ratio)
	var should_burn: bool = vehicle.health > 0 and (_flame_ignited or ratio <= BURN_RATIO)
	if should_burn != burning:
		burning = should_burn
		set_physics_process(burning)
		if not burning: _stop_fire()

func _physics_process(delta: float) -> void:
	if wrecked:
		_step_wreck(delta)
		return
	if not burning or vehicle.health <= 0:
		burning = false
		_stop_fire()
		set_physics_process(false)
		return
	_update_fire()
	var source: Node = _last_source.get_ref() if _last_source != null else null
	vehicle.receive_damage(vehicle.max_health * BURN_RATIO / BURN_SECONDS * delta, source)

# --- Desgaste -----------------------------------------------------------------------------

func _apply_wear(wear: float) -> void:
	var stage: int = clampi(int(ceil(wear * WEAR_STAGES - .35)), 0, WEAR_STAGES)
	for material: StandardMaterial3D in vehicle._paint.materials if vehicle._paint != null else []:
		if not _paint_base.has(material):
			_paint_base[material] = {"roughness": material.roughness, "metallic": material.metallic,
				"clearcoat": material.clearcoat_enabled, "dents": material.albedo_texture == null and material.normal_texture == null}
		var base: Dictionary = _paint_base[material]
		material.roughness = lerpf(base.roughness, maxf(base.roughness, .68), wear)
		material.metallic = lerpf(base.metallic, base.metallic * .55, wear)
		material.clearcoat_enabled = base.clearcoat and wear < .4
		if stage == _stage: continue
		material.detail_enabled = stage > 0
		if stage > 0:
			material.detail_albedo = _scratches(stage - 1)
			material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
			material.uv2_triplanar = true
			material.uv2_scale = Vector3(.42, .42, .42)
		# Amassado só em pintura sem textura própria: o triplanar em UV1 deslocaria a textura.
		var dented: bool = base.dents and stage >= 2
		material.normal_enabled = dented
		if dented:
			material.normal_texture = _dents()
			material.normal_scale = .55 if stage == 2 else 1.0
			material.uv1_triplanar = true
			material.uv1_scale = Vector3(.55, .55, .55)
		elif base.dents:
			material.normal_texture = null
			material.uv1_triplanar = false
			material.uv1_scale = Vector3.ONE
	_stage = stage

## Riscos de metal nu (cinza-prata neutro) e marcas de fuligem cinza: nada de tom quente.
static func _scratches(level: int) -> Texture2D:
	if _scratch_textures.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 4401
		for index in WEAR_STAGES:
			var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
			image.fill(Color(0, 0, 0, 0))
			# Fuligem só no dano pesado e quase opaca: mancha escura translúcida sobre
			# amarelo/laranja é justamente o que lê como marrom.
			for mark in [0, 4, 12][index]:
				var center := Vector2(rng.randf() * 256.0, rng.randf() * 256.0)
				var radius := rng.randf_range(5.0, 12.0 + index * 3.0)
				for y in range(int(center.y - radius), int(center.y + radius)):
					for x in range(int(center.x - radius), int(center.x + radius)):
						var falloff := 1.0 - Vector2(x, y).distance_to(center) / radius
						if falloff <= 0: continue
						var pixel := Vector2i(posmod(x, 256), posmod(y, 256))
						var alpha := maxf(image.get_pixelv(pixel).a, clampf(falloff * 2.2, 0.0, .92))
						image.set_pixelv(pixel, Color(.035, .037, .042, alpha))
			for scratch in [26, 70, 150][index]:
				var start := Vector2(rng.randf() * 256.0, rng.randf() * 256.0)
				var direction := Vector2.from_angle(rng.randf_range(-.5, .5) + (PI if rng.randf() < .5 else 0.0))
				var length := rng.randf_range(10.0, 38.0 + index * 12.0)
				var tone := rng.randf_range(.55, .78)
				for step in int(length):
					var point := start + direction * step + Vector2(0, sin(step * .21) * 1.3)
					var pixel := Vector2i(posmod(int(point.x), 256), posmod(int(point.y), 256))
					image.set_pixelv(pixel, Color(tone, tone + .01, tone + .025, .95))
			image.generate_mipmaps()
			_scratch_textures.append(ImageTexture.create_from_image(image))
	return _scratch_textures[level]

static func _dents() -> Texture2D:
	if _dent_normal == null:
		var noise := FastNoiseLite.new()
		noise.seed = 812
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = .018
		var texture := NoiseTexture2D.new()
		texture.width = 256
		texture.height = 256
		texture.seamless = true
		texture.as_normal_map = true
		texture.bump_strength = 5.0
		texture.noise = noise
		_dent_normal = texture
	return _dent_normal

## Carvão preto-frio com placas de cinza clara; `embers` devolve a máscara das rachaduras.
static func _char(embers: bool) -> Texture2D:
	if _char_albedo == null:
		var noise := FastNoiseLite.new()
		noise.seed = 377
		noise.frequency = .04
		noise.fractal_octaves = 4
		var cracks := FastNoiseLite.new()
		cracks.seed = 91
		cracks.frequency = .05
		cracks.fractal_octaves = 2
		var albedo := Image.create(128, 128, false, Image.FORMAT_RGB8)
		var glow := Image.create(128, 128, false, Image.FORMAT_RGB8)
		for y in 128:
			for x in 128:
				var ash := smoothstep(.3, .55, noise.get_noise_2d(x, y))
				var tone := lerpf(.028, .2, ash)
				albedo.set_pixel(x, y, Color(tone, tone * 1.01, tone * 1.06))
				# Linhas finas onde o ruído cruza zero: rachaduras, não manchas.
				var crack := 1.0 - smoothstep(.0, .014, absf(cracks.get_noise_2d(x, y)))
				glow.set_pixel(x, y, Color.WHITE * crack * (1.0 - ash))
		albedo.generate_mipmaps()
		glow.generate_mipmaps()
		_char_albedo = ImageTexture.create_from_image(albedo)
		_char_embers = ImageTexture.create_from_image(glow)
	return _char_embers if embers else _char_albedo

# --- Incêndio no motor --------------------------------------------------------------------

func _update_fire() -> void:
	if not is_instance_valid(_fire):
		# Chama: núcleo pequeno e aditivo (sprite macio, sem "wisp"), que sobe rápido
		# e encolhe; a versão anterior usava quads grandes em alpha-mix que viravam
		# um borrão laranja parado sobre o capô.
		_fire = RESOURCES.emitter("EngineFire", 64, .55, Vector2(.55, .55), false)
		var flame_mesh: QuadMesh = _fire.draw_pass_1.duplicate(true)
		(flame_mesh.material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_fire.draw_pass_1 = flame_mesh
		var process := RESOURCES.particle_process()
		process.emission_sphere_radius = .35
		process.spread = 12.0
		process.initial_velocity_min = 1.6
		process.initial_velocity_max = 2.8
		process.scale_min = .6
		process.scale_max = 1.2
		var shrink := Curve.new()
		shrink.add_point(Vector2(0, .7))
		shrink.add_point(Vector2(.3, 1))
		shrink.add_point(Vector2(1, .15))
		var shrink_texture := CurveTexture.new()
		shrink_texture.curve = shrink
		process.scale_curve = shrink_texture
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, .3, .7, 1.0])
		ramp.colors = PackedColorArray([Color(1, .85, .45, .9), Color(1, .45, .1, .75), Color(.6, .12, .03, .35), Color(0, 0, 0, 0)])
		var ramp_texture := GradientTexture1D.new()
		ramp_texture.gradient = ramp
		process.color_ramp = ramp_texture
		_fire.process_material = process
		vehicle.add_child(_fire)
		_fire.top_level = true
		# Fumaça escura separada, acima da chama: é ela que lê como "carro pegando fogo"
		# vista de cima, e esconde o corte seco do topo das partículas de chama.
		_smoke = RESOURCES.emitter("EngineSmoke", 28, 2.4, Vector2(1.3, 1.3), true)
		var smoke := RESOURCES.particle_process()
		smoke.emission_sphere_radius = .4
		smoke.spread = 20.0
		smoke.initial_velocity_min = 1.0
		smoke.initial_velocity_max = 1.8
		smoke.gravity = Vector3(.25, .3, 0)
		smoke.scale_min = .8
		smoke.scale_max = 1.4
		var grow := Curve.new()
		grow.add_point(Vector2(0, .5))
		grow.add_point(Vector2(1, 2.2))
		var grow_texture := CurveTexture.new()
		grow_texture.curve = grow
		smoke.scale_curve = grow_texture
		var smoke_ramp := Gradient.new()
		smoke_ramp.offsets = PackedFloat32Array([0.0, .15, .6, 1.0])
		smoke_ramp.colors = PackedColorArray([Color(.1, .09, .08, 0), Color(.12, .11, .1, .6), Color(.2, .2, .21, .35), Color(.3, .3, .32, 0)])
		var smoke_texture := GradientTexture1D.new()
		smoke_texture.gradient = smoke_ramp
		smoke.color_ramp = smoke_texture
		_smoke.process_material = smoke
		vehicle.add_child(_smoke)
		_smoke.top_level = true
		_fire_light = OmniLight3D.new()
		_fire_light.light_color = Color(1, .5, .18)
		_fire_light.omni_range = 5.0
		_fire_light.shadow_enabled = false
		vehicle.add_child(_fire_light)
	var hood: Vector3 = Vector3(0, .85, -vehicle.half_length * .58)
	_fire.global_position = vehicle.to_global(hood)
	_fire.emitting = true
	_smoke.global_position = _fire.global_position + Vector3.UP * .5
	_smoke.emitting = true
	_fire_light.position = hood + Vector3.UP * .4
	_fire_light.light_energy = 1.6 + _rng.randf_range(-.5, .5)
	_fire_light.visible = true

func _stop_fire() -> void:
	if is_instance_valid(_fire): _fire.emitting = false
	if is_instance_valid(_smoke): _smoke.emitting = false
	if is_instance_valid(_fire_light): _fire_light.visible = false

## Impacto direto de lança-chamas inicia o fogo no capô mesmo antes do limiar
## de dano pesado. O escoamento continua usando o dano normal do veículo.
func ignite(source: Node = null) -> void:
	if not is_instance_valid(vehicle) or vehicle.health <= 0 or wrecked: return
	_flame_ignited = true
	if source != null: note_source(source)
	if not burning:
		burning = true
		set_physics_process(true)
	_update_fire()

# --- Carcaça ------------------------------------------------------------------------------

## Explodiu: lataria carbonizada com brasa que esfria, vidro estourado, pneu derretido,
## lanternas apagadas, e o corpo pula com a explosão e assenta sobre os aros.
func wreck() -> void:
	if wrecked: return
	wrecked = true
	burning = false
	_flame_ignited = false
	set_physics_process(false)
	_stop_fire()
	_ember = StandardMaterial3D.new()
	_ember.albedo_texture = _char(false)
	_ember.metallic = .3
	_ember.roughness = .92
	_ember.uv1_triplanar = true
	_ember.uv1_scale = Vector3(.22, .22, .22)
	# A brasa fica só nas rachaduras da máscara; emissão chapada deixava a carcaça laranja.
	_ember.emission_enabled = true
	_ember.emission = Color(.9, .22, .04)
	_ember.emission_texture = _char(true)
	_ember.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	_ember.emission_energy_multiplier = 1.1
	var molten := StandardMaterial3D.new()
	molten.albedo_color = Color(.02, .02, .022)
	molten.roughness = 1.0
	var dead_lens := StandardMaterial3D.new()
	dead_lens.albedo_color = Color(.06, .06, .065)
	dead_lens.roughness = .35
	var shattered := StandardMaterial3D.new()
	shattered.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shattered.albedo_color = Color(0, 0, 0, 0)
	var replacement := {"body": _ember, "rubber": molten, "lens": dead_lens, "glass": shattered}
	for part: MeshInstance3D in vehicle.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		var key := _key(part)
		if part.material_override != null:
			_saved.append([part, -1, part.material_override])
			part.material_override = replacement[_role(part.material_override as StandardMaterial3D, key)]
			continue
		var surface_keys: Array = _surface_keys(part)
		for index in part.mesh.get_surface_count():
			var surface_key: String = str(surface_keys[index]) if index < surface_keys.size() else key
			_saved.append([part, index, part.get_surface_override_material(index)])
			part.set_surface_override_material(index, replacement[_role(part.get_active_material(index) as StandardMaterial3D, surface_key)])
	_blast_hop()

## Salto balístico do corpo. Antes era um tween fixo (sobe .75 m em .16 s e quica com
## TRANS_BOUNCE): lia como desenho animado, com a mesma altura para moto e caminhão. Agora a
## frente (onde fica o motor que pegou fogo) levanta primeiro, o corpo cai sob gravidade,
## quica uma vez amortecido e assenta torto sobre os aros. Veículo pesado salta menos.
func _blast_hop() -> void:
	if is_instance_valid(_tween): _tween.kill()
	var mass := 1.0
	var handling = vehicle.get("handling")
	if handling != null and handling.get("mass") != null: mass = maxf(.5, float(handling.mass))
	var lift := 1.0 / sqrt(mass)
	_hop_height = 0.0
	_hop_velocity = _rng.randf_range(4.4, 5.4) * lift
	_hop_tilt = Vector2.ZERO
	_hop_spin = Vector2(_rng.randf_range(1.5, 2.3), _rng.randf_range(-1.3, 1.3)) * lift
	_hop_rest = Vector2(_rng.randf_range(-.035, .035), _rng.randf_range(-.06, .06))
	_hop_bounces = 0
	_hop_landed = false
	_hop_active = true
	_wreck_fire_time = WRECK_FIRE_SECONDS
	if is_instance_valid(STREET_PHYSICS.instance):
		STREET_PHYSICS.instance.spawn_glass(vehicle.global_position + Vector3.UP * 1.0, Vector3.UP)
	_update_fire()
	set_physics_process(true)
	# A brasa esfria até sobrar só a lataria queimada.
	_tween = vehicle.create_tween()
	_tween.tween_property(_ember, "emission_energy_multiplier", 0.0, 7.0).set_trans(Tween.TRANS_SINE)

func _step_wreck(delta: float) -> void:
	if _hop_active: _step_hop(delta)
	if _wreck_fire_time > 0.0:
		_wreck_fire_time = maxf(0.0, _wreck_fire_time - delta)
		var strength := _wreck_fire_time / WRECK_FIRE_SECONDS
		_update_fire()
		_fire.amount_ratio = clampf(strength * 1.4, 0.0, 1.0)
		_smoke.amount_ratio = clampf(strength * 2.0, .3, 1.0)
		_fire_light.light_energy *= strength
		if _wreck_fire_time <= 0.0: _stop_fire()
	if not _hop_active and _wreck_fire_time <= 0.0: set_physics_process(false)

func _step_hop(delta: float) -> void:
	var visual: Node3D = vehicle.visual
	if not is_instance_valid(visual):
		_hop_active = false
		return
	if not _hop_landed:
		_hop_velocity -= HOP_GRAVITY * delta
		_hop_height += _hop_velocity * delta
		_hop_tilt += _hop_spin * delta
		# No ar a frente volta a cair: o giro perde força e inverte perto do pico.
		_hop_spin -= _hop_tilt * 9.0 * delta
		if _hop_height <= -SAG and _hop_velocity < 0.0:
			_hop_height = -SAG
			if _hop_bounces < 1 and _hop_velocity < -2.0:
				_hop_bounces += 1
				_hop_velocity = -_hop_velocity * .22
				_hop_spin *= -.35
			else:
				_hop_velocity = 0.0
				_hop_landed = true
	else:
		_hop_tilt = _hop_tilt.lerp(_hop_rest, 1.0 - exp(-7.0 * delta))
		if _hop_tilt.distance_to(_hop_rest) < .002:
			_hop_tilt = _hop_rest
			_hop_active = false
	visual.position.y = _hop_height
	visual.rotation = Vector3(_hop_tilt.x, visual.rotation.y, _hop_tilt.y)

func restore() -> void:
	if is_instance_valid(_tween): _tween.kill()
	_hop_active = false
	_wreck_fire_time = 0.0
	if is_instance_valid(_fire): _fire.amount_ratio = 1.0
	if is_instance_valid(_smoke): _smoke.amount_ratio = 1.0
	_stop_fire()
	burning = false
	_flame_ignited = false
	set_physics_process(false)
	for entry in _saved:
		var part: MeshInstance3D = entry[0]
		if not is_instance_valid(part): continue
		if entry[1] < 0: part.material_override = entry[2]
		else: part.set_surface_override_material(entry[1], entry[2])
	_saved.clear()
	wrecked = false
	_flame_ignited = false
	if is_instance_valid(vehicle.visual):
		vehicle.visual.position = Vector3.ZERO
		vehicle.visual.rotation = Vector3(0, vehicle.visual.rotation.y, 0)
	refresh()

func _key(part: Node) -> String:
	for metadata in part.get_meta_list():
		if str(metadata).ends_with("material_key"): return str(part.get_meta(metadata))
	return ""

func _surface_keys(part: Node) -> Array:
	for metadata in part.get_meta_list():
		if str(metadata).ends_with("surface_material_keys"): return Array(part.get_meta(metadata))
	return []

func _role(material: StandardMaterial3D, key: String) -> String:
	if key in ["glass"] or (material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED): return "glass"
	if key in ["headlight", "tail", "smoked_lens"] or (material != null and material.emission_enabled): return "lens"
	if key in ["rubber"]: return "rubber"
	return "body"
