extends SceneTree
const INDEX := preload("res://characters/pedestrians/PedestrianNeighborhood.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	var actors: Array[Node2D] = []
	# Inclui coordenadas negativas e ambos os lados das bordas de célula.
	for y in range(-10, 11):
		for x in range(-10, 11):
			var actor := Node2D.new()
			actor.position = Vector2(x * 31 - 1, y * 29 + 1)
			stage.add_child(actor)
			actor.add_to_group("authored_sidewalk_pedestrian")
			actors.append(actor)
	var scanned := 0
	for actor in actors:
		var nearby := INDEX.neighbors(actor, 64.0)
		scanned += nearby.size()
		var expected: Array = []
		var actual: Array = []
		for other in actors:
			if actor.position.distance_to(other.position) < 64.0: expected.append(other)
		for other in nearby:
			if actor.position.distance_to(other.position) < 64.0: actual.append(other)
		check(actual == expected, "Índice deve preservar vizinhos e ordem da busca completa.")
	check(scanned < actors.size() * actors.size() / 2, "Índice deve reduzir candidatos.")
	# Um objeto pode sair da árvore entre duas consultas do mesmo tick.
	var removed: Node2D = actors.pop_back()
	removed.free()
	var pedestrian := preload("res://characters/pedestrians/AuthoredSidewalkPedestrian.gd").new()
	check(not pedestrian._social_neighbor(removed), "Vizinho em cache já liberado deve ser rejeitado sem erro de argumento.")
	pedestrian.free()
	check(not INDEX.neighbors(actors[-1], 64.0).has(removed), "Consulta não deve devolver objeto removido.")
	actors[0].position = actors[-1].position
	await physics_frame
	await process_frame
	check(INDEX.neighbors(actors[-1], 64.0).has(actors[0]), "Movimento entre células deve atualizar no tick seguinte.")
	print("NEIGHBORHOOD_RESULT failures=%d candidates=%d brute_force=%d" % [failures, scanned, 441*441])
	stage.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
