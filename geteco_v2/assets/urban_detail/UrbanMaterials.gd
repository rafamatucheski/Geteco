extends RefCounted
class_name UrbanMaterials

## Centralized shared material palette for urban buildings and architectural props.
## Prioritizes batching, shared VRAM resources, and optimal shadow/transparency settings.

static var _cache: Dictionary = {}

static func get_mat(key: String, color: Color = Color.WHITE, roughness: float = 0.82, metallic: float = 0.0) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	_cache[key] = mat
	return mat

static func material_for_color(color: Color, roughness: float = 0.84) -> StandardMaterial3D:
	var hex := color.to_html(false)
	var key := "custom_" + hex
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	_cache[key] = mat
	return mat

# Fachada com albedo quebrado por ruído (tijolo/reboco irregular) em vez de cor
# chapada. A textura de ruído é gerada uma vez por cor e fica no cache
# compartilhado, então o custo extra por prédio é zero depois do primeiro uso.
static func textured_wall(color: Color, roughness: float = 0.86, grain: float = 0.09) -> StandardMaterial3D:
	var hex := color.to_html(false)
	var key := "textured_" + hex + "_%.2f" % grain
	if _cache.has(key):
		return _cache[key]
	# Fachada com material de construção de verdade, escolhido pela cor da V1:
	# tons de barro/tijolo viram alvenaria aparente com argamassa, tons claros
	# viram reboco, o resto vira placas de concreto. A versão anterior era ruído
	# (primeiro chiado, depois manchas soltas) e lia como mármore sujo. UV
	# triplanar em metros de MUNDO: tijolo tem o mesmo tamanho em qualquer
	# prédio, em vez de esticar com a caixa.
	var style := _wall_style(color)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = ImageTexture.create_from_image(_wall_image(color, style, hash(hex)))
	mat.roughness = roughness
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / 4.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cache[key] = mat
	return mat


static func _wall_style(color: Color) -> String:
	var warm := color.r > color.b * 1.12 and color.s > 0.18
	if warm and color.v < 0.8: return "brick"
	if color.v > 0.62: return "stucco"
	return "concrete"


## 256 px = 4 m de parede (64 px/m).
static func _wall_image(color: Color, style: String, seed_value: int) -> Image:
	var size := 256
	var image := Image.create(size, size, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	match style:
		"brick":
			# Fiada de 0,25 m (16 px), tijolo de 0,5 m (32 px), junta clara de
			# 2 px, fiadas desencontradas e cada tijolo com tom próprio.
			var mortar := color.lerp(Color("c9c1b0"), 0.7)
			for y in size:
				var course := y / 16
				var offset := 16 if course % 2 else 0
				for x in size:
					var bx := (x + offset) / 32
					var joint := y % 16 < 2 or (x + offset) % 32 < 2
					var c: Color
					if joint:
						c = mortar
					else:
						var tone := float(hash(Vector2i(bx, course) + Vector2i(seed_value % 97, 0)) % 100) / 100.0
						c = color.darkened(0.14).lerp(color.lightened(0.1), tone)
						if tone > 0.93: c = color.darkened(0.3)
					var n := noise.get_noise_2d(x, y)
					image.set_pixel(x, y, c.darkened(maxf(0.0, n) * 0.18).lerp(c, 0.85 + rng.randf() * 0.15))
		"stucco":
			for y in size:
				for x in size:
					var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
					var c := color.lerp(color.darkened(0.12), n * 0.6)
					c = c.lerp(color.lightened(0.06), rng.randf() * 0.35)
					# Friso de reboco a cada 2 m.
					if y % 128 < 2: c = color.darkened(0.2)
					image.set_pixel(x, y, c)
		_:
			# Placas de 2 m × 1,33 m com junta e marcas de fôrma (furos).
			for y in size:
				for x in size:
					var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
					var panel := Vector2i(x / 128, y / 85)
					var tone := float(hash(panel + Vector2i(seed_value % 53, 3)) % 100) / 100.0
					var c := color.darkened(0.06).lerp(color.lightened(0.06), tone)
					c = c.lerp(color.darkened(0.15), n * 0.4 + rng.randf() * 0.06)
					if x % 128 < 2 or y % 85 < 2: c = color.darkened(0.35)
					var hx := x % 128
					var hy := y % 85
					if (hx == 20 or hx == 64 or hx == 108) and (hy == 20 or hy == 64): c = color.darkened(0.4)
					image.set_pixel(x, y, c)
	image.generate_mipmaps()
	return image

static func _wall_grain_ramp(color: Color, grain: float) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, color.darkened(grain))
	gradient.add_point(0.5, color)
	gradient.set_color(1, color.lightened(grain * 0.6))
	return gradient

# --- Wall Materials ---
static func brick_red() -> StandardMaterial3D:
	return get_mat("brick_red", Color("7a463b"), 0.88)

static func brick_brown() -> StandardMaterial3D:
	return get_mat("brick_brown", Color("685447"), 0.86)

static func brick_dark() -> StandardMaterial3D:
	return get_mat("brick_dark", Color("4d342d"), 0.88)

static func brick_weathered() -> StandardMaterial3D:
	return get_mat("brick_weathered", Color("5d4840"), 0.90)

static func wall_concrete() -> StandardMaterial3D:
	return get_mat("wall_concrete", Color("8f9588"), 0.85)

static func wall_plaster() -> StandardMaterial3D:
	return get_mat("wall_plaster", Color("a8a798"), 0.86)

static func wall_cream() -> StandardMaterial3D:
	return get_mat("wall_cream", Color("d4c9a9"), 0.82)

static func wall_olive() -> StandardMaterial3D:
	return get_mat("wall_olive", Color("6e7865"), 0.84)

