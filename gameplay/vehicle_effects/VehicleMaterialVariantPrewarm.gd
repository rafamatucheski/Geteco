extends RefCounted
## Prepara sob a cortina as variantes de material de veículo que só surgem em
## jogo: sujeira de uso (VehicleUsage), desgaste/amassado e carcaça queimada
## (VehicleDamage). Os vidros da cabine mantêm os materiais originais. Cada
## combinação nova de flags do StandardMaterial3D gera uma versão
## SceneForwardMobileShaderRD; com cache frio ela compilava no primeiro desenho:
## draws de 47–68 ms (rec2/rec3 e first-draw-*, 05/10/2026; chaves 502cb30b e
## 0af590d5 = pintura suja / limpa depois de suja, 10b0b8ea = desgaste,
## f24a1c0a = vidro translúcido, 3d4ae273 = brasa da carcaça).
## Só cria cópias de material e caixas temporárias de desenho: nenhum veículo,
## RNG, população ou colisão. Cada material desenhado fica retido para o shader
## continuar no mapa do motor; o primeiro uso real com as mesmas flags o reutiliza.
const PAINT = preload("res://runtime/VehiclePaint.gd")
const USAGE = preload("res://runtime/VehicleUsage.gd")
const DAMAGE = preload("res://gameplay/vehicle_effects/VehicleDamage.gd")
const RAIN = preload("res://gameplay/vehicle_effects/VehicleRain.gd")
const GUARDS = preload("res://gameplay/emergency/EffectsPrewarm.gd")
const RESOURCES = preload("res://gameplay/vehicle_effects/VehicleEffectResources.gd")
const TIRES = preload("res://gameplay/vehicle_effects/VehicleTireEffects.gd")
const WINDSHIELD = preload("res://gameplay/vehicle_effects/VehicleWindshieldRain.gd")
const STREET = preload("res://gameplay/street_physics/StreetPhysics.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
const SPACING := .7
static var _bases: Dictionary = {}         # assinatura -> pintura base (cópia)
static var _retained: Array[StandardMaterial3D] = []
## Efeitos do veículo e da rua que nascem só no jogo (fumaça, fogo, estouro, marcas de pneu,
## chuva no para-brisa, lascas de vidro, detritos). Cada um compilava o próprio shader no
## quadro em que aparecia: vehicle.effects.powertrain 17-46 ms (10 rodadas de benchmark no
## release de 15/10, sempre ~115 s depois do início), vehicle_damage.fire até 80 ms,
## street.glass/scatter 18-19 ms. O ParticleProcessMaterial e o StandardMaterial3D só guardam o
## shader enquanto houver material vivo com as mesmas flags: estes ficam retidos.
static var _retained_effects: Array[Resource] = []
static var _drawn := false
static var last_summary: Dictionary = {}
## Formatos de vértice da frota (FormatPrewarm): as variantes acima também são desenhadas num triângulo de
## cada formato real de carro, porta recortada e acabamento; na caixa só o shader ficava pronto (22/10).
const FORMAT := preload("res://runtime/FormatPrewarm.gd")
static var _formats: Dictionary = {}
## Materiais das peças que a porta da viatura recorta (ProductionWorld._prewarm_dispatch_models): na folha
## da porta eles vão para um formato novo (posição, normal, UV, às vezes cor).
static var door_materials: Array[Material] = []

## Controle A/B de medição: HARBOR_VEHICLE_VARIANT_PREWARM=0 desliga só esta etapa.
static func enabled() -> bool:
	return OS.get_environment("HARBOR_VEHICLE_VARIANT_PREWARM") != "0" \
		and "--no-prewarm" not in OS.get_cmdline_user_args()

## Chamado com cada modelo decorado da frota já criado pelo aquecimento de
## shaders do tráfego, antes de liberá-lo. Não cria modelos extras.
static func collect(model: Node3D, archetype: String) -> void:
	if _drawn or not enabled() or model == null: return
	var paint = PAINT.new()
	paint.bind(model, archetype)
	for material in paint.materials:
		var signature := shader_signature(material)
		if not _bases.has(signature): _bases[signature] = material
	if FORMAT.enabled(): FORMAT.collect(model, _formats)

## Variantes de pintura que não são as bases (lattice ou as 9 antigas) e as carcaças, sem repetir shader.
static func _paint_variants() -> Array[StandardMaterial3D]:
	var known := {}
	for signature in _bases: known[signature] = true
	var variants: Array[StandardMaterial3D] = []
	var candidates: Array = []
	var lattice := OS.get_environment("GETECO_PAINT_LATTICE") != "0"
	for base: StandardMaterial3D in _bases.values(): candidates.append_array(_lattice(base) if lattice else _variants(base))
	candidates.append_array(DAMAGE.wreck_materials().values())
	for material: StandardMaterial3D in candidates:
		var signature := shader_signature(material)
		if known.has(signature): continue
		known[signature] = true
		variants.append(material)
	return variants

## Pares [material, formato]: pintura (bases e variantes) nos formatos de carro e de porta, efeitos do
## carro nos formatos de carro e de SurfaceTool, materiais da porta recortada e do acabamento da porta.
static func _format_pairs(variants: Array[StandardMaterial3D], effect_materials: Array[Material]) -> Array:
	var pairs: Array = []
	var seen := {}
	var car_formats: Array = _formats.keys()
	var paint_formats: Array = car_formats + [FORMAT.V | FORMAT.N | FORMAT.UV, FORMAT.V | FORMAT.N | FORMAT.UV | FORMAT.C, FORMAT.V | FORMAT.N | FORMAT.C]
	FORMAT.cross(_bases.values() + variants, paint_formats, pairs, seen)
	# Para-brisa molhado, limpador, marcas de pneu e detritos: malhas montadas no jogo a partir do vidro
	# e da lataria (formatos de carro) ou por SurfaceTool (posição, normal e cor).
	FORMAT.cross(effect_materials, car_formats + FORMAT.DOOR_FORMATS + [FORMAT.V | FORMAT.N], pairs, seen)
	FORMAT.cross(door_materials, [FORMAT.V | FORMAT.N | FORMAT.UV, FORMAT.V | FORMAT.N | FORMAT.UV | FORMAT.C], pairs, seen)
	var door := preload("res://gameplay/VehicleDoorPresentation.gd")
	FORMAT.cross([door._card_material(), door._liner_dark(), preload("res://world/city_look/CityPropKit.gd").material()], FORMAT.DOOR_FORMATS, pairs, seen)
	return pairs

## Peças escondidas (22/10, 3ª rodada): o motor compila em segundo plano o pipeline "ubershader" de toda
## superfície criada, mesmo invisível ou fora da câmera (conferido no editor: instância com visible=false
## compilou os pipelines `surface` e, ao aparecer, só especializou em segundo plano, sem nenhum `surface`
## novo). Montadas logo depois da frota, as variantes de pintura × formatos compilam nos trabalhadores do
## motor enquanto a thread principal segue com a carga, sem quadro esperando por elas; saem antes da
## cortina (`release_hidden`). GETECO_FORMAT_HIDDEN=0 volta a desenhá-las diante da câmera em `run`.
static var _hidden: Node3D
static var _hidden_pieces := 0
static func hidden_enabled() -> bool:
	return FORMAT.enabled() and OS.get_environment("GETECO_FORMAT_HIDDEN") != "0"

static func start_hidden(host: Node3D) -> void:
	if not enabled() or not hidden_enabled() or _drawn or _bases.is_empty() or is_instance_valid(_hidden): return
	if DisplayServer.get_name() == "headless" or "--no-prewarm" in OS.get_cmdline_user_args(): return
	var began := Time.get_ticks_usec()
	var variants := _paint_variants()
	var effect_materials := _effect_materials()
	_retained.append_array(variants)
	for base: StandardMaterial3D in _bases.values(): _retained.append(base)
	_retained_effects.append_array(effect_materials)
	_hidden = Node3D.new()
	_hidden.name = "VehicleFormatPrewarm"
	_hidden.visible = false
	host.add_child(_hidden)
	_hidden_pieces = FORMAT.build_grid(_hidden, _format_pairs(variants, effect_materials))
	# Carcaça queimada sumindo: os materiais da brasa nos formatos de carro, no passe alfa.
	# A brasa vai para todas as malhas do carro, inclusive insígnia da Cobra (posição, normal, cor) e
	# limpador (posição, cor): sonda de pipelines, estresse do oeste a quente (export C).
	# Desligado por padrão (GETECO_WRECK_FADE_PREWARM=1): ganho não medido limpo.
	if OS.get_environment("GETECO_WRECK_FADE_PREWARM") == "1":
		var wreck: Array = DAMAGE.wreck_materials().values()
		var opaque_pairs: Array = []
		FORMAT.cross(wreck, FORMAT.DOOR_FORMATS, opaque_pairs, {})
		_hidden_pieces += FORMAT.build_grid(_hidden, opaque_pairs)
		var wreck_pairs: Array = []
		FORMAT.cross(wreck, _formats.keys() + FORMAT.DOOR_FORMATS, wreck_pairs, {})
		_hidden_pieces += FORMAT.build_grid(_hidden, wreck_pairs, Vector3.ZERO, .5)
	print("Variantes de pintura em formato real (escondidas): ", JSON.stringify({"bases": _bases.size(), "variants": variants.size(),
		"formats": _formats.keys(), "pieces": _hidden_pieces, "door_materials": door_materials.size(), "usec": Time.get_ticks_usec() - began}))
	door_materials.clear()

static func release_hidden() -> void:
	if is_instance_valid(_hidden): _hidden.free()
	_hidden = null

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _drawn or not enabled() or DisplayServer.get_name() == "headless" or _bases.is_empty(): return
	if not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var began := Time.get_ticks_usec()
	var base_count := _bases.size()
	# Com as peças escondidas já montadas, a pintura está coberta nos formatos reais: aqui só os efeitos.
	var hidden := is_instance_valid(_hidden)
	# O ternário com `[]` sai sem tipo e o GDScript recusa a atribuição: o aquecimento dos efeitos parava aqui.
	var variants: Array[StandardMaterial3D] = []
	if not hidden: variants = _paint_variants()
	var visual := Node3D.new()
	visual.name = "VehicleMaterialVariantPrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var box := BoxMesh.new()
	box.size = Vector3.ONE * .5
	var effect_materials := _effect_materials()
	var drawn: Array[Material] = []
	drawn.append_array(variants)
	drawn.append_array(effect_materials)
	var columns := maxi(1, ceili(sqrt(float(drawn.size()))))
	for index in drawn.size():
		var part := MeshInstance3D.new()
		part.mesh = box
		part.material_override = drawn[index]
		part.position = Vector3((index % columns - (columns - 1) * .5) * SPACING, -floorf(float(index) / columns) * SPACING, 0)
		visual.add_child(part)
	var format_pieces := _hidden_pieces if hidden else 0
	if FORMAT.enabled() and not hidden: format_pieces = FORMAT.build_grid(visual, _format_pairs(variants, effect_materials), Vector3(0, 0, -1.5))
	# Rachadura do vidro (26/10): a textura é desenhada aqui e o atlas de decals já sobe com ela.
	var crack := Decal.new()
	crack.texture_albedo = preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").crack_texture()
	crack.size = Vector3(.5, .5, .5)
	visual.add_child(crack)
	var emitters := _effect_emitters()
	# Os processos ficam retidos depois que os emissores são liberados com `visual`.
	var processes: Array[Resource] = []
	for emitter in emitters: processes.append(emitter.process_material)
	for index in emitters.size():
		emitters[index].position = Vector3((index - (emitters.size() - 1) * .5) * SPACING, SPACING, 0)
		visual.add_child(emitters[index])
	host.add_child(visual)
	_position(visual, camera)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	# Peças escondidas primeiro: os trabalhadores do motor compilam em paralelo (runtime/HiddenCompile.gd).
	await preload("res://runtime/HiddenCompile.gd").prepare(visual, host.get_tree())
	RenderingServer.frame_post_draw.connect(count_draw)
	var completed := false
	for frame in MAX_WAIT_FRAMES:
		await host.get_tree().process_frame
		if not GUARDS._covered_loading(host, curtain) or not GUARDS._current_camera(host, camera): break
		if not is_instance_valid(visual) or visual.is_queued_for_deletion(): break
		_position(visual, camera)
		if draws[0] >= DRAW_FRAMES:
			completed = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw):
		RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(visual): visual.free()
	if completed:
		_retained.append_array(variants)
		# As bases vêm de modelos já liberados; sem referência o shader e os pipelines novos sairiam juntos.
		if format_pieces > 0 and not hidden:
			for base: StandardMaterial3D in _bases.values(): _retained.append(base)
		_retained_effects.append_array(effect_materials)
		_retained_effects.append_array(processes)
		_drawn = true
		_bases.clear()
	last_summary = {"bases":base_count, "glass":0, "variants":variants.size(), "effects":effect_materials.size(),
		"emitters":processes.size(), "completed":completed, "draws":draws[0], "usec":Time.get_ticks_usec()-began,
		"formats":_formats.keys(), "format_pieces":format_pieces, "hidden":hidden, "door_materials":door_materials.size()}
	if completed: door_materials.clear()
	print("Variantes de material de veículo preparadas: ", JSON.stringify(last_summary))

