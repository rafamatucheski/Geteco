extends SceneTree
## GETECO-PERF-03A — diagnóstico direto: imprime posição/forma real de
## Container01 e dos RoadPost* citados na falha de test_south_port.gd, sem
## nenhuma lógica de teste, para comparar árvore "antes" e "depois".
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1500, 1400)
	root.content_scale_size = root.size
	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	while not scene.world_build_ready: await process_frame
	for i in 25: await physics_frame
	var port := scene.get_node("SouthPort")
	print("port_ready=", port.get("port_ready"), " sites=", port.sites.size(), " model_views=", port.model_views.size())
	var c1 := port.get_node_or_null("Container01")
	if c1:
		print("Container01 global_position=", c1.global_position, " shape_size=", (c1.get_child(0) as CollisionShape2D).shape.size)
	for name in ["RoadPost222", "RoadPost223", "RoadPost253", "RoadPost257", "RoadPost271", "RoadPost272"]:
		var node := scene.find_children(name, "StaticBody2D", true, false)
		for n in node:
			print(name, " global_position=", n.global_position, " path=", n.get_path())
	print("total_static_bodies=", scene.find_children("*", "StaticBody2D", true, false).size())
	print("total_road_posts=", scene.find_children("RoadPost*", "StaticBody2D", true, false).size())
	quit(0)
