extends RefCounted
class_name HarborRouteMaterials

## Central cached material palette for the urban route detail (Rodoviária → Delegacia → Garagem do Maciota).
## Adheres to Geteco V2 performance standards: cached StandardMaterial3D instances,
## no per-frame material churn, correct roughness, metallicity, and authentic Harbor urban colors.

const SURFACES := preload("res://assets/urban_detail/UrbanSurfaces.gd")

static var _cache: Dictionary = {}

static func get_mat(key: String, color: Color = Color.WHITE, roughness: float = 0.82, metallic: float = 0.0, emissive: Color = Color.BLACK) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emissive != Color.BLACK:
		mat.emission_enabled = true
		mat.emission = emissive
		mat.emission_energy_multiplier = 1.6
	_cache[key] = mat
	return mat

# --- Pavements & Curbs ---

## Light textured concrete slab for sidewalks and promenades (matching Harbor urban tone #989c92)
static func sidewalk_concrete() -> StandardMaterial3D:
	return SURFACES.material("route_sidewalk_concrete", "paving", Color("#989c92"), 0.88, 0.0, 2.0, 1.0)

## Darker washed concrete paving for promenade borders and pedestrian crossings
static func sidewalk_accent() -> StandardMaterial3D:
	return SURFACES.material("route_sidewalk_accent", "paving", Color("#7f8379"), 0.86, 0.0, 2.0, 1.2)

## Heavy granite/concrete curb stones (matching #aaad98)
static func curb_granite() -> StandardMaterial3D:
	return SURFACES.material("route_curb_granite", "granite", Color("#aaad98"), 0.80, 0.0, 2.0, 1.0)

## Safety yellow curb paint for official loading zones and bay boundaries
static func curb_yellow_marking() -> StandardMaterial3D:
	return get_mat("curb_yellow_marking", Color("#dfa838"), 0.65, 0.15)

## White reflective thermoplastic pavement marking for pedestrian crossings
static func pavement_white() -> StandardMaterial3D:
	return SURFACES.material("route_pavement_white", "concrete", Color("#e6e4dc"), 0.72, 0.0, 2.0, 0.6)

# --- Metals & Street Furniture ---

## Cast iron for antique bollards, heavy lamppost bases, and tree grates (#2e3436)
static func cast_iron_dark() -> StandardMaterial3D:
	return SURFACES.material("route_cast_iron", "metal", Color("#2a3032"), 0.72, 0.65, 1.0, 1.0)

## Galvanized steel for modern streetlights, bike racks, and sign posts (#6e7c80)
static func steel_galvanized() -> StandardMaterial3D:
	return SURFACES.material("route_galvanized", "metal", Color("#6e7c80"), 0.45, 0.75, 1.0, 1.0)

## Treated hardwood slats for transit benches (#8b5e3c)
static func bench_wood() -> StandardMaterial3D:
	var result := get_mat("bench_wood", Color("#8b5e3c"), 0.75, 0.0)
	result.albedo_texture = preload("res://world/places/ShopInteriorMaterials.gd").texture("wood")
	result.uv1_triplanar = true
	return result

## High-durability waste hopper / litter bin dark grey (#3c4447)
static func trash_bin_metal() -> StandardMaterial3D:
	return SURFACES.material("route_trash_bin", "metal", Color("#3c4447"), 0.60, 0.4, 1.0, 1.0)

# --- Specialized Accents (Police, Workshop, Utilities) ---

## Institutional Harbor Police blue for bollard accent bands and precinct lamp posts (#234c58)
static func police_navy() -> StandardMaterial3D:
	return get_mat("police_navy", Color("#234c58"), 0.55, 0.35)

## Municipal emergency hydrant red (#a82b2b)
static func hydrant_red() -> StandardMaterial3D:
	return get_mat("hydrant_red", Color("#a82b2b"), 0.50, 0.40)

## Polished brass fittings on hydrants (#c89b3c)
static func hydrant_brass() -> StandardMaterial3D:
	return get_mat("hydrant_brass", Color("#c89b3c"), 0.25, 0.85)

## Industrial workshop hazard yellow for apron safety posts (#e5b535)
static func hazard_yellow() -> StandardMaterial3D:
	return get_mat("hazard_yellow", Color("#e5b535"), 0.45, 0.20)

## Weathered asphalt/grease patch for garage driveway transition (#383634)
static func workshop_apron() -> StandardMaterial3D:
	return SURFACES.material("route_apron", "concrete", Color("#484643"), 0.92, 0.0, 2.0, 1.2)

## Cast iron storm sewer drainage grate (#242829)
static func drain_grate() -> StandardMaterial3D:
	return SURFACES.material("route_drain_grate", "metal", Color("#242829"), 0.80, 0.7, 0.5, 1.4)

# --- Lighting & Landscaping ---

## Warm emissive glow for street lamp luminaires
static func lamp_emissive() -> StandardMaterial3D:
	return get_mat("lamp_emissive", Color("#fff1d0"), 0.20, 0.10, Color("#ffebb5"))

## Frosted glass globe for lamp heads
static func lamp_glass() -> StandardMaterial3D:
	if _cache.has("lamp_glass"):
		return _cache["lamp_glass"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.92, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.25
	mat.metallic = 0.10
	_cache["lamp_glass"] = mat
	return mat

## Chiseled granite planter box wall
static func planter_stone() -> StandardMaterial3D:
	return SURFACES.material("route_planter", "granite", Color("#6e736b"), 0.90, 0.0, 1.0, 1.0)

## Maritime coastal shrub foliage (#3d5945)
static func shrub_foliage() -> StandardMaterial3D:
	return SURFACES.material("route_shrub", "foliage", Color("#3d5945"), 0.85, 0.0, 0.6, 1.0)
