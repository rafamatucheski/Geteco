extends SceneTree
var failures: Array[String] = []
var checks := 0
var world: Node2D
var player: CharacterBody2D
const SOLIDS = preload("res://systems/interiors/InteriorSolidProjection.gd")
func _init(): call_deferred("run")
func check(ok: bool, label: String):
 checks += 1
 if not ok:
  failures.append(label)
  push_error(label)
func make_player() -> CharacterBody2D:
 var p = load("res://Player.gd").new()
 p.name = "Player"
 p.collision_layer = 4
 p.collision_mask = 7
 var shape := CollisionShape2D.new()
 shape.name = "Collision"
 var capsule := CapsuleShape2D.new()
 capsule.radius = 5
 capsule.height = 16
 shape.shape = capsule
 p.add_child(shape)
 var cam := Camera2D.new()
 cam.name = "Camera"
 p.add_child(cam)
 world.add_child(p)
 p.set_physics_process(false)
 return p
func run():
 create_timer(65).timeout.connect(func(): push_error("Focused fixture timed out"); quit(2))
 root.get_node("SaveManager")._save_dir="D:/geteco/artifacts/focused-repair/saves/"
 root.get_node("SaveManager").clear_pending_save()
 world=Node2D.new()
 root.add_child(world)
 current_scene=world
 player=make_player()
 player.position=Vector2(-5000,-5000)
 for spec in [["HarborPoliceInterior",Vector2.ZERO],["HarborGarageInterior",Vector2(4000,0)]]:
  var room=load("res://world/harbor/interiors/"+spec[0]+".gd").new()
  room.position=spec[1]
  world.add_child(room)
  room.set_process(false)
  room.set_physics_process(false)
  var residents: Array = room.all_npcs if spec[0]=="HarborPoliceInterior" else [room.jager_npc]
  var positions: Array = residents.map(func(n): return n.position)
  room.set_npc_rendering_active(true)
  for i in residents.size():
   check(residents[i].position.distance_to(positions[i])<.01,spec[0]+" authored resident spawn clear "+residents[i].name)
   check(residents[i].has_meta("interior_actor_presentation"),"Resident shares room depth")
  player.position=room.spawn_point.global_position
  if room.has_method("on_actor_entered"): room.on_actor_entered(player)
  else: room._sync_actor_scale()
  var helper: Node = player.get_meta("interior_actor_presentation")
  check(helper._placement_is_clear(room),spec[0]+" player spawn fits full body")
  check(player.sprite_3d_display.scale.x<1.0,spec[0]+" bounded actor calibration")
  for actor in [player,residents[0]]:
   var presentation: Node=actor.get_meta("interior_actor_presentation")
   var saved: Vector2=actor.global_position
   var origin: Vector2=room.global_position
   var project: Callable=room.project_floor if spec[0]=="HarborPoliceInterior" else room.showroom.project_floor
   if spec[0]!="HarborPoliceInterior": origin=room.showroom.global_position
   var pair: Array=[Vector2(-2.8,.8),Vector2(0,.8)] if spec[0]=="HarborPoliceInterior" else [Vector2(3.1,-1.8),Vector2(4.5,-1.8)]
   actor.global_position=origin+project.call(pair[0])
   presentation._update_scale()
   for i in 2: await physics_frame
   check(actor.test_move(actor.global_transform,origin+project.call(pair[1])-actor.global_position),spec[0]+" real "+actor.name+" swept furniture collision")
   actor.global_position=saved
   presentation._update_scale()
  var cam: Camera3D=room.camera_3d
  var vp: SubViewport=cam.get_viewport()
  for actor in [player,residents[0]]: await depth(room,actor,cam,vp)
  room.set_npc_rendering_active(false)
  check(not player.has_meta("interior_actor_presentation"),spec[0]+" exit restores player rig")
  for npc in residents: check(not npc.has_meta("interior_actor_presentation"),"Resident rig restored")
  player.global_position=Vector2(-5000,-5000)
  room.queue_free()
  await process_frame
 await exterior()
 print("FOCUSED_REPAIR checks=",checks," failures=",failures)
 quit(0 if failures.is_empty() else 1)
