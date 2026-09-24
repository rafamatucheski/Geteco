extends RefCounted
## Materiais compartilhados do visual urbano (noite, chão, telhado, marcas).
##
## Tudo que acende à noite usa UM material compartilhado por tipo, e o
## CityLook.gd só reescreve a energia desses poucos materiais quando a hora
## muda. Assim centenas de janelas e postes acendem sem Light3D nova (o
## renderizador Mobile não aguenta dezenas de luzes dinâmicas por tela) e sem
## varrer a cena a cada quadro.

static var _cache := {}
static var night := 0.0

# Cores de referência. Os postes eram sódio puro (1, .62, .26): somado às
# janelas âmbar, à vitrine âmbar e ao LUT creme, a noite inteira virava um
# laranja chapado. Agora o poste é branco-quente (~3500 K, LED/vapor metálico),
# as janelas misturam âmbar, branco neutro e azul-TV, e a vitrine é neutra —
# o contraste quente/frio é o que dá leitura de cidade à noite.
const SODIUM := Color(1.0, 0.86, 0.66)
const WINDOW_TONES := [Color(1.0, 0.8, 0.55), Color(0.96, 0.94, 0.88), Color(0.62, 0.78, 1.0)]
const SHOP_TONE := Color(0.98, 0.93, 0.84)
## Janelas apagadas com cortina/persiana: bege, vinho, azul-marinho, persiana clara.
const UNLIT_VARIANTS := 4
const UNLIT_TONES := [Color("8a7a60"), Color("5a2a2e"), Color("27344a"), Color("a9a89c")]


static func set_night(value: float) -> void:
	night = clampf(value, 0.0, 1.0)
	for index in WINDOW_TONES.size():
		var window := window_lit(index)
		window.emission_energy_multiplier = lerpf(0.0, 1.8, night)
	shop_glass().emission_energy_multiplier = lerpf(0.05, 1.25, night)
	lamp_head().emission_energy_multiplier = lerpf(0.0, 5.0, night)
	# Additivo: cor zero some sem custo visual; a visibilidade do nó é
	# desligada pelo CityLook durante o dia para economizar o draw.
	# A cor está na textura (núcleo branco, borda quente); aqui só a energia.
	# Era 1,25: em asfalto claro estourava e virava disco sólido.
	light_pool().albedo_color = Color(1, 1, 1) * (0.85 * night)
	neon_materials_set(night)


static func window_lit(index: int) -> StandardMaterial3D:
	var key := "window_lit_%d" % index
	if _cache.has(key): return _cache[key]
	var material := StandardMaterial3D.new()
	# De dia a janela "acesa" precisa ler como vidro comum, não como amarelo.
	material.albedo_color = Color(0.30, 0.42, 0.48)
	material.roughness = 0.2
	material.metallic_specular = 0.7
	material.emission_enabled = true
	material.emission = WINDOW_TONES[index]
	material.emission_energy_multiplier = 0.0
	_cache[key] = material
	return material


static func shop_glass() -> StandardMaterial3D:
	if _cache.has("shop_glass"): return _cache["shop_glass"]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.40, 0.56, 0.60)
	material.roughness = 0.12
	material.metallic_specular = 0.8
	material.emission_enabled = true
	material.emission = SHOP_TONE
	material.emission_energy_multiplier = 0.05
	_cache["shop_glass"] = material
	return material


static func lamp_head() -> StandardMaterial3D:
	if _cache.has("lamp_head"): return _cache["lamp_head"]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("e4d6b0")
	material.emission_enabled = true
	material.emission = SODIUM
	material.emission_energy_multiplier = 0.0
	_cache["lamp_head"] = material
	return material


