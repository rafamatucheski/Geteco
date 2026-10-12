extends RefCounted
class_name UrbanMaterials

## Centralized shared material palette for urban buildings and architectural props.
## Prioritizes batching, shared VRAM resources, and optimal shadow/transparency settings.

const SURFACES := preload("res://assets/urban_detail/UrbanSurfaces.gd")

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
	var wall_image := _wall_image(color, style, hash(hex))
	mat.albedo_texture = ImageTexture.create_from_image(wall_image)
	# Relevo derivado do próprio albedo: junta de tijolo/placa entra para dentro e a
	# luz rasante da manhã/tarde passa a desenhar a fachada em vez de pintá-la.
	mat.normal_enabled = true
	mat.normal_texture = SURFACES.normal_from_albedo(wall_image, 7.0 if style == "brick" else 4.0, style == "brick")
	mat.normal_scale = 1.0
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
				# Whole-number grouping/index; preserve integer truncation and precision.
				@warning_ignore("integer_division")
				var course := y / 16
				var offset := 16 if course % 2 else 0
				for x in size:
					# Whole-number grouping/index; preserve integer truncation and precision.
					@warning_ignore("integer_division")
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
					# Whole-number grouping/index; preserve integer truncation and precision.
					@warning_ignore("integer_division")
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
	return SURFACES.material("brick_red", "brick", Color("7a463b"), 0.88, 0.0, 2.0, 1.0)

static func brick_brown() -> StandardMaterial3D:
	return SURFACES.material("brick_brown", "brick", Color("685447"), 0.86, 0.0, 2.0, 1.0)

static func brick_dark() -> StandardMaterial3D:
	return SURFACES.material("brick_dark", "brick", Color("4d342d"), 0.88, 0.0, 2.0, 1.0)

static func brick_weathered() -> StandardMaterial3D:
	return SURFACES.material("brick_weathered", "brick", Color("5d4840"), 0.90, 0.0, 2.0, 1.0)

static func wall_concrete() -> StandardMaterial3D:
	return SURFACES.material("wall_concrete", "concrete", Color("8f9588"), 0.85, 0.0, 2.0, 1.0)

static func wall_plaster() -> StandardMaterial3D:
	return SURFACES.material("wall_plaster", "plaster", Color("a8a798"), 0.86, 0.0, 3.0, 0.8)

static func wall_cream() -> StandardMaterial3D:
	return SURFACES.material("wall_cream", "plaster", Color("d4c9a9"), 0.82, 0.0, 3.0, 0.8)

static func wall_olive() -> StandardMaterial3D:
	return SURFACES.material("wall_olive", "plaster", Color("6e7865"), 0.84, 0.0, 3.0, 0.8)

static func wall_slate() -> StandardMaterial3D:
	return SURFACES.material("wall_slate", "concrete", Color("4f5a60"), 0.80, 0.0, 2.0, 1.0)

# --- Architectural Trim & Stone ---
static func trim_stone() -> StandardMaterial3D:
	return SURFACES.material("trim_stone", "granite", Color("c8bda8"), 0.78, 0.0, 2.0, 1.0)

static func trim_dark() -> StandardMaterial3D:
	return SURFACES.material("trim_dark", "concrete", Color("282c2e"), 0.75, 0.0, 2.0, 1.0)

static func trim_cream() -> StandardMaterial3D:
	return SURFACES.material("trim_cream", "plaster", Color("e5dcc7"), 0.80, 0.0, 3.0, 0.8)

static func sidewalk_stone() -> StandardMaterial3D:
	return SURFACES.material("sidewalk_stone", "paving", Color("9da092"), 0.90, 0.0, 2.0, 1.0)

static func stoop_stone() -> StandardMaterial3D:
	return SURFACES.material("stoop_stone", "paving", Color("aba496"), 0.84, 0.0, 2.0, 1.0)

# --- Roofing Materials ---
static func roof_tar() -> StandardMaterial3D:
	return SURFACES.material("roof_tar", "tar", Color("343a3d"), 0.92, 0.0, 2.0, 1.0)

