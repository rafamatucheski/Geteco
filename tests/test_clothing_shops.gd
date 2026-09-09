extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
 root.size=Vector2i(1280,720)
 root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen",true)
 root.get_node("CampaignState").set_campaign_flag(&"harbor_call_complete",true)
 var world=load("res://world/harbor/HarborGame.tscn").instantiate()
 root.add_child(world)
 current_scene=world
 while not world.gameplay_ready: await process_frame
 await process_frame
 await process_frame
 var manager=world.get_node("Interiors")
 var entrance=world.get_node("District/NorthFrontage3/ClothingEntrance")
 var room=manager.get_node("InteriorSpaces/ClothingRoom0")
 var player=world.get_node("Player")
 manager._on_exterior_destination_requested(entrance,player,entrance.destination_id,null,&"",room,room.spawn_point)
 assert(room.get_camera_rect().has_point(player.global_position))
 player.money=5000
 room.shop.open_store(player)
 room.shop._select_outfit("dante_arctic")
 room.shop._on_action_pressed()
 assert(player.current_outfit_id=="dante_arctic")
 assert(player.money==3200)
 room.shop._select_outfit("dante_classic")
 room.shop._on_action_pressed()
 assert(not player.mountain_thermal_coat)
 assert(player.money==3200)
 room.shop.close_store()
 var cold=preload("res://world/mountain_pass/ColdSurvivalController.gd").new()
 cold.force_cold_active=true
 cold.outfit_protection=.8
 cold.current_temperature=100
 cold._update_temperature(1)
 var protected_temp=cold.current_temperature
 cold.outfit_protection=0
 cold.current_temperature=100
 cold._update_temperature(1)
 assert(cold.current_temperature<protected_temp)
 cold.free()
 var camera=Camera2D.new()
 world.add_child(camera)
 camera.position=room.global_position
 camera.zoom=Vector2(1.5,1.5)
 camera.make_current()
 for layer in world.find_children("","CanvasLayer",true,false): layer.hide()
 for i in 5: await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("D:/geteco/clothing-shop-interior.png")
 manager._on_exit_door_requested(room.exit_door,player,&"",null,&"",entrance.destination_id)
 assert(player.global_position.distance_to(entrance.get_node("OutsideReturn").global_position)<1)
 await world.get_node("ContinuousWorld").ensure_mountain()
 for i in 5: await process_frame
 assert(get_nodes_in_group("clothing_shop").size()==2)
 var mountain_room=manager.get_node("InteriorSpaces/ClothingRoom1")
 var mountain_door=get_nodes_in_group("clothing_shop")[1]
 manager._on_exterior_destination_requested(mountain_door,player,mountain_door.destination_id,null,&"",mountain_room,mountain_room.spawn_point)
 assert(mountain_room.get_camera_rect().has_point(player.global_position))
 manager._on_exit_door_requested(mountain_room.exit_door,player,&"",null,&"",mountain_door.destination_id)
 assert(player.global_position.distance_to(mountain_door.get_node("OutsideReturn").global_position)<1)
 print("CLOTHING_SHOPS PASS purchase equip protection city exit mountain entrance")
 world.queue_free()
 await process_frame
 quit()
