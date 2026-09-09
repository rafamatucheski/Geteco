extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
 root.size=Vector2i(1280,720)
 root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen",true)
 root.get_node("CampaignState").set_campaign_flag(&"harbor_call_complete",true)
 var world=load("res://district/harbor_preview/HarborGame.tscn").instantiate()
 root.add_child(world)
 current_scene=world
 while not world.gameplay_ready: await process_frame
 await process_frame
 await process_frame
 var manager=world.get_node("Interiors")
 var room=manager.get_node("InteriorSpaces/BankInterior")
 assert(room.vault.get_child_count()>10,"Finished vault door parts are attached to animated hinge")
 var player=world.get_node("Player")
 player.set_physics_process(false)
 player.active_weapon_id="fists"
 player.position=room.global_position+Vector2(0,90)
 room.set_process(false)
 for guard in room.guards: guard.set_physics_process(false)
 room._process(.1)
 assert(not room.armed_warning and not room.alarm_started)
 player.active_weapon_id="pistol"
 room._process(.1)
 assert(room.armed_warning and not room.alarm_started)
 player.position=room.spawn_point.global_position
 await physics_frame
 for waypoint in [Vector2(-1,3),Vector2(-1,0),Vector2(0,0)]:
  var collision=player.move_and_collide(room.to_global(room.project_floor(waypoint))-player.global_position)
  if collision: print("BANK_ROUTE_BLOCK ",waypoint," ",collision.get_collider().get_path()," ",player.position)
  assert(collision==null,"Playable route around clients stays clear")
 var ray=PhysicsRayQueryParameters2D.create(room.to_global(room.vault_position),room.to_global(room.loot_positions[1]),1)
 assert(not player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(),"Locked vault is physically closed")
 var preview_camera=Camera2D.new()
 world.add_child(preview_camera)
 preview_camera.position=room.global_position
 preview_camera.zoom=Vector2(1.6,1.6)
 preview_camera.make_current()
 for i in 5: await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("D:/geteco/bank-ready-preview.png")
 room._on_shot()
 assert(room.alarm_started and room.shots_fired)
 for person in room.civilians: assert(person.frightened)
 player.position=room.global_position+room.vault_position
 room._tick_vault(2,true)
 assert(not room.vault_open)
 assert(room.lockpick.active)
 var before_timer=room.alarm_time
 room._process(1)
 assert(room.alarm_time<before_timer,"Lockpick does not pause alarm")
 for i in 3: await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("D:/geteco/bank-lockpick-preview.png")
 room.lockpick.finish(false)
 assert(not room.vault_open and not player.is_in_dialogue)
 room._tick_vault(.3,true)
 room.lockpick.angle=room.lockpick.target_angle+1
 room.lockpick.attempt()
 assert(room.lockpick.mistakes==1 and not room.vault_open)
 for i in 3:
  room.lockpick.angle=room.lockpick.target_angle
  room.lockpick.attempt()
 assert(room.vault_open and room.vault_body.collision_layer==0)
 await physics_frame
 assert(player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(),"Unlocked vault passage opens")
 var before=player.money
 player.position=room.global_position+room.loot_positions[0]
 room._tick_vault(1.3,true)
 assert(player.money==before+400)
 room._tick_vault(2,true)
 assert(player.money==before+400,"Cash cannot be farmed")
 player.position=room.global_position+Vector2(0,90)
 room.alarm_time=.1
 room._process(.2)
 assert(room.dispatched)
 assert(root.get_node("WantedManager").current_stars>=3)
 room.dispatch_response()
 var camera=Camera2D.new()
 world.add_child(camera)
 camera.position=room.global_position
 camera.zoom=Vector2(2,2)
 camera.make_current()
 for layer in world.find_children("","CanvasLayer",true,false): layer.hide()
 for i in 6: await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("D:/geteco/bank-robbery-preview.png")
 var fuel=manager.get_node("InteriorSpaces/FuelInterior")
 fuel.set_process(false)
 fuel.cashier_resists=false
 player.position=fuel.global_position+Vector2(0,10)
 camera.position=fuel.global_position
 for i in 3: await process_frame
 var clerk=fuel.civilians[0]
 Input.warp_mouse(player.get_global_transform_with_canvas()*player.to_local(clerk.global_position))
 await process_frame
 player.weapon_aim_active=true
 var wallet=player.money
 fuel._tick_cashier(3.2,clerk.global_position)
 assert(fuel.cash_paid and player.money==wallet+180)
 fuel._tick_cashier(4,clerk.global_position)
 assert(player.money==wallet+180)
 root.get_node("CampaignState").set_campaign_flag(&"fuel_register",false)
 fuel.cash_paid=false
 fuel.cashier_resists=true
 fuel._tick_cashier(4,clerk.global_position)
 assert(player.money==wallet+180 and fuel.call_confirmed)
 print("BANK_ROBBERY PASS neutral armed shot vault loot timer")
 world.queue_free()
 await process_frame
 quit()



