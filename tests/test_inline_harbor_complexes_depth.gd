extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	_tag="inline_harbor_complexes_depth"
	arm_watchdog(175)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	check(DisplayServer.get_name()!="headless","Depth samples use the rendered game")
	var player: CharacterBody2D = world.get_node("Player")
	var manager: HarborInteriorManager = world.get_node("Interiors")
	var boss = world.get_node("Interiors/InteriorSpaces/PortBossGarage")
	boss.build_interior()
	for spec in [
		{"id":"maciota","room":manager.garage_interior,"view":manager.garage_interior.showroom,"npc":manager.garage_interior.jager_npc,"outside":world.get_node("District/Garage/Entrance").to_global(Vector2(0,100))},
		{"id":"fire","room":manager.fire_station_interior,"view":manager.fire_station_interior.room_view,"npc":manager.fire_station_interior.captain_npc,"outside":world.get_node("NorthDistrict/NorthFireStation/Entrance1").to_global(Vector2(0,100))},
		{"id":"boss","room":boss,"view":boss.showroom,"npc":boss.guards[0],"outside":boss.EXTERIOR+Vector2(75,0)},
	]:
		var id: String=spec.id
		var room=spec.room
		var view: Node2D=spec.view
		player.global_position=room.spawn_point.global_position
		player.velocity=Vector2.ZERO
		player.reset_physics_interpolation()
		await physics_frames(60 if id=="fire" else 18)
		var actor_adapter: Node=player.get_meta("interior_actor_presentation",null)
		check(is_instance_valid(actor_adapter),"Player uses same 3D depth buffer: "+id)
		check(spec.npc.has_meta("interior_actor_presentation"),"Resident uses same 3D depth buffer: "+id)
		if id=="fire":
			# Parked trucks have independently animated 3D lights. Hide only their
			# models during image subtraction so the measured pixels belong to the actor.
			for truck in room.bay_trucks: truck.body_model.hide()
		if is_instance_valid(actor_adapter): await _check_depth(view,actor_adapter,"Player "+id)
		var npc_adapter: Node=spec.npc.get_meta("interior_actor_presentation",null)
		if is_instance_valid(npc_adapter): await _check_depth(view,npc_adapter,"Resident "+id)
		if id=="fire":
			for truck in room.bay_trucks: truck.body_model.show()
		player.global_position=spec.outside
		player.velocity=Vector2.ZERO
		await physics_frames(28)
		check(not player.has_meta("interior_actor_presentation"),"Player presentation restores outside: "+id)
		check(view.viewport_3d.render_target_update_mode==SubViewport.UPDATE_DISABLED or view.viewport_3d.render_target_update_mode==SubViewport.UPDATE_ONCE,"Empty room render is suspended: "+id)
	print("INLINE HARBOR COMPLEXES DEPTH: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)

func _check_depth(view: Node2D,adapter: Node,label: String) -> void:
	adapter._update_scale()
	adapter.set_process(false)
	var anchor: Node3D=adapter.anchor
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size=Vector3(4,4,.2)
	panel.mesh=mesh
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("427766")
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override=material
	view.viewport_3d.add_child(panel)
	panel.position=anchor.position+Vector3.UP+(view.camera_3d.position-anchor.position).normalized()*1.5
	panel.look_at(view.camera_3d.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	var actor: Image=view.viewport_3d.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var empty: Image=view.viewport_3d.get_texture().get_image()
	var pixel: Vector2=view.camera_3d.unproject_position(anchor.position+Vector3.UP*.9)
	var masked_pixels := _changed_pixels(actor,empty,pixel)
	check(masked_pixels==0,label+" is hidden by opaque geometry")
	panel.hide()
	anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	actor=view.viewport_3d.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	empty=view.viewport_3d.get_texture().get_image()
	var clear_pixels := _changed_pixels(actor,empty,pixel)
	check(clear_pixels>100,label+" is visible on open floor")
	panel.queue_free()
	anchor.show()
	adapter.set_process(true)

func _changed_pixels(a: Image,b: Image,center: Vector2) -> int:
	var count := 0
	for y in range(maxi(0,int(center.y)-25),mini(a.get_height(),int(center.y)+25)):
		for x in range(maxi(0,int(center.x)-20),mini(a.get_width(),int(center.x)+20)):
			if a.get_pixel(x,y)!=b.get_pixel(x,y): count+=1
	return count
