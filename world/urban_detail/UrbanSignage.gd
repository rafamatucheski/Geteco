extends RefCounted
class_name UrbanSignage

## Helper for generating authentic exterior 3D building signage.
## Strictly adheres to the rule: "Fachadas recebem somente o nome próprio do estabelecimento."
## Strips categories, slogans, and descriptive product/service labels.

const CANONICAL_PROPER_NAMES: Dictionary = {
	"NorthFrontage0": "North Pier",
	"NorthFrontage1": "Foundry Flats",
	"harbor_ammunation": "Ammu-Nation",
	"NorthFrontage2": "Ammu-Nation",
	"NorthFrontage3": "Union",
	# The V1 fuel frontage has no proper establishment name. Pumps communicate
	# its function visually; a category-only sign would violate the facade rule.
	"NorthFrontage4": "",
	"NorthFrontage5": "Customs House",
	"FoundryTerraceWest": "Foundry Terraces",
	"FoundryTerraceEast": "Foundry Terraces",
	"FoundryLofts": "Union Lofts",
	"CornerDiner": "Anchor Diner",
	"Laundry": "", # Communicated purely by appearance (washing drums/glazing)
	"UnionWorkshop": "Harbor Bindery",
	"MarketHall": "Breakwater",
	"ColdStorage": "Cold Storage",
	"Garage": "Westgate",
	"Police": "Harbor Patrol",
	"Clinic": "Bay Medical",
	"Apartments": "Union Lofts",
	"FreightOffice": "Port Authority",
	"FreightDepot": "Transatlantic",
	"ExchangeTower": "Northbank Exchange",
	"CivicTower": "Horizon",
	"MaritimeMuseum": "Maritime Museum",
	"IslandGrocer": "Northbank",
	"IslandCinema": "Orion",
	"Aquarium": "Bay Aquarium",
	"PromenadeCafe": "Tideline",
	"NorthbankFront0": "Bridge House",
	"NorthbankFront1": "Founders Club",
	"NorthbankFront2": "Design Works",
	"NorthbankFront3": "Eastgate Hotel",
	"GatewayFlats": "Gateway Flats",
	"TransitHouse": "Transit House",
	"MotorWorkshop": "",
	"RoadsideSupplies": "Hardware",
	"ServiceLodge": "Gateway Lodge",
	"ParcelOffice": "North Parcel",
	"NorthFireStation": "Northgate Fire",
	"ServiceCafe": "Early Shift",
	"NorthGrocer": "Canal Grocery",
	"CycleWorkshop": "Spoke",
	"UnionApartments": "North Union",
	"CommunityHall": "Northgate Hall",
	"CornerPharmacy": "Corner Pharmacy",
}

static func extract_proper_name(building_id: String, raw_name: String = "") -> String:
	if CANONICAL_PROPER_NAMES.has(building_id):
		return CANONICAL_PROPER_NAMES[building_id]
	if raw_name.is_empty():
		return ""
	
	# Clean up any UTF-8 decoding anomalies if present
	var clean := raw_name.strip_edges()
	
	# If name contains slash (category / proper name), extract the proper name part
	if "/" in clean:
		var parts := clean.split("/")
		# Common pattern in V1 was "CATEGORY / PROPER NAME" or "PROPER NAME / CATEGORY" or "NAME / 02"
		var candidates: Array[String] = []
		for part in parts:
			var trimmed := part.strip_edges()
			# Filter out numbers and known category words
			var upper := trimmed.to_upper()
			if upper in ["BANCO", "ROUPAS", "POSTO", "CONVENIÊNCIA", "CONVENIENCIA", "COFFEE", "CINEMA", "SUPPLY", "CYCLE CO.", "02", "03", "04"]:
				continue
			if trimmed.is_valid_int():
				continue
			candidates.append(trimmed)
		if candidates.size() > 0:
			clean = candidates[0]
		else:
			clean = parts[0].strip_edges()
	
	# Strip "THE " prefix if desired or title-case
	if clean.to_upper().begins_with("THE "):
		clean = clean.substr(4).strip_edges()
	
	# Format to Title Case for human elegance
	return clean.capitalize()

static func create_sign_3d(proper_name: String, size: Vector2, depth: float = 0.08, frame_mat: StandardMaterial3D = null) -> Node3D:
	if proper_name.is_empty():
		return null
	
	var root := Node3D.new()
	root.name = "Sign_" + proper_name.replace(" ", "_")
	
	# Sign backing board
	var board := MeshInstance3D.new()
	board.name = "BackingBoard"
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, depth)
	board.mesh = box
	if frame_mat != null:
		board.material_override = frame_mat
	else:
		board.material_override = UrbanMaterials.trim_dark()
	root.add_child(board)
	
	# Sign border trim
	var trim := MeshInstance3D.new()
	trim.name = "BoardTrim"
	var trim_box := BoxMesh.new()
	trim_box.size = Vector3(size.x + 0.06, size.y + 0.06, depth * 0.5)
	trim.mesh = trim_box
	trim.material_override = UrbanMaterials.metal_brass()
	trim.position.z = -depth * 0.25
	root.add_child(trim)
	
	return root
