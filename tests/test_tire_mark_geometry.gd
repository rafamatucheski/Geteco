extends SceneTree
## Mesh-consumer contracts: world-space tread geometry, sampled normals, fade and cleanup.
const TIRES := preload("res://gameplay/vehicle_effects/VehicleTireEffects.gd")
const COLOR_EPSILON := 1.0 / 255.0 + 0.0001 # Mesh colors are stored as RGBA8.
var checks := 0
var failures: Array[String] = []

class Car extends CharacterBody3D:
	var handling := {"mass": 1.0}
	var half_width := 1.04
	var half_length := 2.3

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func mark(a: Vector3, b: Vector3, na: Vector3, nb: Vector3, kind: String, born: int, life: int, width: float, depth := 1.0) -> Dictionary:
	return {"a": a, "b": b, "na": na, "nb": nb, "kind": kind, "born": born, "life": life, "w": width, "depth": depth}

func check_color(actual: Color, rgb: Color, alpha_low: float, alpha_high: float, label: String) -> void:
	check(absf(actual.r-rgb.r) <= COLOR_EPSILON and absf(actual.g-rgb.g) <= COLOR_EPSILON
		and absf(actual.b-rgb.b) <= COLOR_EPSILON and actual.a >= alpha_low-COLOR_EPSILON
		and actual.a <= alpha_high+COLOR_EPSILON, label)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var car := Car.new()
	world.add_child(car)
	var tire := TIRES.new()
	tire.configure(car)
	car.add_child(tire)
	tire._redraw_marks()
	check(not is_instance_valid(tire.mark_mesh), "empty marks do not allocate a drawable")
	var now := Time.get_ticks_msec()
	tire.marks.assign([
		mark(Vector3.ZERO, Vector3(0,0,-2), Vector3.UP, Vector3.UP, "hard", now-5000, 10000, .1),
		mark(Vector3(5,0,0), Vector3(5,0,-2), Vector3(.6,.8,0), Vector3(-.6,.8,0), "dirt", now-7500, 30000, .2, 1.2),
		mark(Vector3(10,0,0), Vector3(10,0,-2), Vector3.UP, Vector3.UP, "snow", now-2500, 10000, .1),
		mark(Vector3(15,0,0), Vector3(15,0,-2), Vector3.UP, Vector3.UP, "grass", now-15000, 30000, .1, 1.35),
	])
	var began := Time.get_ticks_msec()
	tire._redraw_marks()
	var ended := Time.get_ticks_msec()
	check(tire.mark_mesh.mesh == tire.geometry and tire.mark_mesh.visible, "drawable consumes the populated mark mesh")
	check(tire.geometry.get_surface_count() == 1, "all marks share one surface")
	var arrays: Array = tire.geometry.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	check(vertices.size() == 24 and normals.size() == 24 and colors.size() == 24, "each segment supplies two complete triangles")
	var expected := PackedVector3Array([
		Vector3(-.1,.012,0), Vector3(-.1,.012,-2), Vector3(.1,.012,-2),
		Vector3(-.1,.012,0), Vector3(.1,.012,-2), Vector3(.1,.012,0),
		Vector3(4.8472,.1296,0), Vector3(4.8328,.1296,-2), Vector3(5.1528,.1296,-2),
		Vector3(4.8472,.1296,0), Vector3(5.1528,.1296,-2), Vector3(5.1672,-.1104,0),
	])
	for index in expected.size():
		check(vertices[index].distance_to(expected[index]) < .00001, "world-space corner and triangle order %d" % index)
	for index in 6:
		check(normals[index].distance_to(Vector3.UP) < .0001, "flat sampled normal %d" % index)
		var expected_normal := Vector3(.6,.8,0) if index in [0,3,5] else Vector3(-.6,.8,0)
		check(normals[index+6].distance_to(expected_normal) < .0001, "sloped sampled normal %d" % index)
	var kinds := ["hard", "dirt", "snow", "grass"]
	var tints := [Color(.035,.035,.03), Color(.15,.10,.07), Color(.38,.43,.44), Color(.13,.15,.06)]
	var amplitudes := [.48, .36*1.2, .38, .42*1.35]
	for segment in 4:
		var data: Dictionary = tire.marks[segment]
		var low: float = (1.0-float(ended-int(data.born))/float(data.life))*amplitudes[segment]
		var high: float = (1.0-float(began-int(data.born))/float(data.life))*amplitudes[segment]
		for vertex in 6:
			check_color(colors[segment*6+vertex], tints[segment], low, high, "%s sampled fade/color %d" % [kinds[segment],vertex])
	var mesh_transform: Transform3D = tire.mark_mesh.global_transform
	car.global_position = Vector3(30,3,10)
	car.rotation.y = .7
	check(tire.mark_mesh.global_transform.is_equal_approx(mesh_transform), "existing marks stay fixed when the car moves")
	for entry in tire.marks: entry.born = int(entry.born)-2000
	tire._redraw_marks()
	var older: Array = tire.geometry.surface_get_arrays(0)
	check(older[Mesh.ARRAY_VERTEX] == vertices, "fading does not move existing geometry")
	check((older[Mesh.ARRAY_COLOR] as PackedColorArray)[0].a < colors[0].a-.05, "age fades the mark without a new contact")
	check(tire.geometry.get_surface_count() == 1, "redraw replaces the surface without accumulating it")
	tire.marks[0].born = Time.get_ticks_msec()-int(tire.marks[0].life)-1
	tire._expire_marks()
	check(tire.marks.size() == 3 and tire.marks[0].kind == "dirt", "expired asphalt is removed while the longer-lived rut remains")
	for entry in tire.marks: entry.born = Time.get_ticks_msec()-int(entry.life)-1
	tire._expire_marks()
	tire._redraw_marks()
	check(tire.marks.is_empty() and not tire.mark_mesh.visible, "all expired marks leave no visible trail")
	tire.clear_all()
	for index in range(tire.MAX_MARK_SEGMENTS+12):
		tire._append_mark(0, {"point":Vector3(index*.1,0,0), "normal":Vector3.UP}, "hard")
	check(tire.marks.size() == tire.MAX_MARK_SEGMENTS, "contact insertion preserves the fixed segment budget")
	tire._redraw_marks()
	var full: Array = tire.geometry.surface_get_arrays(0)
	check((full[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == tire.MAX_MARK_SEGMENTS*6, "drawable respects the same bounded segment count")
	# Same fixed geometry for either mesh implementation. CPU method timing only:
	# this does not measure gameplay frame time or GPU completion.
	for iteration in 10: tire._redraw_marks()
	var redraw_began := Time.get_ticks_usec()
	for iteration in 100: tire._redraw_marks()
	var redraw_elapsed := Time.get_ticks_usec()-redraw_began
	print("TIRE_MARK_CPU ", JSON.stringify({"segments":tire.marks.size(), "redraws":100,
		"warmup_redraws":10, "elapsed_usec":redraw_elapsed, "mean_usec":float(redraw_elapsed)/100.0,
		"scope":"CPU method timing with fixed 320-segment geometry; not FPS or GPU timing"}))
	tire.clear_all()
	check(tire.marks.is_empty() and tire.geometry.get_surface_count() == 0 and not tire.mark_mesh.visible, "clear releases mesh surfaces and hides the drawable")
	var drawable: WeakRef = weakref(tire.mark_mesh)
	car.queue_free()
	await process_frame
	await process_frame
	check(drawable.get_ref() == null, "vehicle removal releases the world-aligned drawable")
	world.queue_free()
	await process_frame
	print("TIRE_MARK_GEOMETRY checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