func depth(room: Node, actor: CharacterBody2D, camera: Camera3D, viewport: SubViewport):
 if DisplayServer.get_name()=="headless":
  check(false,"Rendered depth requires GPU")
  return
 paused=true
 var helper: Node=actor.get_meta("interior_actor_presentation")
 var materials := {}
 var marker := StandardMaterial3D.new()
 marker.albedo_color=Color(1,0,1)
 marker.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 for node in helper.rig.find_children("*","MeshInstance3D",true,false):
  materials[node]=node.material_override
  node.material_override=marker
 var saved: Vector2=actor.global_position
 actor.global_position=room.spawn_point.global_position+Vector2(28,-45)
 helper._update_scale()
 helper.set_process(false)
 actor.set_process(false)
 var box := MeshInstance3D.new()
 var mesh := BoxMesh.new()
 mesh.size=Vector3(4,4,.2)
 box.mesh=mesh
 viewport.add_child(box)
 box.position=helper.anchor.position+Vector3(0,1,0)+(camera.position-helper.anchor.position).normalized()*1.5
 box.look_at(camera.global_position)
 var counts: Array[int]=[]
 for occluding in [true,false]:
  box.visible=occluding
  helper.anchor.show()
  await process_frame
  await RenderingServer.frame_post_draw
  var a: Image=viewport.get_texture().get_image()
  helper.anchor.hide()
  await process_frame
  await RenderingServer.frame_post_draw
  var b: Image=viewport.get_texture().get_image()
  var pixel:=camera.unproject_position(helper.anchor.position+Vector3.UP*.9)
  var changed:=0
  for y in range(maxi(0,int(pixel.y)-20),mini(a.get_height(),int(pixel.y)+20)):
   for x in range(maxi(0,int(pixel.x)-12),mini(a.get_width(),int(pixel.x)+12)):
    var color:=a.get_pixel(x,y)
    if color.r>.9 and color.b>.9 and color.g<.1: changed+=1
  counts.append(changed)
 check(counts[0]==0 and counts[1]>50,"Rendered depth "+room.name+" "+actor.name+" hidden/visible="+str(counts))
 for node in materials: node.material_override=materials[node]
 actor.global_position=saved
 helper._update_scale()
 helper.anchor.show()
 helper.set_process(true)
 box.queue_free()
 paused=false
