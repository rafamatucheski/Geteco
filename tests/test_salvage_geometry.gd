extends "res://tests/test_salvage_yard.gd"
const REVIEW := "D:/geteco/artifacts/neco-fix-0910/"

func audit_access() -> void:
	await super.audit_access()
	var probe:=CharacterBody2D.new()
	probe.collision_layer=0
	probe.collision_mask=1
	var collision:=CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size=Vector2(78,38)
	collision.shape=shape
	probe.add_child(collision)
	world.add_child(probe)
	await physics_frame
	# Sweep across both side fences at several heights, including the former
	# bottom corner gaps, and across the back/front walls. Use the physics server.
	for x in [-16.0,16.0]:
		for z in [-9.0,-5.0,0.0,5.0,10.8]:
			var point: Vector2=yard.to_global(yard.art.projected(Vector3(x,0,z)))
			probe.global_position=point+Vector2(signf(x)*80,0)
			var hit:=probe.move_and_collide(Vector2(-signf(x)*160,0),true)
			check(hit!=null,"Vehicle blocked at side fence x=%s z=%s" % [x,z])
	for z in [-11.5,11.5]:
		for x in [-14.0,-8.0,8.0,14.0]:
			var point: Vector2=yard.to_global(yard.art.projected(Vector3(x,0,z)))
			probe.global_position=point+Vector2(0,signf(z)*80)
			check(probe.move_and_collide(Vector2(0,-signf(z)*160),true)!=null,"Front/back perimeter blocks cars")
	probe.rotation=PI*.5
	probe.global_position=yard.to_global(Vector2(0,280))
	check(probe.move_and_collide(Vector2(0,-130),true)==null,"Vehicle enters through the visible gate")
	probe.queue_free()
	var point_query:=PhysicsPointQueryParameters2D.new()
	point_query.collision_mask=1
	# Points sit in the visible elevated bodywork, where old flat boxes missed.
	for point in [Vector3(-12,1.3,-3),Vector3(-8,1.3,-3),Vector3(-4,1.3,-3),Vector3(-12,1.3,-.2),Vector3(-8,1.3,-.2),Vector3(-4,1.3,-.2),Vector3(-10,2.3,5),Vector3(-4,1,-8.5),Vector3(12,.5,3),Vector3(13,.3,7),Vector3(-5,4,-1),Vector3(7.2,1,-1.5)]:
		point_query.position=yard.to_global(yard.art.projected(point))
		check(not world.get_world_2d().direct_space_state.intersect_point(point_query).is_empty(),"Visible object has physical geodata: "+str(point))
	var foot:=CharacterBody2D.new()
	foot.collision_mask=1
	var foot_collision:=CollisionShape2D.new()
	var circle:=CircleShape2D.new()
	circle.radius=6
	foot_collision.shape=circle
	foot.add_child(foot_collision)
	world.add_child(foot)
	foot.add_collision_exception_with(player)
	await physics_frame
	foot.global_position=yard.to_global(yard.dock+Vector2(0,80))
	var walking_hit:=foot.move_and_collide(yard.npc.global_position+Vector2(20,0)-foot.global_position,true)
	check(walking_hit==null,"Player can walk from the delivery bay to Neco: "+(str(walking_hit.get_collider().get_path()) if walking_hit!=null else "clear"))
	foot.global_position=yard.to_global(yard.art.projected(Vector3(14,0,10)))
	check(foot.move_and_collide(Vector2(100,0),true)!=null,"Pedestrian cannot leave through side fence")
	foot.queue_free()
	if not yard.legacy:
		var land:=Rect2(yard.global_position+LOCATION.LAND.position,LOCATION.LAND.size)
		check(land.end.x>=-100 and land.end.y>=1070,"Yard terrain joins the existing district and Memorial land")
		check(LOCATION.safe_load_position(Vector2(-2250,350),false)==yard.global_position+Vector2(0,470),"Old isolated yard save migrates to connected access")
	check(yard.npc.model_root.find_child("Spanner",true,false)!=null,"Neco has his own mechanic model")

func shot(label: String) -> void:
	if not captures: return
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var suffix: String="_legacy" if yard.legacy else "_harbor"
	root.get_texture().get_image().save_png(REVIEW+label+suffix+".png")
	if label=="01_patio":
		var cam:=root.get_viewport().get_camera_2d()
		var old_pos:=cam.global_position
		var old_zoom:=cam.zoom
		cam.global_position=yard.npc.global_position+Vector2(30,-30)
		cam.zoom=Vector2.ONE*2.2
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(REVIEW+"neco_detail"+suffix+".png")
		cam.global_position=yard.global_position+Vector2(250,330)
		cam.zoom=Vector2.ONE*.45
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(REVIEW+"connected_land"+suffix+".png")
		cam.global_position=old_pos
		cam.zoom=old_zoom
