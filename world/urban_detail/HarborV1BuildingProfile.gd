extends RefCounted
class_name HarborV1BuildingProfile

## Direct translation of ProceduralBuilding._palette and custom HarborBuilding
## typologies. Height is deliberately not inferred here: V1 screen extrusion
## is not world Y, while the two published skyline overrides retain /16.
const SOURCE_SITE_ORDERS := [
	["NorthFrontage0","NorthFrontage1","NorthFrontage2","NorthFrontage3","NorthFrontage4","NorthFrontage5","FoundryTerraceWest","FoundryTerraceEast","FoundryLofts","CornerDiner","Laundry","UnionWorkshop","MarketHall","ColdStorage","Garage","Police","Clinic","Apartments","FreightOffice","FreightDepot"],
	["ExchangeTower","CivicTower","MaritimeMuseum","NorthbankHomes0","NorthbankHomes1","NorthbankHomes2","IslandGrocer","IslandCinema","Aquarium","PromenadeCafe","NorthbankFront0","NorthbankFront1","NorthbankFront2","NorthbankFront3"],
	["BridgeCourtWest","BridgeCourtEast","BridgeQuayHouse","GatewayFlats","TransitHouse","MotorWorkshop","RoadsideSupplies","ServiceLodge","ParcelOffice","NorthFireStation","ServiceCafe","CanalHomesWest","CanalHomesEast","NorthGrocer","CycleWorkshop","GardenFlats","UnionApartments","CommunityHall","CornerPharmacy"],
	["PorchHouse","Duplex","ShingleHouse","CobraWorkshop","CourtyardHouse","BrickDuplex","TinRoofHouse","CornerBungalow"],
]


static func variant_seed_for_id(building_id: String) -> int:
	for order in SOURCE_SITE_ORDERS:
		var index: int=order.find(building_id)
		if index>=0: return (index+1)*17
	return 0


static func palette(kind: String, building_id: String, variant_seed: int, source_accent: Color) -> Dictionary:
	var result: Dictionary
	if kind == "commercial_laundromat":
		result={"roof":Color("505653"),"edge":Color("304c4d"),"front":Color("b7c5b8"),"accent":Color("69938a"),"window":Color("709fa3"),"mortar":Color("69938a")}
	elif kind == "artisan_workshop":
		result={"roof":Color("3a3c3d"),"edge":Color("1f2021"),"front":Color("693e32"),"accent":Color("baa995"),"window":Color("507682"),"mortar":Color("563025")}
	elif kind in ["corner_shop","corner_diner"]:
		result={"roof":Color("505653"),"edge":Color("353e40"),"front":Color("ac7c5e"),"accent":Color("d1b899"),"window":Color("496c70"),"mortar":Color("8a624d")}
	elif "ammunation" in kind:
		result={"roof":Color("292c31"),"edge":Color("111419"),"front":Color("4a3030"),"accent":Color("d4483f"),"window":Color("7f9aa0"),"mortar":Color("342326")}
	elif "clothing" in kind:
		result={"roof":Color("49364f"),"edge":Color("241d2a"),"front":Color("6e506c"),"accent":Color("53b0a3"),"window":Color("91c9c4"),"mortar":Color("513d52")}
	elif "hospital" in kind:
		result={"roof":Color("86989a"),"edge":Color("40545b"),"front":Color("aebfbd"),"accent":Color("4ca1ac"),"window":Color("7fc4cb"),"mortar":Color("748789")}
	elif "morgue" in kind or "iml" in kind:
		result={"roof":Color("181d24"),"edge":Color("090b0d"),"front":Color("2b3e50"),"accent":Color("8e44ad"),"window":Color("4a6572"),"mortar":Color("19222d")}
	elif "fire_station" in kind or "firehouse" in kind:
		result={"roof":Color("3d3332"),"edge":Color("1e1b1c"),"front":Color("75413a"),"accent":Color("d7503f"),"window":Color("8da9aa"),"mortar":Color("4f302d")}
	elif "police_precinct" in kind:
		result={"roof":Color("263a50"),"edge":Color("101e30"),"front":Color("4f6878"),"accent":Color("4ba4d8"),"window":Color("a8dce2"),"mortar":Color("344f63")}
	elif "police_substation" in kind:
		result={"roof":Color("36414b"),"edge":Color("1b2730"),"front":Color("647078"),"accent":Color("76a9bf"),"window":Color("afd6d5"),"mortar":Color("465960")}
	elif "police" in kind:
		result={"roof":Color("344558"),"edge":Color("172334"),"front":Color("586d7c"),"accent":Color("3b91c1"),"window":Color("9bc9d0"),"mortar":Color("405567")}
	elif "warehouse" in kind:
		result={"roof":Color("4e5151"),"edge":Color("282c2e"),"front":Color("6f6258"),"accent":Color("b58a42"),"window":Color("2f4248"),"mortar":Color("514842")}
	elif "garage" in kind:
		result={"roof":Color("665047"),"edge":Color("352a29"),"front":Color("806c5e"),"accent":Color("c69a43"),"window":Color("2d373b"),"mortar":Color("59483f")}
	elif "park" in kind:
		result={"roof":Color("526f55"),"edge":Color("293f30"),"front":Color("78936d"),"accent":Color("c2c879"),"window":Color("426554"),"mortar":Color("60775a")}
	elif "corner_shop" in kind or "shop" in kind:
		var shops := [
			{"roof":Color("673a3e"),"edge":Color("321f28"),"front":Color("986849"),"accent":Color("d4a947"),"window":Color("477d83"),"mortar":Color("704b3d")},
			{"roof":Color("405653"),"edge":Color("243230"),"front":Color("786d56"),"accent":Color("c59045"),"window":Color("4e858d"),"mortar":Color("5b5548")},
		]
		result=shops[posmod(variant_seed,shops.size())].duplicate()
	elif "rowhouse" in kind or "brownstone" in kind:
		var bricks := [
			{"roof":Color("513b3a"),"edge":Color("2c2527"),"front":Color("75483e"),"accent":Color("ae8252"),"window":Color("567e83"),"mortar":Color("593a35")},
			{"roof":Color("484346"),"edge":Color("29272b"),"front":Color("685a50"),"accent":Color("9e8056"),"window":Color("587783"),"mortar":Color("50463f")},
			{"roof":Color("3f494c"),"edge":Color("252c30"),"front":Color("59666a"),"accent":Color("a78250"),"window":Color("537b86"),"mortar":Color("465357")},
		]
		result=bricks[posmod(variant_seed,bricks.size())].duplicate()
	elif "office" in kind:
		result={"roof":Color("455258"),"edge":Color("252f34"),"front":Color("6f7977"),"accent":Color("a89358"),"window":Color("5b8998"),"mortar":Color("586361")}
	else:
		result={"roof":Color("5a4840"),"edge":Color("302824"),"front":Color("776354"),"accent":Color("b3955c"),"window":Color("537d87"),"mortar":Color("5e5045")}
	# HarborBuilding._palette replaces the generic accent with the authored site color.
	result.accent=source_accent
	result["building_id"]=building_id
	return result
