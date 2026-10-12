extends SceneTree
## Patch root metadata only, preserving the baked exterior. Refuses to save if
## the geometry/material fingerprint changes. Backups are never overwritten.
const FIX = preload("res://tools/fleet_fixups/CabinMetadataFix.gd")
const BATCH = preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const DIR = "res://evidence/fleet-redesign-20261011/validation/cabin-metadata-fix/"

func _initialize() -> void: run.call_deferred()

func canonical(value: Variant) -> Variant:
	if value is Resource:
		var fields := {"class":value.get_class()}
		for property in value.get_property_list():
			if (int(property.usage)&PROPERTY_USAGE_STORAGE)==0: continue
			var key: String = property.name
			if key in ["resource_path","resource_scene_unique_id"]: continue
			fields[key]=canonical(value.get(key))
		return fields
	if value is Array:
		var result := []
		for entry in value: result.append(canonical(entry))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key]=canonical(value[key])
		return result
	return value

func exterior(model: Node3D) -> Dictionary:
	var values := []
	for node in model.find_children("*","",true,false):
		var entry := {"path":str(model.get_path_to(node)),"class":node.get_class()}
		for property in node.get_property_list():
			if (int(property.usage)&PROPERTY_USAGE_STORAGE)==0: continue
			var key: String = property.name
			if key in ["owner","unique_name_in_owner"]: continue
			entry[key]=canonical(node.get(key))
		values.append(entry)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(values))
	return {"sha256":hashing.finish().hex_encode(),"counts":BATCH.counts(model)}

func run() -> void:
	var report := {"method":"Only vehicle_interior_spec/cabin_metadata_revision root metadata; all descendant stored properties, mesh channels, transforms and material properties fingerprinted before/save/reload", "vehicles":{}}
	for id: String in FIX.SPECS:
		var path := "res://assets/fleet/redesigned/"+id+".scn"
		var model: Node3D = (ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var before := exterior(model)
		var file_before := FileAccess.get_sha256(path)
		var backup := DIR+id+".before.scn"
		if not FileAccess.file_exists(backup): DirAccess.copy_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(backup))
		FIX.apply(model,id)
		if exterior(model).sha256 != before.sha256:
			push_error("Cabin metadata changed exterior in memory: "+id); quit(2); return
		var status := BATCH.save_model(model,path)
		model.free()
		if status != OK: push_error("Cabin metadata save failed: "+id); quit(3); return
		var reread: Node3D = (ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var after := exterior(reread)
		var same: bool = before.sha256 == after.sha256
		report.vehicles[id]={"file_sha256_before":file_before,"file_sha256_after":FileAccess.get_sha256(path),"before":before,"after":after,"exterior_unchanged":same,"metadata":reread.get_meta("vehicle_interior_spec")}
		reread.free()
		print("CABIN_METADATA ",id," exterior_unchanged=",same," ",JSON.stringify(after.counts))
		if not same:
			FileAccess.open(DIR+"patch.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
			push_error("Serialized exterior differs: "+id); quit(4); return
	FileAccess.open(DIR+"patch.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit()
