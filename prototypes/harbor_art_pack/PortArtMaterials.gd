class_name PortArtMaterials
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

static func container_blue() -> StandardMaterial3D:
	return get_mat("port_container_blue", Color("#1b4965"), 0.40, 0.55)

static func container_rust() -> StandardMaterial3D:
	return get_mat("port_container_rust", Color("#8b3a2b"), 0.35, 0.65)

static func container_teal() -> StandardMaterial3D:
	return get_mat("port_container_teal", Color("#2a6f7b"), 0.40, 0.55)

static func container_amber() -> StandardMaterial3D:
	return get_mat("port_container_amber", Color("#b87d28"), 0.35, 0.60)

static func container_white() -> StandardMaterial3D:
	return get_mat("port_container_white", Color("#d5d8dc"), 0.25, 0.50)

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
