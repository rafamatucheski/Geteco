extends SceneTree
## Directed contract for native 3D conversion of the productive V1 buildings.
## The offline source atlas is evidence only: it must never be mounted as a
## horizontal facade/roof projection at runtime.

const DATA_PATH := "res://world/regions/OriginalWorldData.json"
const ATLAS_ROOT := "res://assets/regions/source/world/harbor/building_atlas"
const SOURCE_MARGIN := 24
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const RETIRED_PROJECTION_PATH := "res://world/urban_detail/HarborV1BuildingProjection.gd"

var failures := 0


func check(value: bool, message: String) -> void:
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Harbor building source validator refuses to run without --no-save")
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	check(parsed is Dictionary, "Harbor inventory loads")
	if not parsed is Dictionary:
		quit(1)
		return
	var retired_projection_source:=FileAccess.get_file_as_string(RETIRED_PROJECTION_PATH)
	check("QuadMesh" not in retired_projection_source and "SHADING_MODE_UNSHADED" not in retired_projection_source,"no dormant 2D building projection fallback remains")
	var covered := 0
	for raw_value in (parsed as Dictionary).get("harbor_buildings", []):
		var raw := raw_value as Dictionary
		var building_id := String(raw.get("id", ""))
		if building_id == "Garage": continue
		var path := "%s/%s.png" % [ATLAS_ROOT, building_id]
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		var source_size := raw.get("size", [0.0, 0.0]) as Array
		check(image != null and not image.is_empty(), "%s has a productive V1 material" % building_id)
		if image != null and not image.is_empty():
			check(image.get_width() == int(source_size[0]) + SOURCE_MARGIN * 2, "%s preserves source width" % building_id)
			check(image.get_height() == int(source_size[1]) + SOURCE_MARGIN * 2, "%s preserves source depth" % building_id)
		var normalized := raw.duplicate()
		normalized.position = Vector3(float(raw.position[0]), 0.0, float(raw.position[1])) / 16.0
		normalized.size = Vector2(float(source_size[0]), float(source_size[1])) / 16.0
		var building := FACTORY.build_building(normalized)
		check(building != null, "%s native volume builds" % building_id)
		if building == null: continue
		root.add_child(building)
		FACTORY.finalize_building(building, normalized)
		await process_frame
		var projections := building.find_children("V1SourceProjection", "MeshInstance3D", true, false)
		var meshes:=building.find_children("*","MeshInstance3D",true,false)
		var elevations:={}
		var material_keys:={}
		for mesh_value in meshes:
			var mesh:=mesh_value as MeshInstance3D
			if mesh.mesh==null: continue
			var bounds:=mesh.transform*mesh.mesh.get_aabb()
			elevations[snappedf(bounds.get_center().y,.25)]=true
			if mesh.material_override!=null: material_keys[mesh.material_override.get_instance_id()]=true
		check(projections.is_empty(), "%s uses native 3D geometry instead of a 2D projection" % building_id)
		check(building.find_children("*", "SubViewport", true, false).is_empty(), "%s uses no runtime projection viewport" % building_id)
		check(not building.find_children("*", "StaticBody3D", true, false).is_empty(), "%s keeps independent 3D collision" % building_id)
		check(meshes.size()>=4,"%s has a composed 3D model rather than one extruded box"%building_id)
		check(elevations.size()>=2,"%s publishes distinct wall/roof or facade elevations"%building_id)
		check(material_keys.size()>=2,"%s preserves more than one authored finish"%building_id)
		if building_id=="FoundryTerraceWest":
			check(building.find_child("FanlightTransom",true,false)!=null,"Foundry west preserves its fanlight")
			check(building.find_child("SquareTransom",true,false)!=null,"Foundry west preserves its square transom")
			check(building.find_child("StoneRailCap",true,false)!=null,"Foundry west preserves its stone stoop rail")
		if building_id=="FoundryTerraceEast":
			check(building.find_child("V1Dormer",true,false)!=null,"Foundry east preserves its authored dormer")
			check(building.find_child("MilkCrate",true,false)!=null,"Foundry east preserves its milk crate")
		if building_id=="CornerDiner":
			check(building.find_child("BayLeft_Counter",true,false)!=null,"Anchor diner preserves a visible 3D counter")
			check(building.find_child("BayLeft_Pendant_0_Shade",true,false)!=null,"Anchor diner preserves a 3D pendant")
			check(building.find_child("AwningStripe_01",true,false)!=null,"Anchor diner preserves its striped awning")
		if building_id=="Laundry":
			var porthole:=building.find_child("WasherPortholeRing",true,false) as MeshInstance3D
			check(porthole!=null and porthole.mesh is CylinderMesh,"Laundry portholes are circular 3D drums")
		if projections.is_empty() and meshes.size()>=4 and elevations.size()>=2 and material_keys.size()>=2: covered += 1
		building.free()
		await process_frame
	check(covered == 60, "all 60 non-Maciota inventory buildings are composed native 3D models")
	print("HARBOR_BUILDING_SOURCE_FIDELITY covered=", covered, " failures=", failures)
	quit(1 if failures else 0)