## Mesmas mudanças de flags de VehicleUsage.apply e VehicleDamage._stall_apply_wear;
## valores contínuos (cor, rugosidade, escala) são uniforms e não importam aqui.
static func _variants(base: StandardMaterial3D) -> Array[StandardMaterial3D]:
	var result: Array[StandardMaterial3D] = []
	var detailed := base.duplicate() as StandardMaterial3D
	detailed.detail_enabled = true
	detailed.detail_albedo = USAGE._texture(1)
	detailed.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	detailed.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	detailed.uv2_triplanar = true
	result.append(detailed)
	# Uso sujo seguido de identidade limpa: detalhe desligado, textura e triplanar ficam.
	var reset := detailed.duplicate() as StandardMaterial3D
	reset.detail_enabled = false
	result.append(reset)
	# Desgaste a partir de 40%: verniz desligado.
	var worn := detailed.duplicate() as StandardMaterial3D
	worn.clearcoat_enabled = false
	result.append(worn)
	# Estágio 2+ em pintura sem textura própria: amassado triplanar em UV1.
	if base.albedo_texture == null and base.normal_texture == null:
		var dented := worn.duplicate() as StandardMaterial3D
		dented.normal_enabled = true
		dented.normal_texture = DAMAGE._dents()
		dented.uv1_triplanar = true
		result.append(dented)
		# Chuva (VehicleRain): gotas triplanares em UV1, em pintura limpa, suja, repintada e gasta
		# (sem verniz): o amassado tira as gotas, mas o desgaste antes dele não.
		for source: StandardMaterial3D in [base, detailed, reset, worn]:
			var beaded := source.duplicate() as StandardMaterial3D
			beaded.normal_enabled = true
			beaded.normal_texture = RAIN.beads()
			beaded.uv1_triplanar = true
			result.append(beaded)
	return result