## Mancha de luz no chão embaixo do poste: quad aditivo com gradiente radial.
static func light_pool() -> StandardMaterial3D:
	if _cache.has("light_pool"): return _cache["light_pool"]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.no_depth_test = false
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Gradiente colorido em vez de cinza: núcleo quase branco logo abaixo da
	# lâmpada, anel quente e borda longa que morre suave. Uma cor só em todo o
	# disco lia como adesivo laranja no chão.
	material.albedo_texture = radial_texture("pool_v2", [
		Color(1.0, 0.97, 0.9, 1), Color(0.78, 0.7, 0.56, 1), Color(0.34, 0.27, 0.18, 1),
		Color(0.1, 0.075, 0.05, 1), Color(0, 0, 0, 1)], [0.0, 0.18, 0.45, 0.72, 1.0])
	material.albedo_color = Color.BLACK
	material.disable_receive_shadows = true
	_cache["light_pool"] = material
	return material


static func radial_texture(key: String, colors: Array, offsets: Array, size := 128) -> GradientTexture2D:
	var cache_key := "radial_" + key
	if _cache.has(cache_key): return _cache[cache_key]
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colors)
	gradient.offsets = PackedFloat32Array(offsets)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	_cache[cache_key] = texture
	return texture


## Lente do semáforo amarelo piscante. O CityLook alterna a energia (1 Hz).
static func signal_amber() -> StandardMaterial3D:
	if _cache.has("signal_amber"): return _cache["signal_amber"]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.24, 0.05)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.66, 0.1)
	material.emission_energy_multiplier = 0.0
	_cache["signal_amber"] = material
	return material


static func set_signal_phase(on: bool) -> void:
	signal_amber().emission_energy_multiplier = lerpf(1.6, 4.0, night) if on else 0.0


static func window_unlit(index: int) -> StandardMaterial3D:
	var key := "window_unlit_%d" % index
	if _cache.has(key): return _cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = UNLIT_TONES[index % UNLIT_TONES.size()]
	material.roughness = 0.45
	material.metallic_specular = 0.6
	if index == 3:
		# Persiana: listras horizontais finas.
		material.albedo_texture = _blinds_texture()
	_cache[key] = material
	return material


static func _blinds_texture() -> ImageTexture:
	if _cache.has("blinds_tex"): return _cache["blinds_tex"]
	var image := Image.create(8, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 8:
			image.set_pixel(x, y, Color(1, 1, 1) if y % 4 != 0 else Color(0.55, 0.55, 0.55))
	var texture := ImageTexture.create_from_image(image)
	_cache["blinds_tex"] = texture
	return texture


## Janela de TV: cor e energia trocadas pelo CityLook (tremulação à noite).
static func window_tv() -> StandardMaterial3D:
	if _cache.has("window_tv"): return _cache["window_tv"]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.3, 0.4)
	material.roughness = 0.2
	material.emission_enabled = true
	material.emission = Color(0.45, 0.6, 1.0)
	material.emission_energy_multiplier = 0.0
	_cache["window_tv"] = material
	return material


static func flicker_tv(rng: RandomNumberGenerator) -> void:
	var material := window_tv()
	if night < 0.05:
		material.emission_energy_multiplier = 0.0
		return
	var tones := [Color(0.45, 0.6, 1.0), Color(0.7, 0.8, 1.0), Color(0.35, 0.45, 0.9), Color(0.9, 0.85, 1.0)]
	material.emission = tones[rng.randi() % tones.size()]
	material.emission_energy_multiplier = night * rng.randf_range(0.9, 2.2)


## Balizamento vermelho de prédio alto: pisca com CityLook, forte à noite.
static func beacon() -> StandardMaterial3D:
	if _cache.has("beacon"): return _cache["beacon"]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.05, 0.04)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.08, 0.05)
	material.emission_energy_multiplier = 0.0
	_cache["beacon"] = material
	return material


static func set_beacon_phase(on: bool) -> void:
	beacon().emission_energy_multiplier = lerpf(1.2, 6.0, night) if on else 0.05


## Delegacia: letreiro, lampiões, neon, giroflex e luzes do heliponto.
const POLICE_TONES := {"lightbox": Color(0.95, 0.97, 1.0), "globe": Color(0.35, 0.55, 1.0), "neon": Color(0.2, 0.45, 1.0), "red": Color(1.0, 0.12, 0.1), "blue": Color(0.15, 0.35, 1.0), "pad": Color(0.4, 1.0, 0.45)}

