extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
 create_timer(120).timeout.connect(func(): quit(2))
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
 room.shop._on_action_pressed()
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
 cold.exposure_seconds=40
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
 if DisplayServer.get_name() != "headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("D:/geteco/clothing-shop-interior.png")
 manager._on_exit_door_requested(room.exit_door,player,&"",null,&"",entrance.destination_id)
 assert(player.global_position.distance_to(entrance.get_node("OutsideReturn").global_position)<1)
 assert(player.sprite_3d_display.scale.x <= 0.35, "Player scale must be restored upon exiting city clothing shop")
 assert(not player.has_meta("interior_movement_presentation"), "Movement presentation meta must be cleaned up")
 await world.get_node("ContinuousWorld").ensure_mountain()
 for i in 5: await process_frame
 assert(get_nodes_in_group("clothing_shop").size() >= 2)
 var mountain=world.get_node("ContinuousWorld").mountain
 var mountain_manager=mountain.interior_manager
 var mountain_room=mountain_manager._interiors[&"mountain_outfitters"]
 var mountain_door=mountain.get_node("MountainExpedition/SnowOutfitters/OutfittersEntrance")
 var stream=world.get_node("ContinuousWorld")
 player.global_position=mountain_door.global_position+Vector2(0,24)
 stream._update_region()
 stream._update_region()
 assert(not mountain_room.shop.visible and not mountain_room.shop.is_active)
 for layer in mountain.find_children("*","CanvasLayer",true,false):
  if layer is ClothingStore or layer is WeaponStore: assert(not layer.visible)
 assert(mountain_door.get_parent().get_node_or_null("ClothingEntrance")==null)
 mountain_manager._on_entrance_requested(mountain_door,player,mountain_door.destination_id,null,&"",mountain_door)
 assert(mountain_room.get_camera_rect().has_point(player.global_position))
 mountain_room.shop.open_store(player)
 stream._update_region()
 assert(mountain_room.shop.visible)
 assert(mountain_room.shop.selected_outfit_id=="dante_arctic")
 mountain_room.shop._on_action_pressed()
 assert(player.money==3200 and player.mountain_thermal_coat)
 var snapshot=player.serialize()
 player.apply_outfit("dante_classic")
 player.restore(snapshot)
 assert(player.current_outfit_id=="dante_arctic" and player.owned_outfits.get("dante_arctic",false))
 mountain_room.shop._select_outfit("dante_trench")
 player.money=100
 mountain_room.shop._on_action_pressed()
 assert(player.money==100 and player.current_outfit_id=="dante_arctic")
 mountain_room.shop.close_store()
 stream._update_region()
 assert(not mountain_room.shop.visible)
 var return_pos=mountain_manager._actor_returns[player]
 mountain_manager._on_exit_requested(mountain_room.exit_door,player,&"",null,&"",&"mountain_outfitters")
 assert(player.global_position.distance_to(return_pos)<1)
 assert(player.sprite_3d_display.scale.x <= 0.35, "Player scale must be restored upon exiting mountain clothing shop")
 assert(not player.has_meta("interior_movement_presentation"), "Movement presentation meta must be cleaned up")
 player.global_position=Vector2(1890,280)
 stream._update_region()
 player.global_position=mountain_door.global_position+Vector2(0,24)
 stream._update_region()
 assert(not mountain_room.shop.visible)
 print("CLOTHING_SHOPS PASS purchase equip protection city exit mountain entrance")
 world.queue_free()
 await process_frame
 quit()
