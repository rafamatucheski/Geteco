class_name ArtPresentationCache
extends RefCounted

## Cache centralizado de geometrias primitivas e materiais imutaveis.
## Evita a criacao redundante de milhares de instancias de BoxMesh, SphereMesh e
## StandardMaterial3D em runtime, reduzindo significativamente a pressao de VRAM,
## RIDs do RenderingServer e tempo de construcao no frame.
##
## REGRA DE OURO DE ISOLAMENTO:
## Materiais no cache sao estritamente IMUTAVEIS. Qualquer ator que receba dano,
## sangue, queimadura, deformacao ou pintura personalizada DEVE usar
## create_damage_material() ou create_isolated_material() para nunca vazar
## alteracoes visuais a outros atores.

# --- 1. CACHE DE MESHES COMPARTILHADAS (IMUTAVEIS) ---
static var _unit_box: BoxMesh = null
static var _unit_sphere: SphereMesh = null
static var _unit_cylinder: CylinderMesh = null

static func get_unit_box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _unit_box

static func get_unit_sphere() -> SphereMesh:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 0.5
		_unit_sphere.height = 1.0
		_unit_sphere.radial_segments = 10
		_unit_sphere.rings = 5
	return _unit_sphere

static func get_unit_cylinder() -> CylinderMesh:
	if _unit_cylinder == null:
		_unit_cylinder = CylinderMesh.new()
		_unit_cylinder.top_radius = 0.5
		_unit_cylinder.bottom_radius = 0.5
		_unit_cylinder.height = 1.0
		_unit_cylinder.radial_segments = 10
		_unit_cylinder.rings = 1
	return _unit_cylinder


# --- 2. CACHE DE MATERIAIS COMPARTILHADOS (IMUTAVEIS) ---
static var _materials_cache: Dictionary = {}

