extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- INICIANDO DIAGNÓSTICO DE EXPLOSÃO E MORTE ---")
	var scene = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 10: await physics_frame
	
	var player = root.get_tree().get_first_node_in_group("player")
	print("Player encontrado: ", player != null)
	var car = root.get_tree().get_first_node_in_group("vehicle")
	print("Carro encontrado: ", car != null)
	
	var before_visible := 0
	var before_buildings := 0
	for node in root.find_children("*", "CanvasItem", true, false):
		if node is CanvasItem and node.is_visible_in_tree():
			before_visible += 1
	for b in root.find_children("*", "ProceduralBuilding", true, false):
		if b.is_visible_in_tree():
			before_buildings += 1
	print("CanvasItems visíveis antes: ", before_visible)
	print("Prédios visíveis antes: ", before_buildings)
	
	car.enter_vehicle(player)
	for i in 5: await physics_frame
	print("Jogador dirigindo: ", car.is_driven_by_player)
	
	print("Causando dano fatal no carro...")
	car.take_damage(200)
	print("Carro explodindo? ", car.is_exploding)
	
	print("Aguardando detonação...")
	for i in 250:
		await physics_frame
		if car.is_exploded:
			print("Carro explodiu no frame ", i)
			break
			
	for i in 10: await physics_frame
	
	print("Estado do jogador: is_dead=", player.is_dead, " visible=", player.visible)
	
	var after_visible := 0
	var after_buildings := 0
	var hidden_nodes: Array[String] = []
	for node in root.find_children("*", "CanvasItem", true, false):
		if node is CanvasItem and node.is_visible_in_tree():
			after_visible += 1
	for b in root.find_children("*", "ProceduralBuilding", true, false):
		if b.is_visible_in_tree():
			after_buildings += 1
		else:
			hidden_nodes.append(b.name + " (" + b.get_parent().name + ")")
			
	print("CanvasItems visíveis depois: ", after_visible)
	print("Prédios visíveis depois: ", after_buildings)
	if not hidden_nodes.is_empty():
		print("Prédios ocultos: ", hidden_nodes)
	
	var cam = root.get_viewport().get_camera_2d()
	if cam:
		print("Câmera ativa: ", cam.get_path(), " global_pos=", cam.global_position, " zoom=", cam.zoom, " enabled=", cam.enabled)
	else:
		print("NENHUMA CÂMERA 2D ATIVA!")
		
	print("Aguardando 2.5s (tela SE FODEU e respawn)...")
	for i in 160: await physics_frame
	
	print("Pós-respawn: Player pos=", player.global_position, " is_dead=", player.is_dead)
	cam = root.get_viewport().get_camera_2d()
	if cam:
		print("Câmera pós-respawn: ", cam.get_path(), " global_pos=", cam.global_position, " zoom=", cam.zoom)

	print("--- FIM DO DIAGNÓSTICO ---")
	quit(0)

