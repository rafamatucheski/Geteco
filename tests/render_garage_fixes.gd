extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene = load("res://Main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)
	
	for i in range(15):
		await process_frame

	var player = main.get_node_or_null("Player")
	var dim = main.get_node_or_null("DistrictInteriors") as DistrictInteriorManager

	# 1. Teleportar player para a garagem através do router oficial
	var entrance = dim.get_node_or_null("WorldEntrances/CommonGarageEntrance") as BuildingEntrance
	var garage = dim.get_node_or_null("InteriorSpaces/CommonGarageInterior") as CentralGarageInterior
	if player and entrance:
		dim.router._on_destination_requested(entrance, player, &"garage_interior_spawn", null, &"")
		player.global_position = garage.global_position + Vector2(0, 180)
			
	for i in range(15):
		await process_frame
		
	var viewport = root.get_viewport()
	var img1 = viewport.get_texture().get_image()
	img1.save_png("res://tests/garage_door_fixed_view.png")
	print("SAVED: res://tests/garage_door_fixed_view.png")

	# 2. Visão dos NPCs na garagem (Lounge do Jäger e Oficina do Tito)
	if player and garage:
		player.global_position = garage.global_position + Vector2(0, -140)
	for i in range(15):
		await process_frame
		
	var img2 = viewport.get_texture().get_image()
	img2.save_png("res://tests/garage_npcs_view.png")
	print("SAVED: res://tests/garage_npcs_view.png")

	# 3. Visão do exterior após sair da garagem
	if player and garage:
		dim.router._on_destination_requested(garage.exit_door, player, &"garage_exterior_return", null, &"")
	for i in range(15):
		await process_frame

	var img3 = viewport.get_texture().get_image()
	img3.save_png("res://tests/garage_exterior_exit_view.png")
	print("SAVED: res://tests/garage_exterior_exit_view.png")

	quit(0)
