extends RefCounted
class_name PaintedWindow

## Janela "pintada" no estilo do GTA III/Vice City: em vez de 5 a 9 caixas por
## janela (moldura, vidro transparente, montantes, verga), um único quad opaco
## com moldura de pedra, caixilho, recuo sombreado, cortina e reflexo do céu já
## desenhados na textura. Os materiais são compartilhados pela cidade inteira
## (chave = tamanho, divisão do caixilho, cortina, acesa), então a fusão por
## trecho junta todas as janelas iguais numa malha só.
##
## Interruptor: GETECO_PAINTED_WINDOWS=0 volta às janelas em caixas (A/B).

const SURFACES := preload("res://assets/urban_detail/UrbanSurfaces.gd")
const PX_PER_M := 100.0
## Moldura de pedra em volta do vão (m): laterais e verga. A base fica para o
## peitoril 3D, que continua em caixa para manter silhueta e sombra real.
const SIDE := 0.14
const LINTEL := 0.24
const BOTTOM := 0.04
const CURTAINS := [Color("8a7a60"), Color("6b2d31"), Color("2c3a52"), Color("b7b2a2"), Color("3f5a43")]
const SASH_TONES := [Color("e6e0d0"), Color("2f3b34"), Color("e6e0d0"), Color("5a2b2b")]

static var _cache := {}
static var _lit_materials: Array[StandardMaterial3D] = []
static var _night := 0.0


static func enabled() -> bool:
	return OS.get_environment("GETECO_PAINTED_WINDOWS") != "0"


## Tamanho do quad (moldura incluída) para um vão de win_w × win_h.
static func quad_size(win_w: float, win_h: float) -> Vector2:
	return Vector2(win_w + SIDE * 2.0, win_h + LINTEL + BOTTOM)


## Deslocamento vertical do centro do quad em relação ao centro do vão.
static func quad_center_offset_y() -> float:
	return (LINTEL - BOTTOM) * 0.5


static func material(win_w: float, win_h: float, panes: int, curtain: int, sash: int, lit: bool) -> StandardMaterial3D:
	var key := "%.2f_%.2f_%d_%d_%d_%s" % [win_w, win_h, panes, curtain, sash, lit]
	if _cache.has(key): return _cache[key]
	var images := _paint(win_w, win_h, panes, curtain % CURTAINS.size(), sash % SASH_TONES.size())
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(images.albedo)
	mat.normal_enabled = true
	mat.normal_texture = SURFACES.normal_from_albedo(images.albedo, 3.0)
	mat.roughness_texture = ImageTexture.create_from_image(images.rough)
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.metallic_specular = 0.7
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Sem meta "city_window": CityChunkDressing._treat_window trocaria a textura
	# pintada por vidro liso. A noite desta janela já está na própria textura.
	if lit:
		mat.emission_enabled = true
		mat.emission_texture = ImageTexture.create_from_image(images.glow)
		# Operador ADD soma a cor à textura: branco aqui estourava o quad inteiro.
		mat.emission = Color.BLACK
		mat.emission_energy_multiplier = lerpf(0.0, 1.8, _night)
		_lit_materials.append(mat)
	_cache[key] = mat
	return mat


## Acompanha o relógio junto com as janelas acesas de CityLookMaterials.
static func set_night(value: float) -> void:
	_night = clampf(value, 0.0, 1.0)
	for mat in _lit_materials: mat.emission_energy_multiplier = lerpf(0.0, 1.8, _night)


static func all_materials() -> Array:
	return _cache.values()


