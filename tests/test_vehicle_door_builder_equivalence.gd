extends SceneTree
## Geometria exata de antes/depois mais tempos locais finitos de CPU. Os tempos headless
## medem só o montador; não certificam o FPS de jogo renderizado.
const BEFORE := preload("res://tests/fixtures/VehicleDoorBuilderBeforeHeart.gd")
const AFTER := preload("res://gameplay/VehicleDoorBuilder.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const SPECS := preload("res://data/catalogs/VehicleDoorSpecs.gd")
var checks := 0
var failures: Array[String] = []
var reports: Array[Dictionary] = []
var stage: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func build(builder: Script, visual: Node3D, spec: Dictionary, budget := 1 << 40) -> Dictionary:
	var began := Time.get_ticks_usec()
	var job = builder.begin(visual, spec, float(spec.get("x", -1.0)))
	var maximum_calls: int = 2 + job.parts.size() * 3
	for part: MeshInstance3D in job.parts:
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			maximum_calls += 4 + ceili(float(count) / 48.0)
	var calls := 0
	var largest := 0
	while not job.finished:
		var step_began := Time.get_ticks_usec()
		builder.step(job, budget)
		largest = maxi(largest, Time.get_ticks_usec() - step_began)
		calls += 1
		if calls > maximum_calls:
			check(false, "Builder did not finish its finite part list")
			break
	return {"result": job.result, "elapsed_usec": Time.get_ticks_usec() - began,
		"largest_step_usec": largest, "calls": calls, "job": job}

func compare_results(before, after, label: String) -> void:
	check(before.skin == after.skin and before.cut_parts == after.cut_parts and before.triangles == after.triangles, label + ": support and triangle counts match")
	check(before.moved_parts == after.moved_parts, label + ": the same complete parts move into the door")
	for side in [-1, 1]:
		for kind in ["leaf", "inner"]:
			var expected: Dictionary = before.get(kind)[side]
			var actual: Dictionary = after.get(kind)[side]
			check(expected.keys() == actual.keys(), label + ": material group order matches")
			for material in expected:
				if not actual.has(material): continue
				var a: Dictionary = expected[material]
				var b: Dictionary = actual[material]
				check(b.pos is PackedVector3Array and b.nrm is PackedVector3Array and b.uv is PackedVector2Array and b.col is PackedColorArray, label + ": final public arrays remain packed")
				check(a == b, label + ": every position, normal, UV, color and surface key matches exactly")
	check(before.swaps.size() == after.swaps.size(), label + ": shell replacement count matches")
	for index in mini(before.swaps.size(), after.swaps.size()):
		var a: Array = before.swaps[index]
		var b: Array = after.swaps[index]
		check(a[0] == b[0] and a[1] == b[1], label + ": replacement targets the same original shell")
		var old_mesh: ArrayMesh = a[2]
		var new_mesh: ArrayMesh = b[2]
		check(old_mesh.get_surface_count() == new_mesh.get_surface_count(), label + ": replacement surface count matches")
		for surface in mini(old_mesh.get_surface_count(), new_mesh.get_surface_count()):
			check(old_mesh.surface_get_arrays(surface) == new_mesh.surface_get_arrays(surface), label + ": replacement geometry and indices match exactly")
			check(old_mesh.surface_get_material(surface) == new_mesh.surface_get_material(surface), label + ": replacement preserves material identity")

func median(values: Array) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	return float(ordered[int(ordered.size() * .5)])

func time_case(visual: Node3D, spec: Dictionary, label: String) -> void:
	# Cinco pares finitos; alterna a ordem depois que as duas implementações aqueceram.
	build(BEFORE, visual, spec)
	build(AFTER, visual, spec)
	var old_times: Array = []
	var new_times: Array = []
	var old_steps: Array = []
	var new_steps: Array = []
	for round in 5:
		var old_row: Dictionary
		var new_row: Dictionary
		if round % 2 == 0:
			old_row = build(BEFORE, visual, spec, 1000)
			new_row = build(AFTER, visual, spec, 1000)
		else:
			new_row = build(AFTER, visual, spec, 1000)
			old_row = build(BEFORE, visual, spec, 1000)
		compare_results(old_row.result, new_row.result, label + " timing %d" % round)
		old_times.append(old_row.elapsed_usec)
		new_times.append(new_row.elapsed_usec)
		old_steps.append(old_row.largest_step_usec)
		new_steps.append(new_row.largest_step_usec)
	reports.append({"case": label, "pairs": 5, "scope": "local_builder_cpu_not_game_fps", "before_median_usec": median(old_times), "after_median_usec": median(new_times), "before_largest_step_median_usec": median(old_steps), "after_largest_step_median_usec": median(new_steps), "before_usec": old_times, "after_usec": new_times})

func high_polygon_model() -> Node3D:
	var visual := Node3D.new()
	var part := MeshInstance3D.new()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 4,000 independent door polygons stress accumulation of a single group.
	for y in 20:
		for z in 100:
			var a := Vector3(1.0, .2 + y * .025, -.2 + z * .009)
			var b := a + Vector3(0, .025, 0)
			var c := a + Vector3(0, .025, .009)
			var d := a + Vector3(0, 0, .009)
			for vertex in [a, b, c, a, c, d]:
				tool.set_normal(Vector3.RIGHT)
				tool.set_uv(Vector2(vertex.z, vertex.y))
				tool.set_color(Color(.7, .3, .1))
				tool.add_vertex(vertex)
	part.mesh = tool.commit()
	visual.add_child(part)
	stage.add_child(visual)
	return visual

func source_lifetime_cases() -> void:
	for removed in [false, true]:
		var visual: Node3D = FLEET.create("police_cruiser")
		stage.add_child(visual)
		var job = AFTER.begin(visual, SPECS.row("police_cruiser"), float(SPECS.row("police_cruiser").x))
		for attempt in 100:
			AFTER.step(job, 0)
			if not job.work.is_empty() and int(job.work.get("triangle", 0)) > 0: break
		check(not job.work.is_empty() and int(job.work.get("triangle", 0)) > 0, "Lifetime case pauses inside a partly processed source")
		if job.work.is_empty():
			visual.free()
			continue
		var part: MeshInstance3D = job.work.part
		var source: Mesh = job.work.mesh
		var replacement := ArrayMesh.new()
		if removed:
			part.free()
		else:
			for surface in source.get_surface_count():
				replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface))
			part.mesh = replacement
		check(AFTER.step(job, 1 << 40) and job.finished, "Lifetime changes do not leave the builder pending")
		job.result.apply()
		if not removed: check(part.mesh == replacement, "Completion never overwrites a shell replaced between batches")
		visual.free()

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var models := 0
	for id in FLEET.all():
		var spec: Dictionary = SPECS.row(str(id))
		if spec.is_empty() or str(id) == "sport_coupe": continue
		var visual: Node3D = FLEET.create(str(id))
		if visual == null:
			check(false, str(id) + ": fleet model exists")
			continue
		stage.add_child(visual)
		var old_row := build(BEFORE, visual, spec)
		var new_row := build(AFTER, visual, spec)
		compare_results(old_row.result, new_row.result, str(id))
		var incremental := build(AFTER, visual, spec, 0)
		compare_results(old_row.result, incremental.result, str(id) + " incremental")
		check(incremental.calls >= AFTER._parts(visual).size(), str(id) + ": zero budget progresses through the finite mesh work")
		check(AFTER.step(incremental.job, 0), str(id) + ": completed jobs remain idempotent")
		if str(id) in ["police_cruiser", "police_transport", "rescue_pumper", "armored_van"]:
			time_case(visual, spec, str(id))
		visual.free()
		models += 1
		await process_frame
	var high_poly := high_polygon_model()
	time_case(high_poly, {"zf": -.3, "zr": .8, "sill": .1, "belt": .8, "top": 1.0, "x": 1.0}, "4000_door_polygons")
	high_poly.free()
	source_lifetime_cases()
	var output := "res://evidence/heart-performance-20261011/door-builder-granular-equivalence.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "models": models, "timings": reports, "scope": "Exact builder result equivalence and finite CPU timing; no rendered FPS conclusion."}, "\t"))
	file.close()
	stage.free()
	print("VEHICLE_DOOR_BUILDER_EQUIVALENCE checks=%d failures=%d models=%d timings=%s" % [checks, failures.size(), models, JSON.stringify(reports)])
	quit(0 if failures.is_empty() else 1)
