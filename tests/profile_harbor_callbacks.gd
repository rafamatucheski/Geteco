extends SceneTree

var idle_nodes: Array[Node] = []
var physics_nodes: Array[Node] = []
var totals := {}
func _init() -> void: call_deferred("run")
func collect(node: Node) -> void:
	if "physics" in OS.get_cmdline_user_args() and node.get_script() != null and node.is_physics_processing() and node.has_method("_physics_process"):
		physics_nodes.append(node)
		node.set_physics_process(false)
	if node.get_script() != null and node.is_processing() and node.has_method("_process"):
		idle_nodes.append(node)
		node.set_process(false)
	for child in node.get_children(): collect(child)
func run() -> void:
	var scene = load("res://district/harbor_preview/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 20: await physics_frame
	if "physics" in OS.get_cmdline_user_args():
		scene.get_node("PlayerCar").position = Vector2(700,425)
		scene.get_node("PlayerCar").rotation = 0
		scene._drive()
		Input.action_press("ui_up")
	else:
		scene._walk()
	collect(root)
	for controller in get_nodes_in_group("junction_traffic_controller"):
		print("GRAPH_SIGNATURE_CHARS %d" % String(controller.get("_graph_signature")).length())
	var sample_count := 600 if "physics" in OS.get_cmdline_user_args() else 120
	for frame in sample_count:
		await process_frame
		for node in physics_nodes:
			if not is_instance_valid(node): continue
			var before := Time.get_ticks_usec()
			node.call("_physics_process",1.0/60.0)
			var elapsed := Time.get_ticks_usec()-before
			var key := String(node.get_path()) + " physics"
			totals[key] = int(totals.get(key,0))+elapsed
			if elapsed > 20000: print("SLOW_CALLBACK frame=%d us=%d node=%s" % [frame,elapsed,key])
		for node in idle_nodes:
			if not is_instance_valid(node): continue
			var before := Time.get_ticks_usec()
			node.call("_process",1.0/60.0)
			var elapsed := Time.get_ticks_usec()-before
			var key := String(node.get_path())
			totals[key] = int(totals.get(key,0))+elapsed
			if elapsed > 20000: print("SLOW_CALLBACK frame=%d us=%d node=%s" % [frame,elapsed,key])
	var names := totals.keys()
	names.sort_custom(func(a,b): return totals[a] > totals[b])
	for name_value in names.slice(0,20): print("CALLBACK_COST %s avg_us=%.1f" % [name_value,totals[name_value]/float(sample_count)])
	Input.action_release("ui_up")
	scene.queue_free()
	await process_frame
	quit()