static func wall_slate() -> StandardMaterial3D:
	return get_mat("wall_slate", Color("4f5a60"), 0.80)

# --- Architectural Trim & Stone ---
static func trim_stone() -> StandardMaterial3D:
	return get_mat("trim_stone", Color("c8bda8"), 0.78)

static func trim_dark() -> StandardMaterial3D:
	return get_mat("trim_dark", Color("282c2e"), 0.75)

static func trim_cream() -> StandardMaterial3D:
	return get_mat("trim_cream", Color("e5dcc7"), 0.80)

static func sidewalk_stone() -> StandardMaterial3D:
	return get_mat("sidewalk_stone", Color("9da092"), 0.90)

static func stoop_stone() -> StandardMaterial3D:
	return get_mat("stoop_stone", Color("aba496"), 0.84)

# --- Roofing Materials ---
static func roof_tar() -> StandardMaterial3D:
	return get_mat("roof_tar", Color("343a3d"), 0.92)

static func roof_gravel() -> StandardMaterial3D:
	return get_mat("roof_gravel", Color("4b5052"), 0.94)

static func roof_tin() -> StandardMaterial3D:
	return get_mat("roof_tin", Color("5e6967"), 0.55, 0.40)

static func roof_tin_rusty() -> StandardMaterial3D:
	return get_mat("roof_tin_rusty", Color("63594f"), 0.78, 0.20)

static func roof_shingle() -> StandardMaterial3D:
	return get_mat("roof_shingle", Color("4a423e"), 0.88)

# --- Glass & Fenestration ---
static func glass_window() -> StandardMaterial3D:
	if _cache.has("glass_window"):
		return _cache["glass_window"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.48, 0.54, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.16
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["glass_window"] = mat
	return mat

static func glass_display() -> StandardMaterial3D:
	if _cache.has("glass_display"):
		return _cache["glass_display"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.60, 0.64, 0.40)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.12
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["glass_display"] = mat
	return mat

static func glass_warm_interior() -> StandardMaterial3D:
	if _cache.has("glass_warm"):
		return _cache["glass_warm"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.75, 0.50, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.20
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["glass_warm"] = mat
	return mat

static func window_interior_dark() -> StandardMaterial3D:
	return get_mat("window_dark", Color("1a2429"), 0.85)

# Janela "acesa" à noite: emission barato em vez de Light3D real (custo de
# draw call zero a mais, nenhuma luz dinâmica nova na cena). Duas variantes de
# calor para não ficar tudo com o mesmo tom de lâmpada.
static func glass_window_lit(warm: bool = true) -> StandardMaterial3D:
	var key := "glass_lit_warm" if warm else "glass_lit_cool"
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.80, 0.55, 0.92) if warm else Color(0.80, 0.86, 0.95, 0.92)
	mat.roughness = 0.25
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.78, 0.42) if warm else Color(0.75, 0.85, 1.0)
	mat.emission_energy_multiplier = 1.6
	_cache[key] = mat
	return mat

# --- Doors & Wood ---
static func wood_door_green() -> StandardMaterial3D:
	return get_mat("door_green", Color("2d4a3b"), 0.75)

static func wood_door_burgundy() -> StandardMaterial3D:
	return get_mat("door_burgundy", Color("542628"), 0.75)

static func wood_door_navy() -> StandardMaterial3D:
	return get_mat("door_navy", Color("26364d"), 0.75)

static func wood_door_brown() -> StandardMaterial3D:
	return get_mat("door_brown", Color("422e22"), 0.80)

static func wood_tank() -> StandardMaterial3D:
	return get_mat("wood_tank", Color("5c493b"), 0.86)

static func wood_porch() -> StandardMaterial3D:
	return get_mat("wood_porch", Color("6e5947"), 0.85)

# --- Metals ---
static func metal_iron() -> StandardMaterial3D:
	return get_mat("metal_iron", Color("202324"), 0.65, 0.60)

static func metal_dark() -> StandardMaterial3D:
	return get_mat("metal_dark", Color("1b1e20"), 0.65, 0.65)

static func metal_steel() -> StandardMaterial3D:
	return get_mat("metal_steel", Color("72797a"), 0.45, 0.75)

static func metal_brass() -> StandardMaterial3D:
	return get_mat("metal_brass", Color("cfa648"), 0.35, 0.80)

static func metal_corrugated() -> StandardMaterial3D:
	return get_mat("metal_corrugated", Color("667070"), 0.50, 0.55)

# --- Awnings & Commercial Accents ---
static func awning_teal() -> StandardMaterial3D:
	return get_mat("awning_teal", Color("3b6b69"), 0.80)

static func awning_terracotta() -> StandardMaterial3D:
	return get_mat("awning_terracotta", Color("9c563e"), 0.80)

static func awning_gold() -> StandardMaterial3D:
	return get_mat("awning_gold", Color("cfa244"), 0.78)

static func awning_cream() -> StandardMaterial3D:
	return get_mat("awning_cream", Color("ece4d0"), 0.85)

static func hazard_stripe_yellow() -> StandardMaterial3D:
	return get_mat("hazard_yellow", Color("d4a035"), 0.70)

static func hazard_stripe_black() -> StandardMaterial3D:
	return get_mat("hazard_black", Color("1e2021"), 0.80)

static func emergency_red() -> StandardMaterial3D:
	return get_mat("emergency_red", Color("b83228"), 0.65)

static func police_blue() -> StandardMaterial3D:
	return get_mat("police_blue", Color("326fa8"), 0.65)

static func police_accent() -> StandardMaterial3D:
	return get_mat("police_accent", Color("d9edf1"), 0.60)

static func terracotta_flue() -> StandardMaterial3D:
	return get_mat("terracotta_flue", Color("b86344"), 0.88)
