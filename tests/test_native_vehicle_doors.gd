extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var scripts: Array[String] = ["res://prototypes/living_cast/CoupeDamageModel.gd"]
	for spec in VehicleCatalog.VEHICLES.values():
		var path: String = spec.get("model_class","")
		if not path.is_empty() and not scripts.has(path): scripts.append(path)
	var doors: Array[Node3D] = []
	for path in scripts:
		var model: Node3D = load(path).new()
		holder.add_child(model)
		var door := preload("res://prototypes/living_cast/VehicleDoor3D.gd").new()
		model.add_child(door)
		var start := Time.get_ticks_usec()
		door.configure(model)
		print("DOOR ",path.get_file()," triangles=",door.extracted_triangles," build_ms=",(Time.get_ticks_usec()-start)/1000.0)
		if door.extracted_triangles==0: failures.append("No door geometry: "+path)
		door.play()
		doors.append(door)
	await create_timer(0.35).timeout
	for door in doors:
		if door.hinge==null or absf(door.hinge.rotation.y)<0.5: failures.append("Door did not physically open")
	await create_timer(0.75).timeout
	for door in doors:
		if door.hinge!=null and not is_zero_approx(door.hinge.rotation.y): failures.append("Door did not close")
		var model := door.get_parent()
		model.repair()
		for source in model.originals:
			if source.mesh != model.originals[source]: failures.append("Repair did not preserve split body mesh")
	print("NATIVE DOOR FAILURES: ",failures)
	holder.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
