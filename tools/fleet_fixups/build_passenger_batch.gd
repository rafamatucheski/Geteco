extends SceneTree
## Offline passenger-car authoring. Production capture/accounting, not a test suite.
const IDS := ["aurora_executive","beach_cabriolet","cobra_v8","metro_hatch","monaliza","muscle_classic","nordic_estate","orbita_micro","porto_rosso","sedan_classic","sport_estate","station_wagon","surf_woody_wagon","taxi_yellow","union_sedan","vale_crossover","vertice_midengine"]
const EVIDENCE := "res://evidence/fleet-redesign-20261011/passenger"
const OUTPUT := "res://assets/fleet/redesigned"

func _initialize() -> void: run.call_deferred()

func metrics(model: Node3D) -> Dictionary:
	var result := {"meshes":0,"surfaces":0,"triangles":0,"parts":[]}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		result.meshes += 1
		result.surfaces += part.mesh.get_surface_count()
		result.triangles += part.mesh.get_faces().size()/3
		var bounds := part.transform * part.mesh.get_aabb()
		var metadata := {}
		for key in part.get_meta_list(): metadata[str(key)] = str(part.get_meta(key))
		var materials := []
		for i in part.mesh.get_surface_count():
			var material := part.get_active_material(i)
			materials.append({"name":material.resource_name if material else "", "color":material.albedo_color.to_html() if material is StandardMaterial3D else "", "emissive":material.emission_enabled if material is StandardMaterial3D else false})
		result.parts.append({"name":str(part.name),"mesh":part.mesh.get_class(),"triangles":part.mesh.get_faces().size()/3,"position":[bounds.position.x,bounds.position.y,bounds.position.z],"size":[bounds.size.x,bounds.size.y,bounds.size.z],"metadata":metadata,"materials":materials})
	return result

func save_model(model: Node3D, destination: String) -> Error:
	for child in model.find_children("*","",true,false): child.owner = model
	var packed := PackedScene.new()
	var status := packed.pack(model)
	if status == OK: status = ResourceSaver.save(packed,destination)
	return status

func write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE+"/original"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var inventory := {}
	var results: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE+"/production.json")) if FileAccess.file_exists(EVIDENCE+"/production.json") else {}
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="): only=arg.trim_prefix("--id=")
	for id: String in IDS:
		if not only.is_empty() and id!=only: continue
		var source_path := EVIDENCE+"/original/"+id+".scn"
		var model: Node3D
		# User explicitly rejected the imported Meshy citycar. The new Metro is
		# rebuilt from its clean authored hatch source; the snapshot stays intact.
		if id=="metro_hatch" and "--inventory" not in OS.get_cmdline_user_args():
			model=(load("res://assets/fleet/metro_hatch.scn") as PackedScene).instantiate()
			preload("res://runtime/VehicleFinish.gd").decorate(id,model)
			preload("res://runtime/VehicleTwoTone.gd").decorate(id,model)
			preload("res://runtime/FleetSpeedPass.gd").decorate(id,model)
			model.set_meta("replaces_rejected_meshy_citycar",true)
		elif id=="taxi_yellow" and "--inventory" not in OS.get_cmdline_user_args():
			model=(load("res://assets/fleet/taxi_yellow.scn") as PackedScene).instantiate()
			preload("res://runtime/VehicleFinish.gd").decorate(id,model)
			preload("res://runtime/VehicleTwoTone.gd").decorate(id,model)
			preload("res://runtime/TaxiLivery.gd").decorate(model)
			preload("res://runtime/FleetSpeedPass.gd").decorate(id,model)
		elif ResourceLoader.exists(source_path): model = (load(source_path) as PackedScene).instantiate()
		else:
			model = preload("res://runtime/FleetCatalog.gd").create(id)
			var status := save_model(model,source_path)
			if status != OK:
				push_error("Passenger source snapshot failed: "+id)
				quit(2)
				return
		inventory[id] = metrics(model)
		inventory[id]["spec"] = preload("res://runtime/FleetCatalog.gd").spec(id)
		if id=="metro_hatch" and "--inventory" not in OS.get_cmdline_user_args():
			inventory[id]["spec"] = inventory[id].spec.duplicate(true)
			inventory[id].spec["bounds_size"]=[1.95999991893768,1.56993126869202,3.86999988555908]
			inventory[id].spec["bounds_center"]=[0.0,.804965615272522,.0149999856948853]
		print("PASSENGER_SOURCE ",id," ",inventory[id].meshes,"/",inventory[id].surfaces,"/",inventory[id].triangles)
		if "--inventory" not in OS.get_cmdline_user_args():
			preload("res://tools/fleet_fixups/PassengerDesign.gd").new().apply(model,id,inventory[id].spec)
			var baked := preload("res://tools/fleet_fixups/FleetBatchMesh.gd").bake(model,.3 if id=="metro_hatch" else .2,id)
			preload("res://tools/fleet_fixups/CabinMetadataFix.gd").apply(baked,id)
			var destination := OUTPUT+"/"+id+".scn"
			var status := save_model(baked,destination)
			results[id] = metrics(baked)
			results[id]["destination"] = destination
			results[id]["source"] = "res://assets/fleet/metro_hatch.scn" if id=="metro_hatch" else ("res://assets/fleet/taxi_yellow.scn" if id=="taxi_yellow" else source_path)
			results[id]["original_snapshot"] = source_path
			results[id]["save_error"] = status
			results[id]["before"] = {"meshes":inventory[id].meshes,"surfaces":inventory[id].surfaces,"triangles":inventory[id].triangles}
			if id=="metro_hatch": results[id]["rejected_meshy_baseline"]={"meshes":5,"surfaces":5,"triangles":9894}
			results[id]["notes"] = "Offline production accounting; no runtime tests or FPS benchmark. User rejected Meshy citycar; this replaces it using the clean legacy hatch, retaining its dimensions and four independent wheel pivots. Meshy historical baseline was 5 meshes/5 surfaces/9894 triangles." if id=="metro_hatch" else "Offline production accounting; no runtime tests or FPS benchmark."
			print("PASSENGER_BAKED ",id," ",results[id].meshes,"/",results[id].surfaces,"/",results[id].triangles," save=",status)
			baked.free()
		model.free()
	if not FileAccess.file_exists(EVIDENCE+"/original-inventory.json"): write_json(EVIDENCE+"/original-inventory.json",inventory)
	if not results.is_empty(): write_json(EVIDENCE+"/production.json",results)
	quit()