## Todas as combinações de flags que VehicleUsage (sujeira), VehicleDamage (verniz, riscos, amassado) e
## VehicleRain (gotas) alcançam juntos numa pintura (22/10, 3ª rodada). A sonda de pipelines viu no jogo
## combinações fora das 9 de `_variants`, como sujeira + gotas que o desgaste desligou (normal desligada, mas
## a textura e o triplanar UV1 ficam): no cache frio esse shader compilava num quadro de 1,16 s ao atirar
## no trânsito. Estados: detalhe (nenhum / montado e desligado / ligado) × verniz (o da base / tirado) ×
## normal (limpa / gotas ou amassado / desligada com textura). GETECO_PAINT_LATTICE=0 volta às 9.
static func _lattice(base: StandardMaterial3D) -> Array[StandardMaterial3D]:
	var result: Array[StandardMaterial3D] = []
	# Gotas e amassado só entram em pintura sem textura própria (VehicleRain.beads_ok, VehicleDamage base.dents).
	var normal_states: Array[String] = ["clean"]
	if base.albedo_texture == null and base.normal_texture == null: normal_states = ["clean", "on", "off_tex"]
	var coats: Array[bool] = [base.clearcoat_enabled]
	if base.clearcoat_enabled: coats.append(false)
	for detail in ["none", "off", "on"]:
		for coat in coats:
			for normal in normal_states:
				var material := base.duplicate() as StandardMaterial3D
				if detail != "none":
					material.detail_albedo = USAGE._texture(1)
					material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
					material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
					material.uv2_triplanar = true
					material.detail_enabled = detail == "on"
				material.clearcoat_enabled = coat
				if normal != "clean":
					material.normal_texture = RAIN.beads()
					material.uv1_triplanar = true
					material.normal_enabled = normal == "on"
				result.append(material)
	return result

