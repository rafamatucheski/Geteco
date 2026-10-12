extends RefCounted
## Superfícies procedurais do cais de passageiros: concreto com juntas, deck de tábuas, telhado
## de chapa, pavimento, estacas e painel solar. Cada tipo gera albedo + normal + rugosidade uma
## única vez (128 px, com mipmaps); nenhum custo por quadro. Triplanar em espaço de mundo para a
## densidade de texels não depender do tamanho de cada caixa do MultiMesh.
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const SIZE := 128

## tile = metros por repetição; offset alinha as juntas da textura às bordas reais da laje.
const SPECS := {
	"pier_concrete": {"kind": "concrete", "tint": "9aa3a0", "tile": 2.5, "offset": Vector3(.8, 0, .4), "bump": 1.1},
	"pier_deck": {"kind": "deck", "tint": "b08a62", "tile": 1.28, "bump": 1.3},
	"pier_deck_light": {"kind": "deck", "tint": "cdb48a", "tile": 1.28, "bump": 1.2},
	"pier_bench": {"kind": "deck", "tint": "a0693f", "tile": 1.28, "bump": 1.0},
	"pier_roof": {"kind": "roof", "tint": "4d7886", "tile": 1.28, "bump": 1.4, "metal": .18},
	"pier_paving": {"kind": "paving", "tint": "a9aeb0", "tile": 1.28, "bump": 1.2},
	"pier_pile": {"kind": "pile", "tint": "6d5b49", "tile": 1.0, "bump": 1.3},
	"pier_solar": {"kind": "solar", "tint": "5a7fb4", "tile": 1.28, "bump": .7, "metal": .35},
	"pier_bulb": {"kind": "plain", "tint": "ffd9a0", "emission": "ffc47e", "energy": 2.4},
}

static var _materials: Dictionary = {}
static var _maps: Dictionary = {}

static func has(key: String) -> bool:
	return SPECS.has(key)