static func _get_or_create_material(key: String, albedo: Color, roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	if _materials_cache.has(key):
		return _materials_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	_materials_cache[key] = mat
	return mat


# --- Paletas de Luto e Funeral ---
const SUIT_PALETTES: Array[Color] = [
	Color("#1a1a20"), # Preto carvao classico
	Color("#272932"), # Grafite escuro elegante
	Color("#1e232d"), # Azul marinho meia-noite
	Color("#2c2b30"), # Ardosia escura quente
	Color("#353535"), # Cinza chumbo escovado
	Color("#2b2528")  # Castanho escuro / ameixa
]

const SKIN_PALETTES: Array[Color] = [
	Color("#d6a374"), # Moreno claro / oliva
	Color("#b87850"), # Moreno medio quente
	Color("#6d4430"), # Pele negra rica
	Color("#8a583e"), # Pele negra acobreada
	Color("#eac0a2"), # Pele clara suave
	Color("#c98b64")  # Moreno bronzeado
]

const HAIR_PALETTES: Array[Color] = [
	Color("#111113"), # Preto espresso
	Color("#3b2b20"), # Castanho escuro
	Color("#63554d"), # Castanho acinzentado
	Color("#8c8c88"), # Grisalho maduro
	Color("#261c16"), # Cafe
	Color("#7d6048")  # Castanho medio
]

static func get_suit_material(variant_idx: int) -> StandardMaterial3D:
	var idx := variant_idx % SUIT_PALETTES.size()
	return _get_or_create_material("suit_%d" % idx, SUIT_PALETTES[idx], 0.70)

static func get_pants_material(variant_idx: int) -> StandardMaterial3D:
	var idx := variant_idx % SUIT_PALETTES.size()
	return _get_or_create_material("pants_%d" % idx, SUIT_PALETTES[idx].darkened(0.12), 0.75)

static func get_skin_material(variant_idx: int) -> StandardMaterial3D:
	var idx := (variant_idx * 2 + 1) % SKIN_PALETTES.size()
	return _get_or_create_material("skin_%d" % idx, SKIN_PALETTES[idx], 0.55)

static func get_hair_material(variant_idx: int) -> StandardMaterial3D:
	var idx := (variant_idx * 3) % HAIR_PALETTES.size()
	return _get_or_create_material("hair_%d" % idx, HAIR_PALETTES[idx], 0.85)

static func get_shoes_material() -> StandardMaterial3D:
	return _get_or_create_material("shoes_black", Color("#121113"), 0.35, 0.15)

static func get_shirt_collar_material() -> StandardMaterial3D:
	return _get_or_create_material("shirt_white", Color("#ebe8e4"), 0.60)


# --- Materiais Exclusivos de Elias ---
static func get_elias_overcoat_material() -> StandardMaterial3D:
	return _get_or_create_material("elias_overcoat", Color("#4b4034"), 0.78)

static func get_elias_scarf_material() -> StandardMaterial3D:
	return _get_or_create_material("elias_scarf", Color("#ad6834"), 0.88)

static func get_elias_cap_material() -> StandardMaterial3D:
	return _get_or_create_material("elias_cap", Color("#292624"), 0.70)

static func get_elias_skin_material() -> StandardMaterial3D:
	return _get_or_create_material("elias_skin", Color("#c7926e"), 0.60)

static func get_elias_beard_material() -> StandardMaterial3D:
	return _get_or_create_material("elias_beard", Color("#dedbd7"), 0.90)

static func get_elias_satchel_material() -> StandardMaterial3D:
	return _get_or_create_material("elias_satchel", Color("#5c3c24"), 0.65)

static func get_elias_spectacles_material() -> StandardMaterial3D:
	return _get_or_create_material("elias_gold_specs", Color("#d4af37"), 0.25, 0.85)


# --- Materiais Exclusivos do Coveiro / Ferramentas ---
static func get_worker_jacket_material() -> StandardMaterial3D:
	return _get_or_create_material("worker_jacket", Color("#324436"), 0.85)

static func get_worker_gloves_material() -> StandardMaterial3D:
	return _get_or_create_material("worker_gloves", Color("#755331"), 0.70)

static func get_worker_trousers_material() -> StandardMaterial3D:
	return _get_or_create_material("worker_trousers", Color("#383e3a"), 0.88)

static func get_worker_boots_material() -> StandardMaterial3D:
	return _get_or_create_material("worker_boots", Color("#1e1e20"), 0.60)

static func get_shovel_wood_material() -> StandardMaterial3D:
	return _get_or_create_material("shovel_wood", Color("#8b6947"), 0.75)

static func get_shovel_steel_material() -> StandardMaterial3D:
	return _get_or_create_material("shovel_steel", Color("#6e7378"), 0.35, 0.70)


# --- Materiais de Caixao e Sepultura ---
static func get_casket_wood_material() -> StandardMaterial3D:
	return _get_or_create_material("casket_mahogany", Color("#381912"), 0.38, 0.05)

static func get_casket_brass_material() -> StandardMaterial3D:
	return _get_or_create_material("casket_brass", Color("#d4a037"), 0.28, 0.75)

static func get_grave_dirt_material() -> StandardMaterial3D:
	return _get_or_create_material("grave_dirt", Color("#33241b"), 0.95)

static func get_grave_rope_material() -> StandardMaterial3D:
	return _get_or_create_material("grave_rope", Color("#a68963"), 0.90)


# --- 3. ISOLAMENTO SEGURO DE MATERIAIS DINAMICOS (ZERO VAZAMENTO) ---

static func create_isolated_material(base_material: StandardMaterial3D, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var dup: StandardMaterial3D = base_material.duplicate()
	if tint != Color.WHITE:
		dup.albedo_color = dup.albedo_color * tint
	return dup

static func create_damage_material(base_material: StandardMaterial3D, damage_type: String, intensity: float = 1.0) -> StandardMaterial3D:
	var dup: StandardMaterial3D = base_material.duplicate()
	match damage_type:
		"blood":
			var blood_color := Color("#7a0d0d")
			dup.albedo_color = dup.albedo_color.lerp(blood_color, clampf(0.55 * intensity, 0.0, 0.85))
			dup.roughness = clampf(dup.roughness * 0.4, 0.1, 0.8)
		"burn", "fire":
			var soot_color := Color("#151313")
			dup.albedo_color = dup.albedo_color.lerp(soot_color, clampf(0.75 * intensity, 0.0, 0.95))
			dup.roughness = 0.98
		"dirt", "grime":
			var mud_color := Color("#3b281c")
			dup.albedo_color = dup.albedo_color.lerp(mud_color, clampf(0.45 * intensity, 0.0, 0.70))
			dup.roughness = 0.92
		_:
			dup.albedo_color = dup.albedo_color.darkened(0.3 * intensity)
	return dup

static func clear_cache() -> void:
	_materials_cache.clear()
	_unit_box = null
	_unit_sphere = null
	_unit_cylinder = null