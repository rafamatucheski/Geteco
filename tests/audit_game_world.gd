extends SceneTree
## O que o jogo real tem na árvore fora dos chunks da região (o editor não monta isso).
func _initialize() -> void: run.call_deferred()
func meshes(n: Node) -> int:
	var c := 1 if n is MeshInstance3D or n is MultiMeshInstance3D else 0
	for k in n.get_children(): c += meshes(k)
	return c
func run() -> void:
	var scene: Node = load("res://Main.tscn").instantiate()
	scene.set_meta("skip_arrival", true)
	root.add_child(scene)
	for i in 7200:
		await physics_frame
		if scene.session != null and scene.session.ready_for_play: break
	for i in 600: await physics_frame
	var rows := []
	for child in scene.get_children():
		if not child is Node3D: continue
		rows.append([meshes(child), str(child.name), (child.get_script().resource_path if child.get_script() else child.get_class()), child.global_position])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 60): print("AUD ", r[0], "  ", r[1], "  ", r[2], "  ", r[3])
	var region = scene.production.region
	print("REGION ", region.region_id, " chunks=", region.chunks.size())
	quit()
