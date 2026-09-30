extends SceneTree
## Lista os scripts com _process ativo na cena de jogo (contagem por script), para escolher o que ablar.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	for i in 300: await process_frame
	var counts := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(): stack.append(child)
		if node.is_processing() and node.get_script() != null:
			var path: String = (node.get_script() as Script).resource_path
			counts[path] = int(counts.get(path, 0)) + 1
	var rows := []
	for path in counts: rows.append([counts[path], path])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for row in rows: print("PROC ", row[0], " ", row[1])
	quit()
