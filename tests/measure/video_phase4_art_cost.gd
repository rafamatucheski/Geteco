extends SceneTree
## CPU-only attribution using an in-memory instrumented copy of the source.
## Does not edit product art or substitute the GPU / Main benchmark.
const SOURCE := "res://assets/regions/source/guns/ammunation/AmmunationArt.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var source := FileAccess.get_file_as_string(SOURCE).replace("\r\n", "\n")
	var instrumented := source.replace("static func box(root:", "static var probe_box_usec := 0\nstatic var probe_bevel_usec := 0\nstatic var probe_arsenal_usec := 0\nstatic var probe_box_calls := 0\nstatic var probe_bevel_calls := 0\n\nstatic func _probe_box_impl(root:")
	instrumented = instrumented.replace("static func bevel_box(", "static func _probe_bevel_impl(")
	var box_args := "root, size, pos, color, unique_material" if source.contains("unique_material := false") else "root, size, pos, color"
	instrumented += "\nstatic func box(root: Node3D, size: Vector3, pos: Vector3, color: Color, unique_material := false) -> MeshInstance3D:\n\tvar started := Time.get_ticks_usec()\n\tvar result := _probe_box_impl(" + box_args + ")\n\tprobe_box_usec += Time.get_ticks_usec()-started\n\tprobe_box_calls += 1\n\treturn result\n\nstatic func bevel_box(size: Vector3) -> ArrayMesh:\n\tvar started := Time.get_ticks_usec()\n\tvar result := _probe_bevel_impl(size)\n\tprobe_bevel_usec += Time.get_ticks_usec()-started\n\tprobe_bevel_calls += 1\n\treturn result\n"
	instrumented = instrumented.replace("\troot.set_meta(\"weapon_muzzle\", ARSENAL.build(root,id))", "\tvar arsenal_started := Time.get_ticks_usec()\n\troot.set_meta(\"weapon_muzzle\", ARSENAL.build(root,id))\n\tprobe_arsenal_usec += Time.get_ticks_usec()-arsenal_started")
	instrumented += "\nstatic func probe_reset() -> void:\n\tprobe_box_usec=0\n\tprobe_bevel_usec=0\n\tprobe_arsenal_usec=0\n\tprobe_box_calls=0\n\tprobe_bevel_calls=0\n\nstatic func probe_stats() -> Dictionary:\n\treturn {\"box_ms\":probe_box_usec/1000.0,\"bevel_ms\":probe_bevel_usec/1000.0,\"arsenal_ms\":probe_arsenal_usec/1000.0,\"box_calls\":probe_box_calls,\"bevel_calls\":probe_bevel_calls}\n"
	var measured := GDScript.new()
	measured.source_code = instrumented
	if measured.reload() != OK:
		push_error("In-memory attribution script failed to compile")
		quit(1)
		return
	for index in 2:
		var model := Node3D.new()
		root.add_child(model)
		measured.probe_reset()
		var started := Time.get_ticks_usec()
		measured.room(model, false)
		var elapsed := (Time.get_ticks_usec()-started)/1000.0
		var stats: Dictionary = measured.probe_stats()
		stats["total_room_ms"] = elapsed
		stats["visit"] = index+1
		stats["source_hash"] = FileAccess.get_sha256(SOURCE)
		stats["room_meshes"] = model.find_children("*", "MeshInstance3D", true, false).size()
		print("ART_CPU_ATTRIBUTION ", JSON.stringify(stats))
		model.free()
		await process_frame
	quit(0)
