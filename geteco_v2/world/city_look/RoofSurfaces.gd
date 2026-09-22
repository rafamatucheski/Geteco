extends RefCounted
## Acabamento de laje com textura de verdade em vez de cor chapada.
##
## Seis superfícies procedurais (geradas uma vez, 256 px): manta asfáltica com
## emendas, brita, placas de concreto, membrana verde remendada, zinco
## canelado e manta branca manchada. A UV é triplanar em coordenadas de MUNDO,
## então um único material por superfície serve a qualquer tamanho de laje (a
## instância do MultiMesh só escala o quad; a textura não estica).

const TEXEL_METERS := 4.0  # uma repetição da textura cobre 4 m de laje

const TAR := 0
const GRAVEL := 1
const PAVERS := 2
const MEMBRANE := 3
const METAL := 4
const WHITE := 5
const COUNT := 6

static var _materials := {}


## Superfície por tipo de prédio, com variação determinística pelo id.
static func pick(kind: String, roll: float) -> int:
	match kind:
		"brownstone", "rowhouse", "rowhouse_terrace", "l_shaped_block", "cobra_house":
			return [TAR, GRAVEL, TAR, MEMBRANE][int(roll * 4.0) % 4]
		"office", "police_precinct", "hospital", "fire_station", "bank_branch":
			return [PAVERS, WHITE, GRAVEL, PAVERS][int(roll * 4.0) % 4]
		"warehouse", "artisan_workshop", "garage", "warehouse_shop":
			return [METAL, METAL, TAR][int(roll * 3.0) % 3]
	return [GRAVEL, TAR, WHITE, MEMBRANE][int(roll * 4.0) % 4]


static func material(surface: int) -> StandardMaterial3D:
	if _materials.has(surface): return _materials[surface]
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(_image(surface))
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / TEXEL_METERS
	material.roughness = 0.35 if surface == METAL else 0.92
	material.metallic = 0.35 if surface == METAL else 0.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_materials[surface] = material
	return material


static func _image(surface: int) -> Image:
	var size := 256
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + surface * 31
	var noise := FastNoiseLite.new()
	noise.seed = 991 + surface
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var grain := rng.randf()
			image.set_pixel(x, y, _texel(surface, x, y, n, grain, size))
	return image


## Cor de um texel. `n` = mancha larga (sujeira/desbotado), `grain` = ruído fino.
static func _texel(surface: int, x: int, y: int, n: float, grain: float, size: int) -> Color:
	match surface:
		TAR:
			# Rolos de manta de ~0,9 m (58 px) com emenda sobreposta clara.
			var strip := y % 58
			var base := Color("34363a").lerp(Color("4a4b4d"), n * 0.7)
			if strip < 3: base = Color("5b5c5a")
			elif strip < 6: base = base.darkened(0.25)
			return base.lerp(Color("2a2b2d"), grain * 0.25)
		GRAVEL:
			var stone := Color("8f887a").lerp(Color("6d675d"), grain)
			if grain > 0.93: stone = Color("b7b0a0")
			if grain < 0.05: stone = Color("4a453e")
			return stone.lerp(Color("5d584f"), (1.0 - n) * 0.35)
		PAVERS:
			# Placas de 1 m (64 px) com junta escura e tom próprio por placa.
			var cell := Vector2i(x / 64, y / 64)
			var tone := float(hash(cell) % 100) / 100.0
			var base := Color("a3a097").lerp(Color("8a877f"), tone)
			if x % 64 < 2 or y % 64 < 2: base = Color("55534f")
			return base.lerp(Color("6f6a60"), n * 0.35 + grain * 0.08)
		MEMBRANE:
			var base := Color("4f6a55").lerp(Color("3f5646"), grain * 0.3)
			# Remendos retangulares mais escuros.
			var patch := Vector2i(x / 40, y / 32)
			if hash(patch) % 7 == 0: base = base.darkened(0.3)
			if x % 40 == 0 and hash(patch) % 7 == 0: base = Color("2b3a30")
			return base.lerp(Color("6c7a60"), n * 0.3)
		METAL:
			# Chapa canelada: ondas a cada 10 px, ferrugem nas manchas.
			var wave := 0.5 + 0.5 * sin(float(x) / 10.0 * TAU)
			var base := Color("8b9296").lerp(Color("5f666a"), wave * 0.6)
			if x % 128 < 2: base = Color("44494c")
			return base.lerp(Color("8a5a3a"), smoothstep(0.6, 0.9, n) * 0.55)
		WHITE:
			var base := Color("d8d6cf").lerp(Color("bdbab0"), grain * 0.15)
			# Escorrimento e poça seca (cinza) nas manchas baixas.
			return base.lerp(Color("8d8a80"), smoothstep(0.55, 0.85, 1.0 - n) * 0.6)
	return Color.MAGENTA


## Laje de prédio fora dos arquétipos (hospital, residências, Maciota...):
## maior caixa horizontal mais alta que cobre ≥60% da pegada. Espaço do chunk.
static func find_roof(root: Node3D) -> AABB:
	var inverse := root.global_transform.affine_inverse()
	var boxes := []
	var footprint := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.visible or mesh.mesh == null: continue
		var box := inverse * (mesh.global_transform * mesh.get_aabb())
		footprint = box if first else footprint.merge(box)
		first = false
		# Só caixa alinhada ao eixo serve de laje: telhado de duas águas tem
		# AABB até a cumeeira e o acabamento flutuaria no ar.
		var basis := (inverse * mesh.global_transform).basis.orthonormalized()
		if not mesh.mesh is BoxMesh or absf(basis.y.y) < 0.999 or absf(basis.x.x) < 0.999 and absf(basis.x.z) < 0.999: continue
		boxes.append(box)
	if first or footprint.size.x < 4.0 or footprint.size.z < 4.0: return AABB()
	var best := AABB()
	for box in boxes:
		if box.size.x < footprint.size.x * 0.6 or box.size.z < footprint.size.z * 0.6: continue
		if box.size.y > 0.6 and box.end.y < 2.0: continue
		if best.size == Vector3.ZERO or box.end.y > best.end.y: best = box
	return best
