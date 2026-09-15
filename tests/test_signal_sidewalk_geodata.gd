extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var network = scene.get_node("RoadNetwork")
	var graph: Dictionary = network.get_graph_data()
	var curb: Array = network.get_signal_ground_surfaces(10.0)
	var sidewalk: Array = network.get_signal_ground_surfaces(84.0)
	var failures := 0
	var checked := 0
	var moved := 0
	for data in graph.junctions:
		if not data.get("signalized", false): continue
		var visual = load("res://geodata/roads/traffic/JunctionSignalVisual2D.gd").new()
		scene.add_child(visual)
		visual.global_position = network.to_global(data.position)
		visual.configure(StringName(data.id), data.radius, data.approaches)
		var before: Array = visual.get_signal_layout()
		visual.ground_source = network
		visual.curb_surfaces = curb
		visual.sidewalk_surfaces = sidewalk
		visual._rebuild_posts()
		for i in visual.signal_posts.size():
			var post = visual.signal_posts[i]
			checked += 1
			if post.position.distance_to(before[i].pole_base) > 0.1: moved += 1
			if not visual._foundation_on_sidewalk(post.position):
				failures += 1
				print("FAIL sidewalk ", data.id, " ", post.position)
		visual.queue_free()
	print("SIGNAL_SIDEWALK_GEODATA checked=", checked, " relocated=", moved, " failures=", failures)
	quit(0 if failures == 0 and checked > 0 else 1)
