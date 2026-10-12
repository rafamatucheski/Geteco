extends RefCounted

## Biblioteca central de materiais PBR compartilhados do porto.
## Garante reuso e evita duplicações de StandardMaterial3D em tempo de execução.

static var _cache: Dictionary = {}

static func get_mat(id_name: String, color: Color, metallic: float = 0.1, roughness: float = 0.7, emission_energy: float = 0.0, emission_col: Color = Color.BLACK) -> StandardMaterial3D:
	if _cache.has(id_name):
		return _cache[id_name]
	
	var m := StandardMaterial3D.new()
	m.resource_name = id_name
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color if emission_col == Color.BLACK else emission_col
		m.emission_energy_multiplier = emission_energy
	
	_cache[id_name] = m
	return m

# Textura de tinta de contêiner, em tons de cinza multiplicados pela cor do tema.
# Antes os contêineres eram cor chapada: vistos de cima na câmera do jogo liam como
# blocos de plástico (vídeo de 12/10/2026). Aqui há tinta desbotada em manchas,
# escorridos de ferrugem vindos de cima, arranhões e lascas que mostram aço cru.
# Imagem contínua (seamless) gerada uma vez e compartilhada por todos os temas.
static var _paint_texture: ImageTexture

static func _container_paint_texture() -> ImageTexture:
	if _paint_texture != null: return _paint_texture
	const SIZE := 128
	var blotch := FastNoiseLite.new()
	blotch.seed = 4417
	blotch.frequency = 0.024
	blotch.fractal_octaves = 3
	var grain := FastNoiseLite.new()
	grain.seed = 9281
	grain.frequency = 0.32
	var streak := FastNoiseLite.new()
	streak.seed = 1307
	# Esticado em y: o ruído vira fios que escorrem de cima para baixo.
	streak.frequency = 0.09
	var blotch_image := blotch.get_seamless_image(SIZE, SIZE)
	var grain_image := grain.get_seamless_image(SIZE, SIZE)
	var streak_image := streak.get_seamless_image(SIZE, SIZE)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var b := blotch_image.get_pixel(x, y).r
			var g := grain_image.get_pixel(x, y).r
			# Amostra do fio com y comprimido: colunas longas e finas.
			var s := streak_image.get_pixel((x * 3) % SIZE, int(y * 0.1667) % SIZE).r
			var value := lerpf(0.78, 1.04, b) * lerpf(0.93, 1.05, g)
			var color := Color(value, value, value)
			# Escorrido de ferrugem: tinge de marrom onde o fio é forte.
			var rust := smoothstep(0.62, 0.86, s) * smoothstep(0.35, 0.7, b)
			color = color.lerp(Color(0.62, 0.40, 0.30) * value, rust * 0.72)
			# Lascas de tinta: aço cru escuro e áspero, manchas pequenas e raras.
			var chip := smoothstep(0.80, 0.90, g * 0.7 + b * 0.45)
			color = color.lerp(Color(0.34, 0.27, 0.23), chip * 0.8)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	_paint_texture = ImageTexture.create_from_image(image)
	return _paint_texture

static func container_paint(id_name: String, color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	if _cache.has(id_name): return _cache[id_name]
	var m := get_mat(id_name, color, metallic, roughness)
	m.albedo_texture = _container_paint_texture()
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.28, 0.28, 0.28)
	return m

static func container_blue() -> StandardMaterial3D:
	return container_paint("port_container_blue", Color("#2d6c93"), 0.40, 0.55)

static func container_rust() -> StandardMaterial3D:
	return container_paint("port_container_rust", Color("#a24632"), 0.35, 0.65)

static func container_teal() -> StandardMaterial3D:
	return container_paint("port_container_teal", Color("#2f8392"), 0.40, 0.55)

static func container_amber() -> StandardMaterial3D:
	return container_paint("port_container_amber", Color("#cc9230"), 0.35, 0.60)