static func _paint(win_w: float, win_h: float, panes: int, curtain: int, sash: int) -> Dictionary:
	var size := quad_size(win_w, win_h)
	var w := int(round(size.x * PX_PER_M))
	var h := int(round(size.y * PX_PER_M))
	var albedo := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rough := Image.create(w, h, false, Image.FORMAT_L8)
	var glow := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([win_w, win_h, panes, curtain, sash])
	var noise := FastNoiseLite.new()
	noise.seed = rng.seed
	noise.frequency = 0.08
	var stone := Color("c8bda8")
	var sash_color: Color = SASH_TONES[sash]
	var curtain_color: Color = CURTAINS[curtain]
	var glow_color := Color(1.0, 0.78, 0.5) if curtain % 2 == 0 else Color(0.98, 0.9, 0.74)
	# Vão (em px, origem no canto superior esquerdo da imagem).
	var side := int(SIDE * PX_PER_M)
	var top := int(LINTEL * PX_PER_M)
	var ox0 := side
	var ox1 := w - side
	var oy0 := top
	var oy1 := h - int(BOTTOM * PX_PER_M)
	var frame := 7
	# Cortina: lado e altura sorteados por variante; parte do vidro fica livre.
	var curtain_left := curtain % 2 == 0
	var curtain_cover := 0.28 + 0.12 * float(curtain % 3)
	var blind_drop := 0.12 + 0.1 * float((curtain + 1) % 3)
	var keystone_half := 9
	var mid_x := w >> 1
	for y in h:
		for x in w:
			var c: Color
			var r := 0.85
			var g := Color.BLACK
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var in_opening := x >= ox0 and x < ox1 and y >= oy0 and y < oy1
			if not in_opening:
				# Moldura de pedra com bisel: luz em cima/esquerda, sombra embaixo/direita.
				c = stone.darkened(0.08).lerp(stone.lightened(0.05), n)
				if y < top:
					# Verga com aduelas e pedra-chave central saliente.
					if (x + 4) % 22 < 2: c = c.darkened(0.22)
					if absi(x - mid_x) < keystone_half: c = stone.lightened(0.08).lerp(stone, n)
					if absi(x - mid_x) == keystone_half: c = c.darkened(0.3)
					if y < 3: c = c.lightened(0.18)
					if y > top - 4: c = c.darkened(0.25)
				if x < 3: c = c.lightened(0.12)
				if x > w - 4: c = c.darkened(0.22)
				if y > h - 3: c = c.darkened(0.2)
				# Escorrido de sujeira sob as quinas da verga.
				if y > top and (absi(x - ox0) < 3 or absi(x - ox1) < 3): c = c.darkened(0.18 * (1.0 - float(y - top) / float(h - top)))
				r = 0.8
			else:
				var lx := x - ox0
				var ly := y - oy0
				var ow := ox1 - ox0
				var oh := oy1 - oy0
				var on_frame := lx < frame or lx >= ow - frame or ly < frame or ly >= oh - frame
				var on_mullion := false
				if panes in [2, 4, 6] and absi(ly - (oh >> 1)) < 2: on_mullion = true
				if panes in [4, 6] and absi(lx - (ow >> 1)) < 2: on_mullion = true
				if panes == 6 and (absi(lx - int(ow * 0.28)) < 2 or absi(lx - int(ow * 0.72)) < 2): on_mullion = true
				# Barra do meio da janela guilhotina (folha de baixo mais saliente).
				if absi(ly - (oh >> 1)) < 4 and panes != 1: on_mullion = true
				if on_frame or on_mullion:
					c = sash_color.darkened(0.06 * n)
					if on_frame and ly < frame: c = c.darkened(0.35)
					if on_frame and lx < frame: c = c.darkened(0.15)
					r = 0.55
				else:
					# Vidro: reflexo do céu em degradê, faixa diagonal clara e,
					# atrás, cortina lateral + persiana no alto + sala escura.
					var u := float(lx) / float(ow)
					var v := float(ly) / float(oh)
					var room := Color("1d252b").lerp(Color("2c3a40"), v)
					var behind := room
					var covered := (u < curtain_cover) if curtain_left else (u > 1.0 - curtain_cover)
					var folds := 0.85 + 0.15 * sin(u * 70.0)
					if covered: behind = curtain_color.darkened(0.1) * folds
					if v < blind_drop: behind = Color("b9b3a3").darkened(0.3 + (0.15 if ly % 4 == 0 else 0.0))
					var sky := Color("8fa8b4").lerp(Color("4d6470"), v)
					var fresnel := 0.16 + 0.2 * (1.0 - v)
					if absf(u + v * 0.6 - 0.75) < 0.05: fresnel += 0.12
					c = behind.lerp(sky, fresnel)
					# Sombra do recuo: verga e ombreira esquerda projetam no vidro.
					var shade := 0.0
					if ly < 26: shade = maxf(shade, 0.45 * (1.0 - float(ly) / 26.0))
					if lx < 14: shade = maxf(shade, 0.3 * (1.0 - float(lx) / 14.0))
					c = c.darkened(shade)
					r = 0.08
					# À noite: luz da sala atravessando cortina (mais fraca) e vidro.
					var glow_k := 0.35 if covered else (0.15 if v < blind_drop else 1.0)
					g = glow_color * glow_k * (0.75 + 0.25 * v)
			albedo.set_pixel(x, y, c)
			rough.set_pixel(x, y, Color(r, r, r))
			glow.set_pixel(x, y, g)
	albedo.generate_mipmaps()
	rough.generate_mipmaps()
	glow.generate_mipmaps()
	return {"albedo": albedo, "rough": rough, "glow": glow}
