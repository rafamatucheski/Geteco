extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	player.money = 3500
	var wardrobe: Dictionary = player.owned_outfits.duplicate()
	var shop := ClothingStore.new()
	world.add_child(shop)
	shop.open_store(player)
	assert(get_nodes_in_group("player").size() == 1, "preview must not register a second player")
	var actual_face = player.head_node.find_children("*","MeshInstance3D",true,false)
	var preview_face = shop.preview_3d.rig.head_node.find_children("*","MeshInstance3D",true,false)
	assert(actual_face.size() == preview_face.size() and actual_face.size() > 30, "preview uses the full production face and hair")
	for i in actual_face.size():
		assert(actual_face[i].mesh.get_aabb() == preview_face[i].mesh.get_aabb())
		assert(actual_face[i].transform == preview_face[i].transform)
	for id in OutfitCatalog.ORDER:
		shop._select_outfit(id)
		await process_frame
		assert(shop.preview_3d.rig.head_node.find_children("*","MeshInstance3D",true,false).size() == actual_face.size())
		assert(player.current_outfit_id == "dante_classic" and player.money == 3500)
		assert(player.owned_outfits == wardrobe)
	shop._select_outfit("dante_arctic")
	shop._on_action_pressed()
	assert(player.money == 1700 and player.current_outfit_id == "dante_arctic")
	assert(player.mat_black_jacket.albedo_color == shop.preview_3d.rig.mat_black_jacket.albedo_color)
	shop._on_action_pressed()
	assert(player.money == 1700)
	shop._select_outfit("dante_trench")
	shop._on_action_pressed()
	assert(player.money == 1700 and shop.notice_label.text == "Faltam $ 500.")
	shop._select_outfit("dante_classic")
	shop._on_action_pressed()
	assert(player.money == 1700 and not player.mountain_thermal_coat)
	shop.close_store()
	assert(shop.preview_3d.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	world.queue_free()
	await process_frame
	await create_timer(.25).timeout
	print("CLOTHING PREVIEW PASS: production Dante, all outfits, isolated fitting, purchase, funds and closed rendering")
	quit()