static func police(kind: String) -> StandardMaterial3D:
	var key := "police_" + kind
	if _cache.has(key): return _cache[key]
	var tone: Color = POLICE_TONES.get(kind, Color.WHITE)
	var material := StandardMaterial3D.new()
	material.albedo_color = tone.lerp(Color.WHITE, 0.55) if kind == "lightbox" else tone.darkened(0.35)
	material.emission_enabled = true
	material.emission = tone
	material.emission_energy_multiplier = 0.5
	_cache[key] = material
	return material


## Chamado pelo CityLook: luz fixa segue a noite; giroflex alterna vermelho/azul.
static func set_police_phase(phase: bool) -> void:
	police("lightbox").emission_energy_multiplier = lerpf(0.35, 1.0, night)
	police("globe").emission_energy_multiplier = lerpf(0.4, 3.0, night)
	police("neon").emission_energy_multiplier = lerpf(0.3, 3.0, night)
	police("pad").emission_energy_multiplier = lerpf(0.0, 2.5, night) if phase else lerpf(0.0, 0.6, night)
	var strobe := lerpf(2.0, 6.0, night)
	police("red").emission_energy_multiplier = strobe if phase else 0.05
	police("blue").emission_energy_multiplier = 0.05 if phase else strobe


## Escurecimento na base da parede (oclusão falsa): preto no chão sumindo em 1,3 m.
static func wall_ao() -> StandardMaterial3D:
	if _cache.has("wall_ao"): return _cache["wall_ao"]
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.12), Color(0, 0, 0, 0.55)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_texture = texture
	material.albedo_color = Color(0.02, 0.025, 0.035, 1)
	_cache["wall_ao"] = material
	return material


# --- Neon (letreiros e outdoors) ---

static func neon(color: Color) -> StandardMaterial3D:
	var key := "neon_" + color.to_html(false)
	if _cache.has(key): return _cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.25)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.4
	_cache[key] = material
	var list: Array = _cache.get("neon_list", [])
	list.append(material)
	_cache["neon_list"] = list
	return material


static func neon_materials_set(value: float) -> void:
	for material in _cache.get("neon_list", []):
		material.emission_energy_multiplier = lerpf(0.4, 3.2, value)
	for material in _cache.get("panel_list", []):
		material.emission_energy_multiplier = lerpf(0.12, 0.75, value)


## Fundo de outdoor: iluminado por refletor, não é neon. Energia baixa para o
## texto continuar legível e o glow não engolir o painel à noite.
static func billboard(color: Color) -> StandardMaterial3D:
	var key := "panel_" + color.to_html(false)
	if _cache.has(key): return _cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.12
	_cache[key] = material
	var list: Array = _cache.get("panel_list", [])
	list.append(material)
	_cache["panel_list"] = list
	return material


# --- Superfícies opacas simples ---

static func flat(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var key := "flat_%s_%.2f" % [color.to_html(true), roughness]
	if _cache.has(key): return _cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	_cache[key] = material
	return material


## Decal de chão (mancha, remendo, sombra de contato): cor escura com alfa
## vindo da textura. Escurece qualquer tom de asfalto/calçada sem precisar de
## uma textura por superfície. É sombreado (recebe sol e sombra) para não
## "brilhar" à noite como um adesivo por cima do chão.
static func ground_decal(key: String, texture: Texture2D, tint: Color) -> StandardMaterial3D:
	var cache_key := "ground_" + key
	if _cache.has(cache_key): return _cache[cache_key]
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_texture = texture
	material.albedo_color = tint
	material.roughness = 0.95
	material.render_priority = -1
	_cache[cache_key] = material
	return material


## Textura radial em tons de alfa (preto opaco no centro, transparente na borda).
static func alpha_blob(key: String, falloff := 0.0, size := 64) -> GradientTexture2D:
	return radial_texture("blob_%s" % key, [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, falloff, 1.0], size)
