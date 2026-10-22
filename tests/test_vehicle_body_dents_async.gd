extends SceneTree
## O amassado calculado no WorkerThreadPool (VehicleBodyDents._request_rebuild, 22/10) tem de chegar à
## mesma malha do caminho síncrono, inclusive com várias batidas no meio de um cálculo (a pendente vira
## parcial ou completa) e com conserto no meio (o resultado velho é descartado).
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DENTS := preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd")
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
		result[str(car.get_path_to(entry.node))] = surfaces
	return result

func _max_difference(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	if a.size() != b.size(): return INF
	for part in a:
		if not b.has(part): return INF
		for surface in a[part].size():
			for channel in 2:
				var left: PackedVector3Array = a[part][surface][channel]
				var right: PackedVector3Array = b[part][surface][channel]
				if left.size() != right.size(): return INF
				for index in left.size(): worst = maxf(worst, left[index].distance_to(right[index]))
	return worst

func _settle(car) -> bool:
	for frame in 600:
		if car.body_dents._task < 0 and car.body_dents._pending == null: return true
		await process_frame
	return false

func _car(id: String):
	var car := VEHICLE.new()
	car.archetype = id
	root.add_child(car)
	car.set_physics_process(false)
	return car

func run() -> void:
	DENTS.async_in_headless = true
	for id in ["metro_hatch", "sport_coupe", "police_cruiser"]:
		var reference = _car(id)
		var threaded = _car(id)
		var hits := [Vector3(reference.half_width * .65, .6, -reference.half_length), Vector3(reference.half_width, .55, 0),
			Vector3(reference.half_width * .6, .6, -reference.half_length), Vector3(-reference.half_width * .5, .6, reference.half_length)]
		# Referência: tudo síncrono.
		DENTS.async_enabled = false
		for point in hits: reference.receive_impact(18, point)
		var expected := _snapshot(reference)
		DENTS.async_enabled = true
		# Primeira batida sozinha, depois três no mesmo quadro (pendentes em cima do cálculo em voo).
		threaded.receive_impact(18, hits[0])
		check(threaded.body_dents._task >= 0, id + ": 1ª batida vai para o trabalhador")
		check(await _settle(threaded), id + ": cálculo termina")
		for index in range(1, hits.size()): threaded.receive_impact(18, hits[index])
		check(await _settle(threaded), id + ": pendentes terminam")
		var difference := _max_difference(_snapshot(threaded), expected)
		check(difference < .00001, id + ": assíncrono = síncrono (diferença " + str(difference) + ")")
		# Conserto com cálculo em voo: o resultado velho não pode voltar.
		threaded.receive_impact(18, hits[1] + Vector3(0, 0, .4))
		threaded.repair()
		check(await _settle(threaded), id + ": conserto com cálculo em voo termina")
		var pristine := true
		for entry in threaded.body_dents.parts: pristine = pristine and entry.node.mesh == entry.mesh
		check(threaded.body_dents.dents.is_empty() and pristine, id + ": conserto vence o cálculo em voo")
		print("DENTS_ASYNC ", id, " max_diff=", difference)
		reference.queue_free()
		threaded.queue_free()
		await process_frame
	DENTS.async_in_headless = false
	print("BODY_DENTS_ASYNC failures=", failures)
	quit(0 if failures.is_empty() else 1)