## Materiais desenhados numa caixa: marcas de pneu, para-brisa molhado e limpador, detritos da rua.
static func _effect_materials() -> Array[Material]:
	var result: Array[Material] = [TIRES.mark_material()]
	for material in WINDSHIELD.warm_materials(): result.append(material)
	result.append_array(STREET.warm_materials())
	return result

## Emissores com as mesmas receitas de VehicleTireEffects/PowertrainEffects/ImpactEffects/Damage:
## processo simples e processo com rampa de cor + curva de escala (burnout, fogo e fumaça do
## motor), cada um com o quad de fumaça e com a chama procedural.
static func _effect_emitters() -> Array[GPUParticles3D]:
	var result: Array[GPUParticles3D] = []
	for ramped in [false, true]:
		for wisp in [true, false]:
			var emitter := RESOURCES.emitter("WarmVehicleEffect", 14, .5, Vector2(.3, .3), wisp)
			var process := RESOURCES.particle_process()
			if ramped:
				var ramps: Array = TIRES.burnout_ramps()
				process.color_ramp = ramps[0]
				process.scale_curve = ramps[1]
			emitter.process_material = process
			# Partículas já no primeiro desenho, mesmo com fixed_fps=30 (como EffectsPrewarm).
			emitter.preprocess = .1
			emitter.emitting = true
			result.append(emitter)
	return result

## Aproxima a MaterialKey do motor: bools/enums e presença de texturas mudam o
## código do shader; cores e floats são uniforms.
static func shader_signature(material: Material) -> String:
	var parts: PackedStringArray = [material.get_class()]
	for property in material.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE): continue
		var value: Variant = material.get(property.name)
		match typeof(value):
			TYPE_BOOL, TYPE_INT: parts.append("%s=%s" % [property.name, value])
			TYPE_OBJECT:
				if property.name != "script": parts.append("%s=%s" % [property.name, value != null])
	return "|".join(parts)

static func _position(visual: Node3D, camera: Camera3D) -> void:
	visual.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 9.0)
