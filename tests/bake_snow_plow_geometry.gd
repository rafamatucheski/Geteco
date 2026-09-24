extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/SnowPlowModel.gd"
const OUTPUT_PATH := "res://prototypes/living_cast/models/SnowPlowGeometry.scn"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	var script := load(MODEL_PATH) as Script
	if script == null:
		push_error("SnowPlow script failed to load")
		quit(1)
		return
	var model := script.new() as Node3D
	for child in model.get_children():
		model.remove_child(child)
		child.free()
	model.materials.clear()
	model.paint = null
	model._build_procedural_geometry()
	root.add_child(model)
	var rig := WHEEL_RIG.new()
	if not rig.mount(model):
		push_error("SnowPlow wheel rig failed during prepared geometry bake")
		quit(1)
		return
	var removed := BATCHER.batch_model(model)
	CACHE._flatten_warmup_wheels(model, rig)
	model.set_meta("vehicle_mesh_batched", true)
	var plain := Node3D.new()
	plain.name = "SnowPlowGeometry"
	plain.set_meta("format_version", 1)
	plain.set_meta("model_id", "snow_plow_truck")
	for metadata in model.get_meta_list():
		plain.set_meta(metadata, model.get_meta(metadata))
	var role_counts: Dictionary = {}
	for child in model.get_children():
		if not child is MeshInstance3D:
			continue
		var role := ""
		for material_role in model.materials:
			if model.materials[material_role] == (child as MeshInstance3D).material_override:
				role = String(material_role)
				break
		if role.is_empty():
			push_error("SnowPlow child %s has no material role" % child.name)
			model.free()
			plain.free()
			quit(1)
			return
		var copy := child.duplicate(0) as MeshInstance3D
		copy.set_meta("snow_plow_material_role", role)
		plain.add_child(copy)
		copy.owner = plain
		role_counts[role] = int(role_counts.get(role, 0)) + 1
	plain.set_meta("mesh_count", plain.get_child_count())
	plain.set_meta("material_role_counts", role_counts)
	plain.set_meta("visual_signature", 3643091624)
	plain.set_meta("triangle_count", 38642)
	var packed := PackedScene.new()
	var pack_error := packed.pack(plain)
	var save_error := ERR_CANT_CREATE
	if pack_error == OK:
		save_error = ResourceSaver.save(packed, OUTPUT_PATH)
	print("SNOW_PLOW_GEOMETRY_BAKE path=%s meshes=%d roles=%d removed=%d pack_error=%d save_error=%d" % [
		OUTPUT_PATH, plain.get_child_count(), role_counts.size(), removed, pack_error, save_error,
	])
	model.free()
	plain.free()
	quit(0 if pack_error == OK and save_error == OK else 1)
