extends SceneTree
## Offline-only exporter run from the V1 project root. It renders the actual
## productive HarborBuilding/CobraResidence drawing code to transparent PNGs.
## The V2 runtime never creates a SubViewport for these source projections.

const HARBOR_BUILDING := preload("res://world/harbor/HarborBuilding.gd")
const HOSPITAL_BUILDING := preload("res://world/harbor/hospital/HarborHospital.gd")
const COBRA_RESIDENCE := preload("res://world/harbor/cobras/CobraResidence.gd")
const DATA_PATH := "res://world/regions/OriginalWorldData.json"
const OUTPUT_PATH := "res://assets/regions/source/world/harbor/building_atlas"
const MARGIN := 24
const PROPER_NAMES := {
	"NorthFrontage0":"North Pier","NorthFrontage1":"Foundry Flats","NorthFrontage2":"Ammu-Nation",
	"NorthFrontage3":"Union","NorthFrontage4":"","NorthFrontage5":"Customs House",
	"FoundryTerraceWest":"Foundry Terraces","FoundryTerraceEast":"Foundry Terraces","FoundryLofts":"Union Lofts",
	"CornerDiner":"Anchor Diner","Laundry":"","UnionWorkshop":"Harbor Bindery","MarketHall":"Breakwater",
	"ColdStorage":"Cold Storage","Police":"Harbor Patrol","Clinic":"Bay Medical","Apartments":"Union Lofts",
	"FreightOffice":"Port Authority","FreightDepot":"Transatlantic","ExchangeTower":"Northbank Exchange",
	"CivicTower":"Horizon","MaritimeMuseum":"Maritime Museum","IslandGrocer":"Northbank","IslandCinema":"Orion",
	"Aquarium":"Bay Aquarium","PromenadeCafe":"Tideline","NorthbankFront0":"Bridge House",
	"NorthbankFront1":"Founders Club","NorthbankFront2":"Design Works","NorthbankFront3":"Eastgate Hotel",
	"GatewayFlats":"Gateway Flats","TransitHouse":"Transit House","MotorWorkshop":"","RoadsideSupplies":"Hardware",
	"ServiceLodge":"Gateway Lodge","ParcelOffice":"North Parcel","NorthFireStation":"Northgate Fire",
	"ServiceCafe":"Early Shift","NorthGrocer":"Canal Grocery","CycleWorkshop":"Spoke",
	"UnionApartments":"North Union","CommunityHall":"Northgate Hall","CornerPharmacy":"Corner Pharmacy",
}
const SOURCE_ORDERS := [
	["NorthFrontage0","NorthFrontage1","NorthFrontage2","NorthFrontage3","NorthFrontage4","NorthFrontage5","FoundryTerraceWest","FoundryTerraceEast","FoundryLofts","CornerDiner","Laundry","UnionWorkshop","MarketHall","ColdStorage","Garage","Police","Clinic","Apartments","FreightOffice","FreightDepot"],
	["ExchangeTower","CivicTower","MaritimeMuseum","NorthbankHomes0","NorthbankHomes1","NorthbankHomes2","IslandGrocer","IslandCinema","Aquarium","PromenadeCafe","NorthbankFront0","NorthbankFront1","NorthbankFront2","NorthbankFront3"],
	["BridgeCourtWest","BridgeCourtEast","BridgeQuayHouse","GatewayFlats","TransitHouse","MotorWorkshop","RoadsideSupplies","ServiceLodge","ParcelOffice","NorthFireStation","ServiceCafe","CanalHomesWest","CanalHomesEast","NorthGrocer","CycleWorkshop","GardenFlats","UnionApartments","CommunityHall","CornerPharmacy"],
	["PorchHouse","Duplex","ShingleHouse","CobraWorkshop","CourtyardHouse","BrickDuplex","TinRoofHouse","CornerBungalow"],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("V1 building atlas exporter refuses to run without --no-save")
		quit(2)
		return
	var make_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH))
	if make_result != OK:
		push_error("Could not create isolated atlas output: %s" % error_string(make_result))
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		push_error("Could not read V2 Harbor inventory")
		quit(2)
		return
	var exported := 0
	for raw_value in (parsed as Dictionary).get("harbor_buildings", []):
		var raw := raw_value as Dictionary
		if String(raw.get("id", "")) == "Garage":
			continue
		if await _export_building(raw):
			exported += 1
	print("V1_BUILDING_ATLAS exported=", exported)
	quit(0 if exported == 60 else 1)


func _export_building(data: Dictionary) -> bool:
	var building_id := String(data.get("id", ""))
	var source_size := data.get("size", [160.0, 160.0]) as Array
	var size := Vector2(float(source_size[0]), float(source_size[1]))
	var viewport := SubViewport.new()
	viewport.name = "Atlas_" + building_id
	viewport.size = Vector2i(ceili(size.x) + MARGIN * 2, ceili(size.y) + MARGIN * 2)
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var drawing
	if String(data.get("kind", "")) == "cobra_house":
		drawing = COBRA_RESIDENCE.new()
		drawing.name = building_id
		drawing.size = size
		drawing.variant = _cobra_variant(building_id)
		drawing.wall_color = Color(String(data.get("color", "#72594b")))
		drawing.position = Vector2(MARGIN, MARGIN)
	else:
		drawing = HOSPITAL_BUILDING.new() if building_id == "Clinic" else HARBOR_BUILDING.new()
		drawing.name = building_id
		drawing.footprint = size
		drawing.building_kind = String(data.get("kind", "office"))
		drawing.business_name = String(PROPER_NAMES.get(building_id, data.get("name", ""))).to_upper()
		drawing.accent = Color(String(data.get("color", "#e4b76c")))
		drawing.variant_seed = (_source_index(building_id) + 1) * 17
		drawing.entrance_north = bool(data.get("entrance_north", false))
		if building_id == "ExchangeTower": drawing.height_override = 128.0
		if building_id == "CivicTower": drawing.height_override = 95.0
		drawing.position = Vector2(MARGIN, MARGIN) + size * 0.5
	viewport.add_child(drawing)
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if building_id == "Laundry":
		# HarborBuilding hard-codes the category-only WASH / DRY label. Keep the
		# productive fascia and border but remove that forbidden descriptive text.
		image.fill_rect(Rect2i(MARGIN + int(size.x * 0.5) - 36, MARGIN + int(size.y * 0.5) + 11, 72, 11), Color("315d5d"))
		image.fill_rect(Rect2i(MARGIN + int(size.x * 0.5) - 35, MARGIN + int(size.y * 0.5) + 12, 70, 1), Color("a9c3af"))
		image.fill_rect(Rect2i(MARGIN + int(size.x * 0.5) - 35, MARGIN + int(size.y * 0.5) + 20, 70, 1), Color("a9c3af"))
	var result := image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUTPUT_PATH, building_id]))
	if result != OK:
		viewport.free()
		push_error("Could not export %s: %s" % [building_id, error_string(result)])
		return false
	print("V1_BUILDING_SOURCE ", building_id, " ", viewport.size)
	viewport.free()
	return true


func _source_index(building_id: String) -> int:
	for order_value in SOURCE_ORDERS:
		var order := order_value as Array
		var index := order.find(building_id)
		if index >= 0: return index
	return 0


func _cobra_variant(building_id: String) -> int:
	var variants := {
		"PorchHouse":0,"Duplex":1,"ShingleHouse":2,"CobraWorkshop":3,
		"CourtyardHouse":0,"BrickDuplex":1,"TinRoofHouse":2,"CornerBungalow":0,
	}
	return int(variants.get(building_id, 0))
