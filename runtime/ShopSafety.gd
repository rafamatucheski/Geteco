extends RefCounted
## Peaceful retail interiors share admission, combat and resident protection.
## Banks and hostile/story interiors keep their existing gameplay contracts.
const IDS := ["harbor_curitiba_cellar", "harbor_supermarket", "harbor_ammunation",
	"mountain_gunshop", "harbor_clothing", "mountain_outfitters", "mountain_boutique",
	"mountain_village_outfitters", "harbor_fuel", "ski_lodge", "desert_digo", "harbor_gym"]
static var _building_policy: Dictionary = {}

static func peaceful(id: String) -> bool:
	if id in IDS: return true
	if not id.begins_with("harbor_building_"): return false
	if not _building_policy.has(id):
		var definition: Dictionary = load("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").find(id)
		_building_policy[id] = definition.get("archetype", "") in ["retail", "hospitality"] and definition.get("building_kind", "") != "bank_branch"
	return bool(_building_policy[id])

static func admission_allowed(id: String, stars: int) -> bool:
	return not peaceful(id) or stars <= 0