static func material(key: String) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key]
	var spec: Dictionary = SPECS[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(spec["tint"])
	if spec["kind"] == "plain":
		result.roughness = .6
		result.emission_enabled = true
		result.emission = Color(spec["emission"])
		result.emission_energy_multiplier = spec["energy"]
		_materials[key] = result
		return result
	var maps := _maps_for(spec["kind"])
	result.albedo_texture = maps["albedo"]
	result.normal_enabled = true
	result.normal_texture = maps["normal"]
	result.normal_scale = spec.get("bump", 1.0)
	result.roughness = 1.0
	result.roughness_texture = maps["rough"]
	result.metallic = spec.get("metal", 0.0)
	result.uv1_triplanar = true
	result.uv1_world_triplanar = true
	var density := 1.0 / float(spec["tile"])
	result.uv1_scale = Vector3(density, density, density)
	result.uv1_offset = spec.get("offset", Vector3.ZERO)
	_materials[key] = result
	return result

static func _maps_for(kind: String) -> Dictionary:
	if _maps.has(kind): return _maps[kind]
	var started := STALL_WORK.begin()
	var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var bump := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rough := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	match kind:
		"concrete": _concrete(albedo, bump, rough)
		"deck": _deck(albedo, bump, rough)
		"roof": _roof(albedo, bump, rough)
		"paving": _paving(albedo, bump, rough)
		"pile": _pile(albedo, bump, rough)
		"solar": _solar(albedo, bump, rough)
	bump.bump_map_to_normal_map(2.0)
	for image in [albedo, bump, rough]: image.generate_mipmaps()
	var maps := {
		"albedo": ImageTexture.create_from_image(albedo),
		"normal": ImageTexture.create_from_image(bump),
		"rough": ImageTexture.create_from_image(rough),
	}
	_maps[kind] = maps
	if started != 0:
		STALL_WORK.finish("port.surface." + kind, started, {})
	return maps

static func _noise(seed_value: int, frequency: float, octaves := 3) -> Image:
	var generator := FastNoiseLite.new()
	generator.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	generator.seed = seed_value
	generator.frequency = frequency
	generator.fractal_octaves = octaves
	return generator.get_seamless_image(SIZE, SIZE)

static func _hash(a: float, b := 0.0) -> float:
	return fposmod(sin(a * 127.1 + b * 311.7) * 43758.5453, 1.0)

static func _put(albedo: Image, bump: Image, rough: Image, x: int, y: int, color: Color, height: float, roughness: float) -> void:
	albedo.set_pixel(x, y, color)
	bump.set_pixel(x, y, Color(height, height, height))
	rough.set_pixel(x, y, Color(roughness, roughness, roughness))

static func _concrete(albedo: Image, bump: Image, rough: Image) -> void:
	var broad := _noise(11, .03)
	var fine := _noise(12, .22, 2)
	var stain := _noise(13, .018, 2)
	var wet := _noise(14, .035, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90417
	for y in SIZE:
		for x in SIZE:
			var v := .80 + (broad.get_pixel(x, y).r - .5) * .22 + (fine.get_pixel(x, y).r - .5) * .12
			v += rng.randf_range(-.025, .025)
			var s: float = stain.get_pixel(x, y).r
			if s > .6: v -= (s - .6) * .7
			var roll := rng.randf()
			if roll < .012: v -= .16
			elif roll < .02: v += .08
			var height := .62 + (fine.get_pixel(x, y).r - .5) * .12
			var edge := mini(mini(x, SIZE - 1 - x), mini(y, SIZE - 1 - y))
			# Juntas de dilatação na borda do tile e serra-corte no meio de cada placa.
			var score := mini(absi(x - 64), absi(y - 64))
			if edge == 0:
				v *= .42
				height = .0
			elif edge == 1:
				v *= .62
				height = .2
			elif edge <= 3:
				v *= 1.05
			if score == 0 and edge > 3:
				v *= .7
				height = .3
			var wetness: float = wet.get_pixel(x, y).r
			var roughness := .88 - clampf((wetness - .56) * 4.0, 0.0, 1.0) * .62
			if wetness > .56: v *= .86
			_put(albedo, bump, rough, x, y, Color(v, v * 1.01, v * .99), height, roughness)

static func _deck(albedo: Image, bump: Image, rough: Image) -> void:
	var warp := _noise(21, .05)
	var grain := _noise(22, .35, 2)
	var weather := _noise(23, .025, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5521
	var plank_h := 16
	for y in SIZE:
		var p := floori(float(y) / plank_h)
		var ly := y % plank_h
		var tone := .84 + _hash(p, 3.0) * .22
		var warm := _hash(p, 7.0) * .08
		var joint := int(_hash(p, 11.0) * (SIZE - 24)) + 12
		var knot_x := int(_hash(p, 17.0) * SIZE)
		var has_knot := _hash(p, 19.0) < .4
		for x in SIZE:
			var w: float = warp.get_pixel(x, y).r
			var v := tone + sin((x * .22 + w * 9.0 + p * 4.0)) * .035 + (grain.get_pixel(x, y).r - .5) * .16
			v += rng.randf_range(-.015, .015)
			var wx: float = weather.get_pixel(x, y).r
			var gray := clampf((wx - .45) * 1.6, 0.0, .6)
			var height := .85
			var roughness := .82
			if ly < 2:
				v *= .32
				height = .0
			elif ly == 2:
				v *= 1.12
				height = .7
			elif ly == plank_h - 1:
				v *= .78
				height = .55
			if absi(x - joint) <= 0 and ly >= 2:
				v *= .42
				height = .15
			if has_knot and ly >= 2:
				var d := Vector2(x - knot_x, ly - 8).length()
				if d < 5.0 and d > 2.0: v *= .72
				elif d <= 2.0: v *= .55
			# Pregos: dois de cada lado da emenda.
			if ly in [5, 10] and (absi(x - (joint + 5)) <= 0 or absi(x - (joint - 5)) <= 0):
				v *= .4
				height = .2
			var color := Color(v * (1.0 + warm), v * (1.0 - warm * .3), v * (1.0 - warm * .9)).lerp(Color(v, v, v * .98), gray)
			_put(albedo, bump, rough, x, y, color, height, roughness + gray * .12)

static func _roof(albedo: Image, bump: Image, rough: Image) -> void:
	var streak := _noise(31, .12, 2)
	var stain := _noise(32, .03, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7313
	for y in SIZE:
		for x in SIZE:
			var px := x % 64
			var v := .76 + float(px) / 64.0 * .06
			v += (streak.get_pixel(x, 0).r - .5) * .12 + rng.randf_range(-.012, .012)
			var s: float = stain.get_pixel(x, y).r
			if s > .58: v -= (s - .58) * .5
			var height := .5
			var roughness := .55 + maxf(0.0, s - .5) * .5
			# Junta de pé: nervura levantada com brilho de um lado e sombra do outro.
			if px == 0:
				v += .20
				height = 1.0
			elif px == 1:
				v += .10
				height = .9
			elif px == 2 or px == 3:
				v *= .62
				height = .25
			if y == 0:
				v *= .8
				height = .3
			if (px == 14 or px == 50) and y % 32 == 16:
				v *= .45
				height = .75
			var rust: float = maxf(0.0, s - .64) * 1.4
			var color := Color(v + rust * .12, v - rust * .02, v - rust * .1)
			_put(albedo, bump, rough, x, y, color, height, roughness)

static func _paving(albedo: Image, bump: Image, rough: Image) -> void:
	var fine := _noise(41, .3, 2)
	var wet := _noise(42, .04, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3109
	for y in SIZE:
		var row := floori(float(y) / 16.0)
		var ly := y % 16
		for x in SIZE:
			var shifted := (x + (16 if row % 2 == 1 else 0)) % SIZE
			var col := floori(float(shifted) / 32.0)
			var lx := shifted % 32
			var tone := .78 + _hash(row * 13.0 + col, 5.0) * .2
			var cool := _hash(row * 7.0 + col, 9.0) * .08
			var v := tone + (fine.get_pixel(x, y).r - .5) * .1 + rng.randf_range(-.02, .02)
			var height := .8
			if ly == 0 or lx == 0:
				v *= .4
				height = .05
			elif ly == 1 or lx == 1:
				v *= 1.08
				height = .6
			var wetness: float = wet.get_pixel(x, y).r
			var roughness := .85 - clampf((wetness - .55) * 4.0, 0.0, 1.0) * .55
			_put(albedo, bump, rough, x, y, Color(v * (1.0 - cool), v, v * (1.0 + cool)), height, roughness)

static func _pile(albedo: Image, bump: Image, rough: Image) -> void:
	var fibre := _noise(51, .05, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6041
	for y in SIZE:
		for x in SIZE:
			# Veio vertical: amostra o ruído numa linha só para esticar ao longo de y.
			var streak: float = fibre.get_pixel(x, floori(y / 24.0) * 3 % SIZE).r
			var v := .62 + (streak - .5) * .45 + rng.randf_range(-.03, .03)
			var height := .6 + (streak - .5) * .3
			if _hash(floorf(x / 3.0), 2.0) < .06:
				v *= .55
				height = .2
			# Faixa de maré: o tile é de 1 m, então ela se repete a cada metro de altura.
			if y > SIZE - 22:
				v *= .78
				v += _hash(x, y) * .05
			_put(albedo, bump, rough, x, y, Color(v, v * .96, v * .9), height, .86)

static func _solar(albedo: Image, bump: Image, rough: Image) -> void:
	var sheen := _noise(61, .02, 2)
	for y in SIZE:
		for x in SIZE:
			var cx := x % 16
			var cy := y % 16
			var v := .30 + (sheen.get_pixel(x, y).r - .5) * .1
			var height := .7
			var roughness := .28
			if cx == 0 or cy == 0:
				v = .72
				height = .2
				roughness = .5
			elif cx == 8 or cx == 4 or cx == 12:
				v += .05
			if x % 64 == 0 or y % 64 == 0:
				v = .85
			_put(albedo, bump, rough, x, y, Color(v * .86, v * .95, v * 1.08), height, roughness)
