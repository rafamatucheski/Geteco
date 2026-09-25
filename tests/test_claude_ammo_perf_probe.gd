extends SceneTree
## Atribuição de CPU da montagem da Ammu-Nation (sem Main, sem FPS). Compara a
## montagem dentro da árvore (como AmmunationModel._ready faz) com montagem
## destacada + inclusão única, e mede a inclusão na árvore separadamente.
const ART := preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd")

func _initialize() -> void: run.call_deferred()

func count(node: Node) -> Dictionary:
	var result := {"nodes":0, "meshes":0}
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		result.nodes += 1
		if current is MeshInstance3D: result.meshes += 1
		stack.append_array(current.get_children())
	return result

func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	for variant in [false, true]:
		for visit in 3:
			var in_tree := Node3D.new()
			host.add_child(in_tree)
			var t0 := Time.get_ticks_usec()
			ART.room(in_tree, variant)
			var in_tree_ms := (Time.get_ticks_usec() - t0) / 1000.0
			var stats := count(in_tree)
			in_tree.free()
			await process_frame
			var detached := Node3D.new()
			t0 = Time.get_ticks_usec()
			ART.room(detached, variant)
			var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
			t0 = Time.get_ticks_usec()
			host.add_child(detached)
			var enter_ms := (Time.get_ticks_usec() - t0) / 1000.0
			t0 = Time.get_ticks_usec()
			detached.free()
			var free_ms := (Time.get_ticks_usec() - t0) / 1000.0
			await process_frame
			print("AMMO_PERF_PROBE ", JSON.stringify({"mountain":variant, "visit":visit + 1, "in_tree_ms":in_tree_ms, "detached_build_ms":build_ms, "enter_tree_ms":enter_ms, "free_ms":free_ms, "nodes":stats.nodes, "meshes":stats.meshes, "renderer":RenderingServer.get_current_rendering_driver_name()}))
	quit(0)
