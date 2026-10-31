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
const AUTHORED := {"FoundryLofts":TAR,"ColdStorage":GRAVEL,"MarketHall":TAR,"UnionWorkshop":TAR,"Police":GRAVEL,"CornerDiner":GRAVEL,"Laundry":MEMBRANE,"FreightDepot":METAL}

static var _materials := {}


## Superfície por tipo de prédio, com variação determinística pelo id.
static func pick(kind: String, roll: float) -> int:
	match kind:
		"brownstone", "rowhouse", "rowhouse_terrace", "l_shaped_block", "cobra_house":
			return [TAR, GRAVEL, TAR, MEMBRANE][int(roll * 4.0) % 4]
		"office", "police_precinct", "hospital", "fire_station", "bank_branch":
			return [PAVERS, TAR, GRAVEL, PAVERS][int(roll * 4.0) % 4]
		"warehouse", "artisan_workshop", "garage", "warehouse_shop":
			return [METAL, GRAVEL, TAR][int(roll * 3.0) % 3]
	return [GRAVEL, TAR, WHITE, MEMBRANE][int(roll * 4.0) % 4]


## Troca o acabamento das lajes de telhado autoradas. Geometria, colisões, heliponto e
## circulação ficam intactos; sem plano extra e sem superfície/draw call extra.
static func replace_existing(root: Node3D, kind: String, key: String) -> void:
	if kind == "cobra_house": return
	var custom_roof := find_roof(root) if not root is UrbanBuildingBase else AABB()
	var inverse := root.global_transform.affine_inverse()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or instance.has_meta("harbor_roof_finish"): continue
		var part := String(instance.name)
		var authored := part in ["V1RoofSurface","RoofSurface"] or part.begins_with("V1UnitRoof_") or part.begins_with("TerraceUnitRoof_")
		if not authored and custom_roof.size != Vector3.ZERO and instance.mesh is BoxMesh:
			var box := inverse * (instance.global_transform * instance.get_aabb())
			authored = box.size.y <= .6 and box.position.is_equal_approx(custom_roof.position) and box.size.is_equal_approx(custom_roof.size)
		if not authored: continue
		var source := instance.get_active_material(0) as StandardMaterial3D
		if source == null or source.emission_enabled or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		var roll := float(posmod(hash(key + "|" + part),10000)) / 10000.0
		instance.material_override = material(int(AUTHORED.get(key,pick(kind,roll))))
		instance.set_meta("harbor_roof_finish",true)


static func material(surface: int) -> StandardMaterial3D:
	if _materials.has(surface): return _materials[surface]
	var surface_material := StandardMaterial3D.new()
	surface_material.albedo_texture = ImageTexture.create_from_image(_image(surface))
	surface_material.albedo_color = Color(.78,.80,.78)
	surface_material.uv1_triplanar = true
	surface_material.uv1_world_triplanar = true
	surface_material.uv1_scale = Vector3.ONE / TEXEL_METERS
	surface_material.roughness = 0.79 if surface == METAL else 0.96
	surface_material.metallic = 0.18 if surface == METAL else 0.0
	surface_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_materials[surface] = surface_material
	return surface_material


static func _image(surface: int) -> Image:
	var size := 256
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
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
	image.generate_mipmaps()
	return image


## Cor de um texel. `n` = mancha larga (sujeira/desbotado), `grain` = ruído fino.
static func _texel(surface: int, x: int, y: int, n: float, grain: float, _size: int) -> Color:
	match surface:
		TAR:
			# Rolos de manta de ~0,9 m (58 px) com emenda sobreposta clara.
			var strip := y % 58
			var base := Color("34363a").lerp(Color("4a4b4d"), n * 0.7)
			if strip < 1: base = Color("494c48")
			elif strip < 3: base = base.darkened(0.10)
			return base.lerp(Color("2a2b2d"), grain * 0.25)
		GRAVEL:
			var stone := Color("77766c").lerp(Color("5d6056"), grain)
			if grain > 0.96: stone = Color("969184")
			if grain < 0.05: stone = Color("4a453e")
			return stone.lerp(Color("5d584f"), (1.0 - n) * 0.35)
		PAVERS:
			# Placas de 1 m (64 px) com junta escura e tom próprio por placa.
			# Whole-number grouping/index; preserve integer truncation and precision.
			@warning_ignore("integer_division")
			var cell := Vector2i(x / 128, y / 128)
			var tone := float(hash(cell) % 100) / 100.0
			var base := Color("89877b").lerp(Color("77786d"), tone * .5)
			if x % 128 < 1 or y % 128 < 1: base = Color("646459")
			return base.lerp(Color("6f6a60"), n * 0.35 + grain * 0.08)
		MEMBRANE:
			var base := Color("4f6a55").lerp(Color("3f5646"), grain * 0.3)
			# Remendos retangulares mais escuros.
			# Whole-number grouping/index; preserve integer truncation and precision.
			@warning_ignore("integer_division")
			var patch := Vector2i(x / 128, y / 128)
			if hash(patch) % 7 == 0 and x % 128 > 23 and y % 128 > 34: base = base.darkened(0.16)
			return base.lerp(Color("6c7a60"), n * 0.3)
		METAL:
			# Chapa canelada: ondas a cada 10 px, ferrugem nas manchas.
			var wave := 0.5 + 0.5 * sin(float(x) / 10.0 * TAU)
			var base := Color("747d78").lerp(Color("535e5d"), wave * 0.6)
			if x % 128 < 2: base = Color("44494c")
			return base.lerp(Color("8a5a3a"), smoothstep(0.6, 0.9, n) * 0.55)
		WHITE:
			var base := Color("aaa595").lerp(Color("908d80"), grain * 0.15)
			# Sealed one-metre membrane strips, readable beyond the fine grain.
			if y % 64 < 2: base = base.darkened(.16)
			elif y % 64 < 4: base = base.lightened(.025)
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
