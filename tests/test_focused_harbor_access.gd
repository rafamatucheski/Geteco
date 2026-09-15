extends SceneTree
var failures: Array[String]=[]
var checks:=0
func _init(): call_deferred("run")
func check(ok: bool,label: String):
 checks+=1
 if not ok: failures.append(label); push_error(label)
func run():
 create_timer(90).timeout.connect(func(): quit(2))
 root.get_node("SaveManager")._save_dir="D:/geteco/artifacts/focused-repair/saves/"
 root.get_node("SaveManager").clear_pending_save()
 root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete",true)
 var scene=load("res://world/harbor/HarborGame.tscn").instantiate()
 root.add_child(scene)
 current_scene=scene
 for i in 30: await physics_frame
 var p=scene.get_node("Player")
 var manager=scene.get_node("Interiors")
 scene._walk()
 await create_timer(3.0).timeout
 p.show()
 p.set_physics_process(false)
 for spec in [[manager.police_interior,"District/Police/Entrance"],[manager.garage_interior,"District/Garage/Entrance"]]:
  var room: Node2D=spec[0]
  var door=scene.get_node(spec[1])
  manager._on_exterior_destination_requested(door,p,&"",null,&"",room,room.spawn_point)
  for i in 3: await physics_frame
  p.set_physics_process(false)
  check(p.has_meta("interior_actor_presentation"),room.name+" entry configures actor; visible="+str(p.visible)+" dead="+str(p.is_dead)+" arrested="+str(p.is_arrested))
  if not p.has_meta("interior_actor_presentation"): quit(1); return
  var helper: Node=p.get_meta("interior_actor_presentation")
  check(helper._placement_is_clear(room),room.name+" entry whole-body spawn")
  var positions: Array[Vector2]=[]
  if room==manager.police_interior:
   for point in [Vector2(-1.8,3),Vector2(-2.2,2.3),Vector2(-4.2,2.3)]: positions.append(room.to_global(room.project_floor(point)))
  else:
   for point in [Vector2(-2.8,3.4),Vector2(-2.8,-2.8),Vector2(-.95,-2.9),Vector2(-2.8,-2.8),Vector2(-2.8,3.4),Vector2(1.6,3.4),Vector2(1.6,1.5),Vector2(3.0,1.5),Vector2(3.4,.5),Vector2(4.5,-.2),Vector2(3.4,.5),Vector2(3.0,1.5),Vector2(3.2,3.4),Vector2(4.7,3.4)]: positions.append(room.showroom.to_global(room.showroom.project_floor(point)))
  var route: Array[Vector2]=[p.global_position]
  route.append_array(positions)
  for target in positions:
   var motion: Vector2=target-p.global_position
   var hit=p.move_and_collide(motion)
   check(hit==null,room.name+" circulation to "+str(target-room.global_position))
   helper._update_scale()
  route.reverse()
  # Walk back along the same proven corridor, including its turn at the office door.
  for target in route:
   var hit=p.move_and_collide(target-p.global_position)
   check(hit==null,room.name+" return circulation")
  manager._on_exit_door_requested(room.exit_door,p,&"",null,&"",door.destination_id)
  p.set_physics_process(false)
  check(not p.has_meta("interior_actor_presentation"),room.name+" exit restores rig")
  check(p.global_position.distance_to(door.get_node("OutsideReturn").global_position)<.01,room.name+" exterior return")
  manager._on_exterior_destination_requested(door,p,&"",null,&"",room,room.spawn_point)
  for i in 2: await physics_frame
  p.set_physics_process(false)
  check(p.has_meta("interior_actor_presentation"),room.name+" reentry")
  p.global_position=door.get_node("OutsideReturn").global_position
  room.set_npc_rendering_active(false)
  check(not p.has_meta("interior_actor_presentation"),room.name+" respawn restores rig")
 var lane=scene.find_child("PortLogisticsCircuit",true,false) as Path2D
 check(lane!=null,"Port production logistics lane exists")
 if lane!=null:
  var truck=scene.find_child("PortCargoTruck0",true,false)
  truck.ensure_presentation()
  for i in 2: await process_frame
  var camera: Camera3D=truck.body_viewport.get_camera_3d()
  var foot: Vector2=truck.visual.to_global(camera.unproject_position(Vector3.ZERO)-Vector2(truck.body_viewport.size)*.5+truck.visual.offset)
  check(foot.distance_to(truck.global_position)<.01,"Port truck render grounded at physical origin")
  var blocked:=0
  var length: float=lane.curve.get_baked_length()
  var query:=PhysicsShapeQueryParameters2D.new()
  query.shape=truck.collision.shape
  query.collision_mask=1
  query.exclude=[truck.get_rid()]
  for offset in range(0,int(length),80):
   var point: Vector2=lane.curve.sample_baked(float(offset))
   var next: Vector2=lane.curve.sample_baked(minf(float(offset)+1,length))
   query.transform=Transform2D((next-point).angle(),lane.to_global(point))
   if not scene.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): blocked+=1
  check(blocked==0,"Port truck full-body route samples clear; blocked="+str(blocked))
 print("FOCUSED_ACCESS checks=",checks," failures=",failures)
 quit(0 if failures.is_empty() else 1)