static func roof_gravel() -> StandardMaterial3D:
	return SURFACES.material("roof_gravel", "gravel", Color("4b5052"), 0.94, 0.0, 1.0, 1.0)

static func roof_tin() -> StandardMaterial3D:
	return SURFACES.material("roof_tin", "corrugated", Color("5e6967"), 0.55, 0.40, 1.28, 1.0)

static func roof_tin_rusty() -> StandardMaterial3D:
	return SURFACES.material("roof_tin_rusty", "corrugated", Color("63594f"), 0.78, 0.20, 1.28, 1.2)

static func roof_shingle() -> StandardMaterial3D:
	return SURFACES.material("roof_shingle", "shingle", Color("4a423e"), 0.88, 0.0, 1.5, 1.0)

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

# Mesmo material noturno das fachadas individuais: as janelas em MultiMesh
# também acompanham o relógio, inclusive quando o chunk é carregado de dia.
static func glass_window_lit(warm: bool = true) -> StandardMaterial3D:
	return preload("res://world/city_look/CityLookMaterials.gd").window_lit(0 if warm else 2)

# --- Doors & Wood ---
static func wood_door_green() -> StandardMaterial3D:
	return SURFACES.material("door_green", "wood", Color("2d4a3b"), 0.75, 0.0, 1.0, 1.0)

static func wood_door_burgundy() -> StandardMaterial3D:
	return SURFACES.material("door_burgundy", "wood", Color("542628"), 0.75, 0.0, 1.0, 1.0)

static func wood_door_navy() -> StandardMaterial3D:
	return SURFACES.material("door_navy", "wood", Color("26364d"), 0.75, 0.0, 1.0, 1.0)

static func wood_door_brown() -> StandardMaterial3D:
	return SURFACES.material("door_brown", "wood", Color("422e22"), 0.80, 0.0, 1.0, 1.0)

static func wood_tank() -> StandardMaterial3D:
	return SURFACES.material("wood_tank", "wood", Color("5c493b"), 0.86, 0.0, 1.0, 1.0)

static func wood_porch() -> StandardMaterial3D:
	return SURFACES.material("wood_porch", "wood", Color("6e5947"), 0.85, 0.0, 1.0, 1.0)

# --- Metals ---
static func metal_iron() -> StandardMaterial3D:
	return SURFACES.material("metal_iron", "metal", Color("202324"), 0.65, 0.60, 1.0, 1.0)

static func metal_dark() -> StandardMaterial3D:
	return SURFACES.material("metal_dark", "metal", Color("1b1e20"), 0.65, 0.65, 1.0, 1.0)

static func metal_steel() -> StandardMaterial3D:
	return SURFACES.material("metal_steel", "metal", Color("72797a"), 0.45, 0.75, 1.0, 1.0)

static func metal_brass() -> StandardMaterial3D:
	return SURFACES.material("metal_brass", "metal", Color("cfa648"), 0.35, 0.80, 1.0, 1.0)

static func metal_corrugated() -> StandardMaterial3D:
	return SURFACES.material("metal_corrugated", "corrugated", Color("667070"), 0.50, 0.55, 1.28, 0.8)

# --- Awnings & Commercial Accents ---
static func awning_teal() -> StandardMaterial3D:
	return SURFACES.material("awning_teal", "fabric", Color("3b6b69"), 0.80, 0.0, 0.5, 1.0)

static func awning_terracotta() -> StandardMaterial3D:
	return SURFACES.material("awning_terracotta", "fabric", Color("9c563e"), 0.80, 0.0, 0.5, 1.0)

static func awning_gold() -> StandardMaterial3D:
	return SURFACES.material("awning_gold", "fabric", Color("cfa244"), 0.78, 0.0, 0.5, 1.0)

static func awning_cream() -> StandardMaterial3D:
	return SURFACES.material("awning_cream", "fabric", Color("ece4d0"), 0.85, 0.0, 0.5, 1.0)

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
