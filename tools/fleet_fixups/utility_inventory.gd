extends SceneTree
const IDS := ["arctic_jeep","atlas_crew_pickup","beach_buggy","bravio_crew","courier_van","desert_jeep_4x4","dock_delivery_van","dune_buggy","lumber_pickup_4x4","nimbus_minivan","polar_van","ranch_pickup","ranch_single","sertao_trail_pickup","summit_suv","winter_suv_heavy"]
const FOLDER := "res://evidence/fleet-redesign-20261011/utility"
func _initialize() -> void:
	if FileAccess.file_exists(FOLDER.path_join("baseline.json")):
		print("UTILITY_BASELINE_ALREADY_SAVED ",FOLDER)
		quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var output := {}
	for id in IDS:
		var model := preload("res://runtime/FleetCatalog.gd").create(id)
		var row := {"spec":preload("res://runtime/FleetCatalog.gd").spec(id),"door":preload("res://data/catalogs/VehicleDoorSpecs.gd").row(id),"meshes":0,"triangles":0,"surfaces":0,"parts":[],"wheels":[]}
		for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if part.mesh == null: continue
			row.meshes += 1
			row.surfaces += part.mesh.get_surface_count()
			row.triangles += part.mesh.get_faces().size()/3
			var b: AABB = part.transform * part.get_aabb()
			var item := {"name":str(part.name),"min":[b.position.x,b.position.y,b.position.z],"size":[b.size.x,b.size.y,b.size.z],"tris":part.mesh.get_faces().size()/3}
			row.parts.append(item)
			if part.has_meta("wheel_center") and part.get_meta("wheel_spins",true):
				var c: Vector3 = part.get_meta("wheel_center")
				var key := [c.x,c.y,c.z]
				if not key in row.wheels: row.wheels.append(key)
		var pack := PackedScene.new()
		for child in model.find_children("*","",true,false): child.owner = model
		pack.pack(model)
		ResourceSaver.save(pack,FOLDER.path_join(id+"-before.scn"),ResourceSaver.FLAG_BUNDLE_RESOURCES)
		output[id] = row
		print(id," meshes=",row.meshes," tris=",row.triangles," wheels=",row.wheels)
		model.free()
	FileAccess.open(FOLDER.path_join("baseline.json"),FileAccess.WRITE).store_string(JSON.stringify(output,"\t"))
	quit()
