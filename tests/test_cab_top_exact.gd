extends SceneTree
## O _cab_top podado por caixa delimitadora tem de dar EXATAMENTE o mesmo resultado do
## laço completo antigo (todos os vértices) em toda a frota. Renderizado, sem --headless.
const VEHICLE = preload("res://scripts/Vehicle.gd")
const CATALOG = preload("res://runtime/FleetCatalog.gd")
const EQUIPMENT = preload("res://gameplay/VehicleEquipment.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()

## Cópia literal do algoritmo anterior, usada só como referência.
func reference(car: CharacterBody3D) -> Dictionary:
	var to_car := car.global_transform.affine_inverse()
	var points := PackedVector3Array()
	var front := INF
	for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or part.has_meta("wheel_center"): continue
		var into_car := to_car * part.global_transform
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null: continue
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var local := into_car * vertex
				points.append(local)
				front = minf(front, local.z)
	if points.is_empty(): return {}
	var cab_back := front + 2.2
	var roof := -INF
	for point in points:
		if point.z < cab_back: roof = maxf(roof, point.y)
	var edge := INF
	var width := 0.0
	for point in points:
		if point.z < cab_back and point.y > roof - .10:
			edge = minf(edge, point.z)
			width = maxf(width, absf(point.x))
	if not is_finite(edge) or width < .3: return {}
	return {"y": roof, "z": edge, "half": minf(width - .12, car.half_width * .8)}

func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	await process_frame
	var ids: Array = CATALOG.all().keys()
	var checked := 0
	for id in ids:
		var car := VEHICLE.new()
		car.archetype = str(id)
		car.vehicle_id = "cabtop_%s" % id
		host.add_child(car)
		car.place(Vector3(randf() * 200.0, 0.2, 500.0), randf() * TAU)
		if car.visual == null: car.queue_free(); continue
		var equipment = EQUIPMENT.new()
		equipment.car = car
		var fast: Dictionary = equipment._cab_top()
		var slow: Dictionary = reference(car)
		checked += 1
		var same := fast.size() == slow.size()
		if same:
			for key in fast: if not is_equal_approx(float(fast[key]), float(slow[key])): same = false
		print("CABTOP %s %-26s fast=%s" % ["PASS" if same else "FAIL", id, str(fast)])
		if not same: failures.append("%s fast=%s slow=%s" % [id, fast, slow])
		equipment.free()
		car.queue_free()
	print("CABTOP checked=%d failures=%d" % [checked, failures.size()])
	quit(1 if failures.size() > 0 or checked == 0 else 0)
