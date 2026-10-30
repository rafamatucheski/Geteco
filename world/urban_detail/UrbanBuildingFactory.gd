extends RefCounted
class_name UrbanBuildingFactory

## Central factory for native 3D urban buildings in Geteco V2.
## Compatible with NativeRegion building data records.
## Reuses authored 3D models where they exist, and reconstructs 2D procedurals into high-detail 3D geometry.

const RESIDENCE_MODEL_PATH := "res://assets/regions/source/world/harbor/residences/ResidenceExterior3D.gd"
const HOSPITAL_MODEL_PATH := "res://assets/regions/source/world/harbor/hospital/HarborHospitalModel3D.gd"
const AMMUNATION_MODEL_PATH := "res://assets/regions/source/guns/ammunation/AmmunationFacade3D.gd"
const CEMETERY_HOUSE_MODEL_PATH := "res://assets/regions/source/world/harbor/cemetery/CemeteryHouseExterior3D.gd"
const LANDMARK_FRONTAGE := preload("res://world/urban_detail/UrbanLandmarkFrontage3D.gd")
const PORT_BOSS_EXTERIOR := preload("res://world/urban_detail/PortBossGarageExterior3D.gd")
const HARBOR_MANHOLE_EXTERIOR := preload("res://world/urban_detail/HarborManholeExterior3D.gd")
const SEWER_NETWORK := preload("res://world/places/sewers/SewerNetwork.gd")
const V1_PROFILE := preload("res://world/urban_detail/HarborV1BuildingProfile.gd")
const SKYLINE_BUILDING := preload("res://world/urban_detail/UrbanSkylineBuilding.gd")
const LOWRISE_BUILDING := preload("res://world/urban_detail/UrbanLowriseBuilding.gd")
const BUILDING_BATCH := preload("res://world/urban_detail/HarborBuildingBatch.gd")
const BUILDING_BAKE := preload("res://assets/buildings/baked/BuildingBakeCatalog.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
static var baked_enabled := OS.get_environment("GETECO_BAKED_BUILDINGS") != "0"
## Cenas assadas (~1,35 MB cada) eram lidas com load() síncrono na primeira vez que
## o prédio entrava no streaming: base release de 15/10, rota sobrados, quadros de
## 80-116 ms com stream.harbor.record.building de NorthbankFront3 (79,6 ms),
## UnionApartments (89,8) e TransitHouse (58,9), todos escritórios assados. O primeiro
## prédio montado (sob a cortina) pede todas em threads; cada montagem seguinte só
## recolhe as prontas no cache do catálogo. Se uma ainda não terminou, o load() do
## catálogo espera a mesma tarefa: nunca pior que antes. Custo: ~20 MB de RAM retidos.
static var _bake_pending: Array[String] = []
static var _bake_requested := false
const V1_HEIGHT_OVERRIDES := {
	# HarborEastDistrict assigns these two silhouettes after instantiation.
	# Keep their different skyline heights when converting 2D source pixels to metres.
	"ExchangeTower": 128.0 / 16.0,
	"CivicTower": 95.0 / 16.0,
}

static func resolved_height(data: Dictionary) -> float:
	var normalized := data.duplicate()
	var id := str(data.get("id",""))
	if not normalized.has("variant_seed"): normalized.variant_seed = V1_PROFILE.variant_seed_for_id(id)
	if not normalized.has("height_override") and V1_HEIGHT_OVERRIDES.has(id): normalized.height_override = V1_HEIGHT_OVERRIDES[id]
	return UrbanBuildingBase.resolved_height(normalized)

static func extract_position(data: Dictionary) -> Vector3:
	if data.has("position"):
		var p = data["position"]
		if p is Vector3:
			return p
		elif p is Array and p.size() >= 2:
			return Vector3(float(p[0]) * (1.0 / 16.0), 0.0, float(p[1]) * (1.0 / 16.0))
	if data.has("exterior_position"):
		var ep = data["exterior_position"]
		if ep is Vector3:
			return ep
		elif ep is Array and ep.size() >= 2:
			return Vector3(float(ep[0]) * (1.0 / 16.0), 0.0, float(ep[1]) * (1.0 / 16.0))
	return Vector3.ZERO

static func extract_size(data: Dictionary) -> Vector2:
	if data.has("size"):
		var s = data["size"]
		if s is Vector2:
			return s
		elif s is Array and s.size() >= 2:
			return Vector2(float(s[0]) * (1.0 / 16.0), float(s[1]) * (1.0 / 16.0))
	return Vector2(10.0, 10.0)

static func _prefetch_baked() -> void:
	if not baked_enabled: return
	if not _bake_requested:
		_bake_requested = true
		var manifest_path: String = BUILDING_BAKE.OUTPUT + "/manifest.tres"
		if not ResourceLoader.exists(manifest_path): return
		var manifest_resource := load(manifest_path) as Resource
		if manifest_resource == null: return
		var manifest: Dictionary = manifest_resource.get_meta("building_manifest", {})
		# Mesma regra do catálogo: no editor, fonte alterada invalida as cenas e ele não as usa.
		var stamp: String = BUILDING_BAKE.source_stamp()
		if not stamp.is_empty() and manifest.get("source_stamp", "") != stamp: return
		for entry in manifest.get("variants", {}).values():
			var path := str(entry.get("scene", ""))
			if path.is_empty() or path in _bake_pending or BUILDING_BAKE._scenes.has(path) or not ResourceLoader.exists(path): continue
			if ResourceLoader.load_threaded_request(path, "PackedScene") == OK: _bake_pending.append(path)
		return
	for index in range(_bake_pending.size() - 1, -1, -1):
		var path := _bake_pending[index]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
		_bake_pending.remove_at(index)
		if status != ResourceLoader.THREAD_LOAD_LOADED: continue
		# Sempre recolhe a tarefa (libera o registro do carregador), mesmo se o catálogo já a usou.
		var scene := ResourceLoader.load_threaded_get(path) as PackedScene
		if scene != null and not BUILDING_BAKE._scenes.has(path): BUILDING_BAKE._scenes[path] = scene

static func build_building(data: Dictionary) -> Node3D:
	_prefetch_baked()
	var building_id := str(data.get("id", ""))
	var building_kind := str(data.get("kind", data.get("service", "")))
	var point: Vector3 = extract_position(data)
	var size: Vector2 = extract_size(data)
	size.x = PaintedHarborHouses.footprint_width(building_id, size.x)
	
	# Store normalized coordinates back into data dictionary for downstream consumers
	var norm_data: Dictionary = data.duplicate()
	norm_data["position"] = point
	norm_data["size"] = size
	if not norm_data.has("variant_seed"):
		norm_data["variant_seed"] = V1_PROFILE.variant_seed_for_id(building_id)
	if not norm_data.has("height_override") and V1_HEIGHT_OVERRIDES.has(building_id):
		norm_data["height_override"] = V1_HEIGHT_OVERRIDES[building_id]
	
	# 1. Maciota's Garage is mounted as a complete primary place by Root / Catalog
	if building_id == "Garage" or building_id == "maciota_garage":
		return null

	if building_id == "port_boss_garage":
		var port_boss := PORT_BOSS_EXTERIOR.new()
		port_boss.name = building_id
		port_boss.setup(norm_data)
		port_boss.position = point
		port_boss.set_meta("_urban_data", norm_data)
		port_boss.ready.connect(func(): finalize_building(port_boss, norm_data))
		return port_boss

	if SEWER_NETWORK.is_manhole(building_id):
		var manhole := HARBOR_MANHOLE_EXTERIOR.new()
		manhole.name = building_id
		manhole.setup(norm_data)
		manhole.position = point
		manhole.rotation.y = float(norm_data.get("editor_rotation", 0.0))
		manhole.set_meta("_urban_data", norm_data)
		manhole.ready.connect(func(): finalize_building(manhole, norm_data))
		return manhole
	
	# 2. Existing Authored 3D Models (mesh construction in _ready)
	if building_id in ["Clinic", "harbor_hospital"] or building_kind == "hospital":
		return _build_hospital_facade(norm_data, point)
	
	if building_id in ["NorthFrontage2", "harbor_ammunation"] or building_kind == "weapons":
		return _build_ammunation_facade(norm_data, point)
	
	if building_id in ["CanalHomesWest", "canal_north"]:
		return _build_residence_facade(norm_data, point, 2)
	
	if building_id == "westgate_garden":
		return _build_residence_facade(norm_data, point, 0)
	
	if building_id == "quayside_house":
		return _build_residence_facade(norm_data, point, 1)
	
	if building_id == "cemetery_keeper" or building_kind == "cemetery":
		return _build_cemetery_facade(norm_data, point)
	
	if building_kind == "residence":
		var variant: int = int(norm_data.get("variant", 0))
		return _build_residence_facade(norm_data, point, variant)
	
	# 3. Native 3D Reconstructions for 2D Procedural Typologies
	var building: UrbanBuildingBase = null

	# Productive V1 landmarks whose positions and accesses already match the V2
	# catalog. Keep their authored identity instead of the generic kind model.
	if building_id in ["NorthFrontage0", "NorthFrontage3", "NorthFrontage4"]:
		building = LANDMARK_FRONTAGE.new()
	else:
		match building_kind:
			"house_gable", "house_duplex", "warehouse_sawtooth", "warehouse_loading":
				building = LOWRISE_BUILDING.new()

			"urban_setback", "urban_twin", "urban_slab", "urban_deco", "urban_infill", "urban_podium":
				building = SKYLINE_BUILDING.new()

			"brownstone", "rowhouse", "rowhouse_terrace":
				building = UrbanBrownstoneBuilding.new()
		
			"office":
				# Um arquivo ausente ou uma variação editada ainda não assada usa o caminho original.
				if baked_enabled and PaintedHarborHouses.style_for(building_id, building_kind).is_empty(): building = BUILDING_BAKE.create(norm_data)
				if building == null: building = UrbanCommercialBuilding.new()
		
			"corner_shop", "shop", "commercial_laundromat", "warehouse_shop", "bank_branch":
				building = UrbanShopfrontBuilding.new()
		
			"warehouse", "artisan_workshop":
				building = UrbanIndustrialBuilding.new()
		
			"fire_station", "police_precinct":
				building = UrbanServiceBuilding.new()
		
			"garage":
				# Northgate Motor Workshop has an open drive-in bay
				building = UrbanServiceBuilding.new()
		
			"cobra_house":
				building = UrbanCobraHouse.new()
		
			"l_shaped_block":
				building = UrbanLShapedBlock.new()
		
			_:
				building = UrbanBuildingBase.new()
	
	building.name = building_id
	building.setup(norm_data)
	building.position = point
	building.set_meta("_urban_data", norm_data)
	building.ready.connect(func(): finalize_building(building, norm_data))
	return building

## Synchronously mounts building into the chunk and performs post-tree-entry finalization.
## Spans por sub-passo (30/10): `stream.harbor.record.building` de 20-31 ms (Clinic, CanalHomesWest,
## prédios do editor de mundo) e `record.original_facade` de 18-25 ms (quayside_house, sewer_market)
## não diziam se o custo era montar o nó, a geometria do _ready ou a colisão do acabamento.
## "mount" inclui _ready e o finalize que o sinal ready dispara; "finalize"/"collision" são as partes dele.
static func populate_chunk(chunk: Node3D, data: Dictionary) -> Node3D:
	var span := STALL_WORK.begin()
	var building := build_building(data)
	STALL_WORK.finish_slow("stream.building.setup", span, 2000)
	if building != null:
		span = STALL_WORK.begin()
		chunk.add_child(building)
		STALL_WORK.finish_slow("stream.building.mount", span, 2000, building if building.is_inside_tree() else null)
		finalize_building(building, data)
	return building

## Post-mount finalization: executes after child meshes have been constructed in _ready().
## Generates trimesh collisions on layer 1, opens access doors, and sets proper name signage.
static func finalize_building(building: Node3D, data: Dictionary = {}) -> void:
	if building == null:
		return
	if building.get_meta("_urban_finalized", false):
		return
	
	if data.is_empty() and building.has_meta("_urban_data"):
		data = building.get_meta("_urban_data")
	
	building.set_meta("_urban_finalized", true)
	var finalize_span := STALL_WORK.begin()
	var trace_source: Node = building if building.is_inside_tree() else null
	
	# 1. Door opening adjustments on authored models
	if building.has_method("set_public_door_amount"):
		building.set_public_door_amount(1.0)
	if building.has_method("set_door_amount"):
		building.set_door_amount(1.0)
	# The sewer hatch starts closed; its opening belongs to FullSession's entry.
	if building.has_method("set_open_amount") and building.get_script() != HARBOR_MANHOLE_EXTERIOR and data.get("place_id", "") not in ["harbor_ammunation", "harbor_police"]:
		building.set_open_amount(1.0)
	if building.has_method("set_door_open"):
		building.set_door_open(true)
	var door_node = building.get("door") if "door" in building else null
	if door_node is Node3D:
		door_node.rotation.y = -1.3
	
	# 2. Collision and layer setup for authored meshes created in _ready()
	var collision_span := STALL_WORK.begin()
	for mesh: MeshInstance3D in building.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 1
		# Procedural exteriors already own native box solids in their Collision root.
		if not building is UrbanBuildingBase: _create_mesh_collision_safe(mesh)
	STALL_WORK.finish_slow("stream.building.collision", collision_span, 2000, trace_source)
	
	# 3. Clean facade signage (proper name only)
	_apply_proper_name_to_labels(building, data)
	BUILDING_BATCH.schedule(building)
	STALL_WORK.finish_slow("stream.building.finalize", finalize_span, 2000, trace_source)

# --- Helpers for Reused 3D Models ---

static func _build_hospital_facade(data: Dictionary, point: Vector3) -> Node3D:
	if not ResourceLoader.exists(HOSPITAL_MODEL_PATH):
		return null
	var model_script = load(HOSPITAL_MODEL_PATH)
	var art: Node3D = model_script.new()
	art.public_walkup_enabled = true
	art.name = str(data.get("id", "HarborHospital"))
	art.position = point
	art.set_meta("_urban_data", data)
	art.ready.connect(func(): finalize_building(art, data))
	return art

static func _build_ammunation_facade(data: Dictionary, point: Vector3) -> Node3D:
	if not ResourceLoader.exists(AMMUNATION_MODEL_PATH):
		return null
	var model_script = load(AMMUNATION_MODEL_PATH)
	var art: Node3D = model_script.new()
	art.name = str(data.get("id", "AmmunationFacade"))
	art.position = point
	# The reused authored facade is 8.7 x 4.7 m, while NorthFrontage2's V1
	# parcel is 230 x 180 px. Keeping the raw model scale produced a tiny kiosk
	# in the middle of the block; fit the proven facade to its authored parcel.
	var authored_size: Vector2 = extract_size(data)
	art.scale = Vector3(maxf(1.0,authored_size.x/8.7),1.0,maxf(1.0,authored_size.y/4.7))
	art.set_meta("_urban_data", data)
	art.ready.connect(func(): finalize_building(art, data))
	return art

static func _build_residence_facade(data: Dictionary, point: Vector3, variant: int) -> Node3D:
	if not ResourceLoader.exists(RESIDENCE_MODEL_PATH):
		return null
	var model_script = load(RESIDENCE_MODEL_PATH)
	var art: Node3D = model_script.new()
	art.name = str(data.get("id", "ResidenceFacade"))
	art.position = point
	if "variant_index" in art:
		art.variant_index = variant
	art.set_meta("_urban_data", data)
	art.ready.connect(func(): finalize_building(art, data))
	return art

static func _build_cemetery_facade(data: Dictionary, point: Vector3) -> Node3D:
	if not ResourceLoader.exists(CEMETERY_HOUSE_MODEL_PATH):
		return null
	var model_script = load(CEMETERY_HOUSE_MODEL_PATH)
	var art: Node3D = model_script.new()
	art.name = str(data.get("id", "CemeteryHouse"))
	art.position = point
	art.set_meta("_urban_data", data)
	art.ready.connect(func(): finalize_building(art, data))
	return art

static func _apply_proper_name_to_labels(root: Node3D, data: Dictionary) -> void:
	var b_id := str(data.get("id", root.name))
	var raw_name := str(data.get("name", data.get("original_name", "")))
	# Building id wins so catalog service labels cannot reintroduce categories
	# such as "Fuel" over the canonical proper-name-only facade policy.
	var proper := UrbanSignage.extract_proper_name(b_id, raw_name)
	
	for label: Label3D in root.find_children("*", "Label3D", true, false):
		var text := label.text
		# Remove timetable/warning/descriptive notices from exterior facades per AGENTS.md
		if "NÃO ENTRE" in text or "06h" in text or "HORÁRIO" in text or "HORARIO" in text:
			label.visible = false
			label.text = ""
			continue
		if not proper.is_empty():
			label.text = proper

static func _create_mesh_collision_safe(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null:
		return
	for child in mesh.get_children():
		if child is StaticBody3D:
			child.collision_layer = 1
			child.collision_mask = 0
			return
	
	var bounds: AABB = mesh.mesh.get_aabb()
	var center: Vector3 = mesh.position + bounds.get_center()
	if center.y > 2.8 or bounds.size.y < 0.35:
		return
	if mesh.get_meta("interior_solid_id", "") != "" or (bounds.size.x > 2.0 and bounds.size.z > 2.0):
		mesh.create_trimesh_collision()
		for child in mesh.get_children():
			if child is StaticBody3D:
				child.collision_layer = 1
				child.collision_mask = 0

## Transit pose must come from the sampled V1 lane/Arrival adapter, not STOP_DEFS anchors.
## Geometry is already metric; do not apply world /16 scale to the model itself.
static func populate_transit(chunk: Node3D, id: String, position: Vector3, station_type: int, orientation: float = 0.0) -> Node3D:
	var station = preload("res://world/urban_detail/UrbanTransitStation3D.gd").new()
	station.name = id
	station.station_type = station_type
	station.orientation_angle = orientation
	station.position = position
	station.set_meta("source_id","world/harbor/HarborArrivalStop.gd" if station_type==2 else "world/harbor/urban_transit/UrbanTransit.gd")
	chunk.add_child(station)
	return station
