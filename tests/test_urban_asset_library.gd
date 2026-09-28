extends SceneTree
const LIB := preload("res://addons/geteco_world_editor/WorldAssetLibrary.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
const SKYLINE := preload("res://world/urban_detail/UrbanSkylineCatalog.gd")
const LOWRISE := preload("res://world/urban_detail/UrbanLowriseCatalog.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func passive(node: Node) -> bool:
	if node.is_processing() or node.is_physics_processing() or node is Light3D or node is SubViewport: return false
	for child in node.get_children():
		if not passive(child): return false
	return true

func hit(point: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collision_mask = 1
	return not root.world_3d.direct_space_state.intersect_point(query).is_empty()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Urban asset window checks require rendering: dummy MultiMesh transforms are not readable")
		quit(2)
		return
	var rows: Array[Dictionary] = []
	var doc := DATA.empty_document()
	for entry in LIB.build({}):
		if entry.type != "building" or entry.row.model not in SKYLINE.TYPES+LOWRISE.TYPES: continue
		var row: Dictionary = entry.row.duplicate(true)
		row.id = "new/urban_asset_test_"+str(rows.size())
		row.position = [2500.0+rows.size()*48.0,2500.0]
		row.rotation = 37.0
		check(DATA.validate_entity(row).is_empty(),"Valid library preset: "+entry.label)
		rows.append(row)
		doc.regions.harbor[row.id] = row
	check(rows.size() == 20,"Twelve tower and eight lowrise presets are available")
	check(DATA.BUILDING_TYPES.size() == DATA.BUILDING_LABELS.size(),"Model selector has a label for every model")
	var path := "user://urban_assets_test_"+str(OS.get_process_id())+".json"
	check(DATA.save_document(doc,"",path).is_empty(),"Save isolated asset document")
	var loaded := DATA.read_document(path)
	check(loaded.error.is_empty() and loaded.document.regions.harbor.size() == rows.size(),"Reload all models and dimensions from disk")
	Engine.set_meta("geteco_world_edit_document",loaded.document)
	var region := REGION.build_region("harbor",Vector3(2500,0,2500))
	root.add_child(region)
	region.set_process(false)
	for row in rows: region._ensure_chunk(Vector2i(floori(row.position[0]/64.0),floori(row.position[1]/64.0)))
	await physics_frame
	await process_frame
	var all_buildings: Array[Node] = region.find_children("*","Node3D",true,false).filter(func(node): return str(node.get_meta("editor_id","")).begins_with("new/urban_asset_test_"))
	check(all_buildings.size() == rows.size(),"Production streaming mounts every saved asset once")
	for building in all_buildings:
		var row: Dictionary = loaded.document.regions.harbor[building.get_meta("editor_id")]
		check(is_equal_approx(building.height,row.height) and building.building_size.is_equal_approx(DATA.point(row.size)),"Dimensions survive production: "+row.model)
		check(is_equal_approx(building.rotation.y,deg_to_rad(37.0)),"Rotation survives production: "+row.model)
		check(passive(building),"Static asset has no loops or lights: "+row.model)
		check(building.find_children("*","MultiMeshInstance3D",true,false).size() <= 8,"Facade material batching stays bounded: "+row.model)
		var glazed_sides := 0
		for batch in building.find_children("*","MultiMeshInstance3D",true,false):
			if batch.material_override not in [UrbanMaterials.glass_window(),UrbanMaterials.glass_window_lit(true),UrbanMaterials.glass_window_lit(false)]: continue
			for index in batch.multimesh.instance_count:
				var transform: Transform3D = batch.multimesh.get_instance_transform(index)
				var pane_size := transform.basis.get_scale()
				if is_equal_approx(pane_size.x,.135): glazed_sides |= 1 if transform.origin.x > 0 else 2
				if is_equal_approx(pane_size.z,.135): glazed_sides |= 4 if transform.origin.z > 0 else 8
		check(glazed_sides == 15,"Windows exist on front, back and both sides: "+row.model)
		var solids := building.find_children("*","CollisionShape3D",true,false)
		check(not solids.is_empty(),"Asset owns collision: "+row.model)
		for solid in solids:
			if solid.shape is BoxShape3D:
				check(hit(solid.global_position),"Physics hits rotated solid: "+row.model)
		var actor := CharacterBody3D.new()
		actor.collision_mask = 1
		var capsule := CollisionShape3D.new()
		capsule.shape = CapsuleShape3D.new()
		capsule.shape.radius = .3
		capsule.shape.height = 1.8
		actor.add_child(capsule)
		root.add_child(actor)
		var front: float = building.building_size.y*.5
		if row.model == "urban_slab": front = building.building_size.y*.36
		var from: Transform3D = building.global_transform
		from.origin = building.to_global(Vector3(0,.95,front+2.0))
		check(actor.test_move(from,building.global_basis*Vector3(0,0,-4)),"Walking capsule cannot pass through facade: "+row.model)
		actor.free()
		if row.model == "urban_twin":
			check(not hit(building.to_global(Vector3(0,building.height*.6,0))),"Gap between twin towers is not filled by collision")
		if row.model == "urban_setback":
			check(not hit(building.to_global(Vector3(building.building_size.x*.46,building.height*.92,0))),"Setback sky is not filled by collision")
	region.release_chunks()
	await process_frame
	check(region.find_children("*","MultiMeshInstance3D",true,false).is_empty(),"Facade batches unload with chunks")
	for row in rows: region._ensure_chunk(Vector2i(floori(row.position[0]/64.0),floori(row.position[1]/64.0)))
	check(region.find_children("*","Node3D",true,false).filter(func(node): return str(node.get_meta("editor_id","")).begins_with("new/urban_asset_test_")).size() == rows.size(),"Assets reconstruct once on streaming reload")
	region.free()
	Engine.remove_meta("geteco_world_edit_document")
	DirAccess.remove_absolute(path)
	await process_frame
	print("URBAN_ASSET_LIBRARY checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