static func container_white() -> StandardMaterial3D:
	return container_paint("port_container_white", Color("#e0e3e6"), 0.25, 0.50)

# Faixa de marca e placas de identificação: tinta lisa, sem o desgaste do casco.
static func container_marking() -> StandardMaterial3D:
	return get_mat("port_container_marking", Color("#ece6d4"), 0.05, 0.75)

static func container_stencil() -> StandardMaterial3D:
	return get_mat("port_container_stencil", Color("#1d2326"), 0.05, 0.80)

static func container_interior() -> StandardMaterial3D:
	return get_mat("port_container_interior", Color("#423a31"), 0.05, 0.85)

static func steel_galvanized() -> StandardMaterial3D:
	return get_mat("port_steel_galvanized", Color("#838c94"), 0.75, 0.35)

static func steel_dark() -> StandardMaterial3D:
	return get_mat("port_steel_dark", Color("#212529"), 0.80, 0.40)

static func cast_iron() -> StandardMaterial3D:
	return get_mat("port_cast_iron", Color("#181b1e"), 0.60, 0.65)

static func rusty_iron() -> StandardMaterial3D:
	return get_mat("port_rusty_iron", Color("#6e473b"), 0.45, 0.80)

static func brass() -> StandardMaterial3D:
	return get_mat("port_brass", Color("#dab471"), 0.85, 0.25)

static func wood_pallet_clean() -> StandardMaterial3D:
	return get_mat("port_wood_pallet_clean", Color("#c4a482"), 0.05, 0.75)

static func wood_pallet_weathered() -> StandardMaterial3D:
	return get_mat("port_wood_pallet_weathered", Color("#6d6359"), 0.05, 0.85)

static func wood_crate() -> StandardMaterial3D:
	return get_mat("port_wood_crate", Color("#9c7a53"), 0.05, 0.80)

static func rubber_black() -> StandardMaterial3D:
	return get_mat("port_rubber_black", Color("#151719"), 0.05, 0.90)

static func marine_fender() -> StandardMaterial3D:
	return get_mat("port_marine_fender", Color("#202326"), 0.10, 0.85)

static func safety_yellow() -> StandardMaterial3D:
	return get_mat("port_safety_yellow", Color("#f1c40f"), 0.20, 0.35)

static func hazard_black() -> StandardMaterial3D:
	return get_mat("port_hazard_black", Color("#1c2024"), 0.10, 0.85)

static func safety_orange() -> StandardMaterial3D:
	return get_mat("port_safety_orange", Color("#e67e22"), 0.20, 0.40)

static func plastic_blue() -> StandardMaterial3D:
	return get_mat("port_plastic_blue", Color("#2980b9"), 0.15, 0.45)

static func plastic_grey() -> StandardMaterial3D:
	return get_mat("port_plastic_grey", Color("#5d6d7e"), 0.15, 0.45)

static func rope_hemp() -> StandardMaterial3D:
	return get_mat("port_rope_hemp", Color("#b09971"), 0.05, 0.95)

static func reflective_white() -> StandardMaterial3D:
	return get_mat("port_reflective_white", Color("#fdfefe"), 0.30, 0.20)

static func floodlight_casing() -> StandardMaterial3D:
	return get_mat("port_floodlight_casing", Color("#2c3e50"), 0.60, 0.40)

static func floodlight_emission() -> StandardMaterial3D:
	return get_mat("port_floodlight_emission", Color("#fef9e7"), 0.0, 0.1, 2.8, Color("#fff4cc"))

static func forklift_orange() -> StandardMaterial3D:
	return get_mat("port_forklift_orange", Color("#d35400"), 0.35, 0.45)

static func warning_red() -> StandardMaterial3D:
	return get_mat("port_warning_red", Color("#c0392b"), 0.25, 0.50)

static func oil_stain() -> StandardMaterial3D:
	return get_mat("port_oil_stain", Color("#0e1111"), 0.05, 0.25)
