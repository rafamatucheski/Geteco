extends SceneTree

func _init() -> void:
	call_deferred("_find_nodes")

func _find_nodes() -> void:
	var main_scene = load("res://legacy/Main.tscn") as PackedScene
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	
	for i in 5:
		await process_frame
		
	var target = Vector2(870, 1260)
	print("=== SEARCHING NODES NEAR ", target, " ===")
	_scan_node(main_node, target)
	quit(0)

func _scan_node(node: Node, target: Vector2) -> void:
	if node is Node2D:
		var n2d = node as Node2D
		var d = n2d.global_position.distance_to(target)
		if d < 300.0:
			print("Node2D: ", n2d.get_path(), " pos=", n2d.global_position, " z=", n2d.z_index, " class=", n2d.get_class(), " script=", n2d.get_script())
			if n2d is Polygon2D:
				print("   Polygon2D polygon=", (n2d as Polygon2D).polygon, " color=", (n2d as Polygon2D).color)
			if n2d is ColorRect:
				print("   ColorRect rect=", (n2d as ColorRect).get_rect(), " color=", (n2d as ColorRect).color)
	for child in node.get_children():
		_scan_node(child, target)
