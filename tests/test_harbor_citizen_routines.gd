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
 var routes=preload("res://world/harbor/HarborPedestrianRoutes.gd")
 var connected=routes.connected_routes(self)
 print("CONNECTED_ROUTES ",connected.size())
 assert(connected.size()>0)
 assert(get_nodes_in_group("foot_patrol").size()==2)
 var walkers=get_nodes_in_group("authored_sidewalk_pedestrian")
 var loops=0
 for walker in walkers:
  if walker.route_loop: loops+=1
 assert(loops>=24)
 var walker=walkers[0]
 walker.set_physics_process(false)
 walker._route_segment=walker.route_points.size()-2
 walker._route_direction=1
 walker._route_target_ready=true
 walker._pick_new_sidewalk_target()
 assert(walker._route_segment==0 and walker._route_direction==1)
 var officer=get_nodes_in_group("foot_patrol")[0]
 officer.set_physics_process(false)
 var player=world.get_node("Player")
 player.set_physics_process(false)
 player.global_position=Vector2(750,482)
 officer.global_position=Vector2(800,482)
 await physics_frame
 root.get_node("WantedManager").report_crime(12)
 assert(officer.alerted,"Nearby patrol sees reported crime")
 root.get_node("WantedManager").reset_crime()
 officer._physics_process(.1)
 assert(not officer.alerted)
 var wall=StaticBody2D.new()
 wall.position=Vector2(775,482)
 var shape=CollisionShape2D.new()
 var box=RectangleShape2D.new()
 box.size=Vector2(12,80)
 shape.shape=box
 wall.add_child(shape)
 world.add_child(wall)
 await physics_frame
 await physics_frame
 root.get_node("WantedManager").report_crime(12)
 assert(not officer.alerted,"Wall blocks witnessing a crime")
 root.get_node("WantedManager").reset_crime()
 wall.queue_free()
 var crossing=preload("res://geodata/roads/safety/RoadCrossingArea2D.gd").new()
 crossing.configure({"id":"test","junction_id":"test_junction","position":Vector2(-4000,-4000),"road_width":120.0})
 world.add_child(crossing)
 walker.global_position=crossing.to_global(Vector2(0,-82))
 var exit=crossing.to_global(Vector2(0,82))
 crossing.set_signal_state(true,false)
 assert(routes.crossing_wait(walker,exit),"Wait at red pedestrian signal")
 crossing.set_signal_state(false,true)
 assert(not routes.crossing_wait(walker,exit),"Clear green crossing proceeds")
 walker.global_position=crossing.to_global(Vector2(0,-20))
 crossing.set_signal_state(true,false)
 assert(not routes.crossing_wait(walker,exit),"Finish committed crossing")
 crossing.queue_free()
 print("HARBOR_CITIZEN_ROUTINES PASS loops=",loops)
 # Staged lineup of the actual runtime rigs, frozen only for this capture.
 var camera=Camera2D.new()
 world.add_child(camera)
 camera.position=Vector2(1750,1940)
 camera.zoom=Vector2(3,3)
 camera.make_current()
 for layer in world.find_children("","CanvasLayer",true,false): layer.hide()
 for i in 8:
  var npc=walkers[i]
  npc.set_physics_process(false)
  npc.position=Vector2(1600+i*42,1940)
  npc.model_root.rotation.y=PI*.18
  npc.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
 for i in 5: await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("D:/geteco/citizens-detail-preview.png")
 world.queue_free()
 await process_frame
 quit()