func exterior():
 var lamp=load("res://geodata/StreetLamp.gd").new()
 world.add_child(lamp)
 var building=load("res://world/harbor/HarborBuilding.gd").new()
 building.name="Garage"
 building.footprint=Vector2(390,250)
 building.building_kind="garage"
 building.entrance_offset=-40
 building.position=Vector2(900,0)
 world.add_child(building)
 var port=load("res://world/harbor/HarborPortModelView.gd").new()
 world.add_child(port)
 port.setup("warehouse",Rect2(1500,-100,640,330),0)
 var portal=load("res://world/mountain_pass/MountainStaticModelView.gd").new()
 portal.position=Vector2(3000,0)
 world.add_child(portal)
 portal.build_view(load("res://world/harbor/PortBossGaragePortal.gd"),22.0,20.0,Vector3.ZERO,Vector3(0,40,15),Vector2i(1024,512))
 var portal_body:=StaticBody2D.new()
 portal.add_child(portal_body)
 SOLIDS.build(portal.model,portal_body,portal.project_floor)
 var visitor=load("res://world/harbor/interiors/HarborConversationalNPC.gd").new()
 visitor.position=Vector2(-2000,-2000)
 world.add_child(visitor)
 for i in 3: await physics_frame
 for body in [player,visitor]:
  for direction in [Vector2.RIGHT,Vector2.DOWN,Vector2(1,1).normalized()]:
   body.global_position=-direction*35
   check(body.test_move(body.global_transform,direction*70),"Post swept collision "+str(direction))
  body.global_position=portal.to_global(portal.project_floor(Vector2(-10,0)))
  check(body.test_move(body.global_transform,Vector2(420,0)),"Port garage closed shell blocks roof traversal "+body.name)
  body.global_position=portal.to_global(portal.project_floor(Vector2(11,0)))
  check(not body.test_move(body.global_transform,Vector2(-30,0)),"Port garage return/entry apron fits "+body.name)
  body.global_position=Vector2(900,-200)
  check(body.test_move(body.global_transform,Vector2(0,400)),"Garage rear shell blocks traversal")
  body.global_position=Vector2(860,180)
  check(not body.test_move(body.global_transform,Vector2(0,-40)),"Garage entry apron stays free")
  body.global_position=Vector2(1450,65)
  check(body.test_move(body.global_transform,Vector2(800,0)),"Port warehouse swept crossing blocked")
 var car=preload("res://world/shared/emergency/ModernTrafficFactory.gd").spawn_parked_vehicle(world,"PortGarageApproach",portal.global_position+Vector2(220,0),PI,"porto_rosso",0)
 car.ensure_presentation()
 car.set_physics_process(false)
 for i in 2: await physics_frame
 check(car.test_move(car.global_transform,Vector2(-40,0)),"Port garage closed gate stops real car before entry threshold")
 portal_body.get_node("Shutter").disabled=true
 for i in 2: await physics_frame
 check(not car.test_move(car.global_transform,Vector2(-40,0)),"Port garage open gate preserves real car entry threshold")
 var camera: Camera3D=car.body_viewport.get_camera_3d()
 var foot: Vector2=car.visual.to_global(camera.unproject_position(Vector3.ZERO)-Vector2(car.body_viewport.size)*.5+car.visual.offset)
 check(foot.distance_to(car.global_position)<.01,"Port garage car render foot agrees with collision origin")
 car.queue_free()
 visitor.queue_free()
 await process_frame
 await outdoor_depth(lamp)
 await outdoor_depth(building.get_node("GarageExterior3D"),-140,150)
 await outdoor_depth(port,-180,190)
 check(not port.model.solid_floor_bounds.is_empty(),"Port physics sourced from visual shell")
 check(port.unproject_floor(port.to_global(port.project_floor(Vector2(4,5)))).distance_to(Vector2(4,5))<.001,"Port projection floor roundtrip")

func outdoor_depth(lamp: Node, back_y: float=-15.0, front_y: float=25.0):
 var zone: Node
 for child in lamp.get_children():
  if child is Area2D and child.get("overlay") is Sprite2D: zone=child
 check(zone != null,"Lamp occlusion sensor exists")
 var cam: Camera2D=player.get_node("Camera")
 cam.zoom=Vector2(4,4)
 cam.make_current()
 var npc=load("res://world/harbor/interiors/HarborConversationalNPC.gd").new()
 npc.position=Vector2(-1000,-1000)
 world.add_child(npc)
 player.viewport_3d.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 player.set_process(true)
 for actor in [player,npc]:
  if actor==player: npc.position=Vector2(-1000,-1000)
  for y in [-15,25]:
   var position_y: float=back_y if y<0 else front_y
   player.global_position=lamp.global_position+(Vector2(0,position_y) if actor==player else Vector2(70,position_y))
   actor.global_position=lamp.global_position+Vector2(0,position_y)
   cam.reset_smoothing()
   cam.reset_physics_interpolation()
   for i in 3: await physics_frame
   zone._process(0)
   paused=true
   await process_frame
   await RenderingServer.frame_post_draw
   var a: Image=root.get_texture().get_image()
   zone.overlay.hide()
   await process_frame
   await RenderingServer.frame_post_draw
   var b: Image=root.get_texture().get_image()

   var changed:=0
   var point: Vector2=root.get_stretch_transform()*actor.get_global_transform_with_canvas().origin
   for py in range(maxi(0,int(point.y)-230),mini(a.get_height(),int(point.y)+50)):
    for px in range(maxi(0,int(point.x)-90),mini(a.get_width(),int(point.x)+90)):
     if a.get_pixel(px,py)!=b.get_pixel(px,py): changed+=1
   check(changed>0 if y<0 else changed==0,"Scenery occlusion "+lamp.name+" "+actor.name+" y="+str(y)+" changed="+str(changed))
   paused=false
 npc.queue_free()
