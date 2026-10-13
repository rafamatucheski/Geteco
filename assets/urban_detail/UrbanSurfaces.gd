extends RefCounted
class_name UrbanSurfaces
@warning_ignore_start("integer_division")

## Superfícies procedurais (albedo + normal + rugosidade) para a cidade: tijolo, calçada,
## meio-fio, telhados, madeira, metal, tecido e folhagem. Antes quase tudo isso era
## `albedo_color` chapado e lia como plástico. A textura é NEUTRA (cinza claro) e a cor
## do material a tinge, então um conjunto de mapas por tipo serve todas as cores. UV
## triplanar em metros de MUNDO: o tijolo tem o mesmo tamanho em qualquer prédio.

const SIZE := 256

static var _maps: Dictionary = {}
static var _materials: Dictionary = {}


## Material texturizado e cacheado. `color` é a cor desejada vista de longe: o albedo é
## dividido pela luminância média da textura para a paleta antiga não escurecer.
static func material(key: String, kind: String, color: Color, roughness := 0.85, metallic := 0.0, tile := 2.0, bump := 1.0) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var maps := _maps_for(kind)
	var mat := StandardMaterial3D.new()
	var gain := 1.0 / maxf(float(maps["mean"]), 0.2)
	mat.albedo_color = Color(minf(color.r * gain, 1.0), minf(color.g * gain, 1.0), minf(color.b * gain, 1.0), color.a)
	mat.albedo_texture = maps["albedo"]
	mat.normal_enabled = true
	mat.normal_texture = maps["normal"]
	mat.normal_scale = bump
	mat.roughness = roughness
	mat.roughness_texture = maps["rough"]
	mat.metallic = metallic
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / tile
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_materials[key] = mat
	return mat


## Aplica relevo + rugosidade + textura a um material que já existe (MultiMesh com cor por
## instância): o albedo neutro multiplica a cor do vértice, então compensa a luminância média.
static func detail(mat: StandardMaterial3D, kind: String, tile := 2.0, bump := 1.0) -> StandardMaterial3D:
	var maps := _maps_for(kind)
	var gain := 1.0 / maxf(float(maps["mean"]), 0.2)
	mat.albedo_texture = maps["albedo"]
	mat.albedo_color = Color(gain, gain, gain)
	mat.normal_enabled = true
	mat.normal_texture = maps["normal"]
	mat.normal_scale = bump
	mat.roughness_texture = maps["rough"]
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / tile
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat


## Normal map a partir de uma altura (com repetição nas bordas, para não marcar emenda).
static func normal_from_height(height: PackedFloat32Array, size: int, strength: float) -> ImageTexture:
	var image := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var gx := height[y * size + (x + 1) % size] - height[y * size + (x - 1 + size) % size]
			var gy := height[((y + 1) % size) * size + x] - height[((y - 1 + size) % size) * size + x]
			var n := Vector3(-gx * strength, gy * strength, 1.0).normalized()
			image.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Altura = luminância do albedo (mortar/juntas escuras entram para dentro; `invert` p/ tijolo).
static func normal_from_albedo(albedo: Image, strength: float, invert := false) -> ImageTexture:
	var size := albedo.get_width()
	var height := PackedFloat32Array()
	height.resize(size * size)
	for y in size:
		for x in size:
			var l := albedo.get_pixel(x, y).get_luminance()
			height[y * size + x] = (1.0 - l) if invert else l
	return normal_from_height(height, size, strength)


