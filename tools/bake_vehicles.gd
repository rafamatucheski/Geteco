extends SceneTree
## Run against V1; writes only isolated V2 snapshots of original geometry.
const CATALOG := preload("res://cars/VehicleCatalog.gd")
const OUTPUT := "res://assets/fleet/"
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func flatten(source: Node, destination: Node3D, transform: Transform3D) -> void:
	var current := transform
	if source is Node3D: current = transform * source.transform
	if source is MeshInstance3D:
		var mesh := MeshInstance3D.new()
		mesh.mesh = source.mesh
		mesh.material_override = source.material_override
		mesh.transform = current
		mesh.cast_shadow = source.cast_shadow
		for key in source.get_meta_list(): mesh.set_meta(key,source.get_meta(key))
		for i in source.get_surface_override_material_count(): mesh.set_surface_override_material(i,source.get_surface_override_material(i))
		destination.add_child(mesh)
		mesh.owner = destination
	for child in source.get_children(): flatten(child,destination,current)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var manifest := {}
	for id in CATALOG.VEHICLES:
		var spec: Dictionary = CATALOG.get_vehicle_spec(id).duplicate(true)
		var script: Script = load(spec.model_class)
		if script == null:
			failures.append(id+": missing model")
			continue
		var original: Node3D = script.new()
		root.add_child(original)
		var baked := Node3D.new()
		baked.name = "Vehicle"
		flatten(original,baked,Transform3D.IDENTITY)
		var bounds := AABB()
		var first := true
		for mesh in baked.get_children():
			var box: AABB = mesh.transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		var packed := PackedScene.new()
		var result := packed.pack(baked)
		if result == OK: result = ResourceSaver.save(packed,OUTPUT+id+".scn",ResourceSaver.FLAG_BUNDLE_RESOURCES)
		if result != OK: failures.append(id+": save "+str(result))
		var colors := []
		for color in spec.get("colors",[]): colors.append(color.to_html())
		spec.colors = colors
		spec["scene"] = "res://assets/fleet/"+id+".scn"
		spec["bounds_size"] = [bounds.size.x,bounds.size.y,bounds.size.z]
		spec["bounds_center"] = [bounds.get_center().x,bounds.get_center().y,bounds.get_center().z]
		spec["mesh_count"] = baked.get_child_count()
		manifest[id] = spec
		original.free()
		baked.free()
		print("FLEET ",id," meshes=",spec.mesh_count)
	var file := FileAccess.open(OUTPUT+"catalog.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"source":"cars/VehicleCatalog.gd","vehicles":manifest,"failures":failures},"\t"))
	file.close()
	print("FLEET_EXPORT count=",manifest.size()," failures=",failures)
	quit(0 if failures.is_empty() else 1)
