extends SceneTree
## A reconstrução parcial dos amassados (só o raio do registro que mudou) tem de dar a mesma
## malha que a reconstrução completa a partir do repouso, e o cache de arrays por malha não pode
## misturar carros do mesmo modelo.
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value: failures.append(label); push_error(label)

func _snapshot(car) -> Dictionary:
	var result := {}
	for entry in car.body_dents.parts:
		var mesh: Mesh = entry.node.mesh
		var surfaces: Array = []
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			surfaces.append([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL]])
		result[entry.node] = surfaces
	return result

func _max_difference(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for part in a:
		if not b.has(part): return INF
		for surface in a[part].size():
			for channel in 2:
				var left: PackedVector3Array = a[part][surface][channel]
				var right: PackedVector3Array = b[part][surface][channel]
				if left.size() != right.size(): return INF
				for index in left.size(): worst = maxf(worst, left[index].distance_to(right[index]))
	return worst

func run() -> void:
	for id in ["metro_hatch", "sport_coupe", "police_cruiser"]:
		var car := VEHICLE.new()
		car.archetype = id
		root.add_child(car)
		car.set_physics_process(false)
		var twin := VEHICLE.new()
		twin.archetype = id
		root.add_child(twin)
		twin.set_physics_process(false)
		# Frente, lateral, a mesma frente de novo (aprofunda) e traseira: parcial a cada passo.
		var hits := [Vector3(car.half_width * .65, .6, -car.half_length), Vector3(car.half_width, .55, 0),
			Vector3(car.half_width * .6, .6, -car.half_length), Vector3(-car.half_width * .5, .6, car.half_length)]
		for point in hits: car.receive_impact(18, point)
		var incremental := _snapshot(car)
		car.body_dents._rebuild()
		var full := _snapshot(car)
		var difference := _max_difference(incremental, full)
		check(difference < .00001, id + " parcial = completo (diferença " + str(difference) + ")")
		# O gêmeo usa a cópia em cache das mesmas malhas; uma batida só nele não toca o primeiro.
		twin.receive_impact(18, hits[1])
		check(_max_difference(_snapshot(car), full) < .00001, id + " gêmeo não altera o primeiro carro")
		twin.repair()
		car.repair()
		print("DENTS_INCREMENTAL ", id, " max_diff=", difference, " rebuild_us=", car.body_dents.rebuild_usec)
		car.queue_free()
		twin.queue_free()
		await process_frame
	print("BODY_DENTS_INCREMENTAL failures=", failures)
	quit(0 if failures.is_empty() else 1)