static func _maps_for(kind: String) -> Dictionary:
	if _maps.has(kind):
		return _maps[kind]
	var seed_value := hash(kind)
	var coarse := _noise(seed_value, 0.012)
	var medium := _noise(seed_value + 1, 0.045)
	var fine := _noise(seed_value + 2, 0.22)
	var albedo := Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
	var rough := Image.create(SIZE, SIZE, true, Image.FORMAT_L8)
	var height := PackedFloat32Array()
	height.resize(SIZE * SIZE)
	var total := 0.0
	for y in SIZE:
		for x in SIZE:
			var n := Vector3(coarse.get_pixel(x, y).r, medium.get_pixel(x, y).r, fine.get_pixel(x, y).r)
			var px := _pixel(kind, x, y, n, seed_value, coarse, medium)
			var c: Color = px[0]
			albedo.set_pixel(x, y, c)
			height[y * SIZE + x] = px[1]
			total += c.get_luminance()
	var mean := total / float(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var l := albedo.get_pixel(x, y).get_luminance()
			rough.set_pixel(x, y, Color(clampf(0.92 + (mean - l) * 0.9, 0.62, 1.0), 0, 0))
	albedo.generate_mipmaps()
	rough.generate_mipmaps()
	var result := {
		"albedo": ImageTexture.create_from_image(albedo),
		"normal": normal_from_height(height, SIZE, _bump_for(kind)),
		"rough": ImageTexture.create_from_image(rough),
		"mean": mean,
	}
	_maps[kind] = result
	return result


static func _bump_for(kind: String) -> float:
	match kind:
		"brick", "paving", "shingle": return 5.0
		"corrugated": return 4.0
		"gravel": return 6.0
		"metal", "fabric": return 1.6
		"snow": return 2.0
		_: return 3.0


static func _noise(seed_value: int, frequency: float) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	return noise.get_seamless_image(SIZE, SIZE)


static func _hash01(a: int, b: int, salt: int) -> float:
	return float(hash(Vector3i(a, b, salt)) % 1000) / 999.0


## Devolve [cor neutra, altura] de um pixel. `n` = (grosso, médio, fino) em 0..1.
static func _pixel(kind: String, x: int, y: int, n: Vector3, seed_value: int, coarse: Image, medium: Image) -> Array:
	var stain := n.x
	match kind:
		"brick":
			# Fiada de 16 px (12,5 cm), tijolo de 32 px (25 cm), tile de 2 m.
			var course := y / 16
			var off := 16 if course % 2 else 0
			var bx := (x + off) / 32
			var lx := (x + off) % 32
			var ly := y % 16
			if ly < 2 or lx < 2:
				var m := 0.97 - stain * 0.1 - n.z * 0.05
				return [Color(m, m, m * 0.97), 0.28]
			var tone := _hash01(bx, course, 3)
			var v := 0.6 + tone * 0.32 - stain * 0.12 + (n.z - 0.5) * 0.16
			if tone > 0.94: v -= 0.18
			var edge := minf(minf(float(lx - 2), float(31 - lx)), minf(float(ly - 2), float(15 - ly)))
			var chip := 1.0 if edge > 1.0 else 0.75 + edge * 0.2
			return [Color(v, v * (0.97 + tone * 0.04), v * (0.95 + tone * 0.06)), chip * (0.85 + n.z * 0.15)]
		"paving":
			# Lajes de 1 m (128 px) com junta, rachadura em parte delas e manchas de uso.
			var sx := x / 128
			var sy := y / 128
			var lx := x % 128
			var ly := y % 128
			if lx < 3 or ly < 3:
				return [Color(0.5, 0.5, 0.48), 0.2]
			var tone := _hash01(sx, sy, 5)
			var v := 0.78 + tone * 0.14 - stain * 0.12 + (n.z - 0.5) * 0.16
			if n.y > 0.72: v -= (n.y - 0.72) * 0.7
			var h := 0.8 + n.y * 0.1
			if int(tone * 1000.0) % 4 == 0:
				var crack := absf(float(lx) - float(ly) * 0.4 - 24.0 * tone - (n.y - 0.5) * 20.0)
				if crack < 1.4:
					v -= 0.3
					h -= 0.35
			return [Color(v, v, v * 0.98), h]
		"granite":
			var speck := n.z
			var v := 0.74 + stain * 0.18 + (speck - 0.5) * 0.36
			if _hash01(x, y, 9) > 0.965: v -= 0.25
			elif _hash01(x, y, 10) > 0.975: v += 0.12
			var joint := x % 128 < 2
			if joint: v = 0.4
			return [Color(v, v, v * 0.98), 0.3 if joint else 0.8 + n.z * 0.1]
		"concrete":
			var v := 0.8 + (stain - 0.5) * 0.3 + (n.y - 0.5) * 0.16 + (n.z - 0.5) * 0.12
			var pore := _hash01(x, y, 12) > 0.985
			if pore: v -= 0.3
			var joint := x % 128 < 2 or y % 128 < 2
			if joint: v -= 0.28
			# Escorrido vertical de umidade.
			var streak: float = coarse.get_pixel((x * 5) % SIZE, (y / 6) % SIZE).r
			if streak > 0.66: v -= (streak - 0.66) * 0.3
			return [Color(v, v, v), 0.35 if joint else (0.55 if pore else 0.8 + n.z * 0.1)]
		"plaster":
			var swirl := medium.get_pixel((x + int(n.y * 14.0)) % SIZE, (y + int(n.x * 14.0)) % SIZE).r
			var v := 0.84 + (stain - 0.5) * 0.18 + (swirl - 0.5) * 0.16 + (n.z - 0.5) * 0.1
			if n.y > 0.78 and n.z > 0.55: v -= 0.12
			return [Color(v, v, v * 0.98), 0.6 + swirl * 0.3 + n.z * 0.1]
		"tar":
			var v := 0.7 + (stain - 0.5) * 0.28 + (n.z - 0.5) * 0.3
			var seam := x % 64 < 2
			if seam: v += 0.14
			if n.y > 0.7 and n.x > 0.5: v -= 0.12
			return [Color(v, v, v), 0.7 if seam else 0.55 + n.z * 0.3]
		"gravel":
			var r := _hash01(x / 2, y / 2, 21)
			var v := 0.5 + r * 0.45 + (stain - 0.5) * 0.2
			var h := 0.3 + r * 0.7
			return [Color(v, v, v * 0.97), h]
		"corrugated":
			# 16 ondas por tile de 1,28 m; ferrugem desce pelas ondas.
			var rib := 0.5 + 0.5 * sin(float(x) * TAU / 16.0)
			var v := 0.72 + rib * 0.24 + (n.z - 0.5) * 0.1
			var rust: float = coarse.get_pixel((x * 3) % SIZE, (y / 5) % SIZE).r
			var r := clampf((rust - 0.55) * 3.0, 0.0, 1.0) * clampf(n.y * 1.4, 0.0, 1.0)
			return [Color(v * (1.0 + r * 0.1), v * (1.0 - r * 0.2), v * (1.0 - r * 0.5)), rib]
		"shingle":
			# Fiadas de 24 px, telhas de 48 px alternadas, sombra sob cada fiada.
			var row := y / 24
			var off := 24 if row % 2 else 0
			var tx := (x + off) / 48
			var ly := y % 24
			var tone := _hash01(tx, row, 33)
			var v := 0.62 + tone * 0.3 + (n.z - 0.5) * 0.14 - stain * 0.08
			var gap := (x + off) % 48 < 2
			if gap: v -= 0.34
			if ly > 20: v -= 0.18
			return [Color(v, v, v), 0.2 if gap else (0.45 + 0.55 * (1.0 - float(ly) / 24.0))]
		"wood":
			# Tábuas de ~42 px; veio ao longo de x, nó raro, junta escura entre elas.
			var plank := y / 42
			var ly := y % 42
			if ly < 2:
				return [Color(0.3, 0.27, 0.24), 0.15]
			var tone := _hash01(plank, 1, 41)
			var grain: float = medium.get_pixel(x, (y * 7 + plank * 37) % SIZE).r
			var v := 0.62 + tone * 0.2 + (grain - 0.5) * 0.32 + (n.z - 0.5) * 0.08
			var butt := (x + plank * 83) % 256 < 2
			if butt: v -= 0.3
			return [Color(v * 1.04, v, v * 0.94), 0.25 if butt else 0.6 + grain * 0.3]
		"metal":
			var brush: float = medium.get_pixel(x, (y * 11) % SIZE).r
			var v := 0.72 + (brush - 0.5) * 0.26 + (n.z - 0.5) * 0.1
			if _hash01(x / 3, y / 5, 50) > 0.99: v += 0.18
			if stain > 0.7: v -= (stain - 0.7) * 0.5
			return [Color(v, v, v * 1.02), 0.5 + brush * 0.4]
		"fabric":
			var weave := 0.5 if (x / 2 + y / 2) % 2 == 0 else 0.0
			var v := 0.86 + weave * 0.1 + (n.z - 0.5) * 0.06 - (stain - 0.5) * 0.08
			if y % 128 < 2: v -= 0.12
			return [Color(v, v, v), weave]
		"snow":
			# Dunas suaves de vento, fundo azulado nas depressões e brilho esparso de cristal.
			var drift: float = medium.get_pixel((x + int(n.x * 22.0)) % SIZE, (y + int(n.y * 22.0)) % SIZE).r
			var v := 0.86 + (drift - 0.5) * 0.2 + (stain - 0.5) * 0.12 + (n.z - 0.5) * 0.05
			if _hash01(x, y, 70) > 0.985: v = minf(v + 0.14, 1.0)
			return [Color(v * 0.97, v * 0.99, v), 0.45 + drift * 0.5 + n.z * 0.05]
		"foliage":
			var leaf: float = medium.get_pixel((x * 2) % SIZE, (y * 2) % SIZE).r
			var v := 0.5 + leaf * 0.38 + (n.z - 0.5) * 0.22
			if _hash01(x / 3, y / 3, 61) > 0.93: v += 0.18
			return [Color(v * 0.92, v, v * 0.85), leaf]
	return [Color(0.8, 0.8, 0.8), 0.5]
