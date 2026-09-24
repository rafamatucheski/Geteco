extends RefCounted
class_name NecoPressMaterials

## Centralized shared material palette for Neco's vehicle crusher/press.
## Strictly follows Geteco V2 performance standards: cached StandardMaterial3D instances,
## zero per-frame material churn, correct roughness and metallicity.

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

# --- Structural Steel & Paint ---

## Industrial machinery yellow for structural columns and warning trims (matching V1 #d39c43)
static func frame_yellow() -> StandardMaterial3D:
	return get_mat("frame_yellow", Color("#d39c43"), 0.55, 0.45)

## Steel gantry rails and guide tracks (matching V1 #788579)
static func gantry_steel() -> StandardMaterial3D:
	return get_mat("gantry_steel", Color("#788579"), 0.45, 0.70)

## Reinforced concrete / heavy steel base platform (matching V1 #566556)
static func platform_base() -> StandardMaterial3D:
	return get_mat("platform_base", Color("#566556"), 0.85, 0.25)

## Heavy wear-resistant crushing ram plate (matching V1 #59665a)
static func press_plate() -> StandardMaterial3D:
	return get_mat("press_plate", Color("#4f5b50"), 0.65, 0.60)

## Polished chrome / hydraulic cylinder piston rods (matching V1 #c1c7b9)
static func piston_chrome() -> StandardMaterial3D:
	return get_mat("piston_chrome", Color("#c1c7b9"), 0.15, 0.95)

## Hydraulic pump motor housing (matching V1 #8d6240)
static func pump_housing() -> StandardMaterial3D:
	return get_mat("pump_housing", Color("#8d6240"), 0.65, 0.50)

## Hazard threshold teeth (matching V1 #dfb35b)
static func hazard_yellow() -> StandardMaterial3D:
	return get_mat("hazard_yellow", Color("#dfb35b"), 0.50, 0.30)

## High-pressure hydraulic rubber hoses
static func rubber_hose() -> StandardMaterial3D:
	return get_mat("rubber_hose", Color("#1a1c1c"), 0.90, 0.05)

## Cast iron machine fittings and brackets
static func dark_iron() -> StandardMaterial3D:
	return get_mat("dark_iron", Color("#27292a"), 0.70, 0.65)
