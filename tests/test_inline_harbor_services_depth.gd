extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag="inline_harbor_services_depth"
	arm_watchdog(150)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var manager: HarborInteriorManager = world.get_node("Interiors")
	check(DisplayServer.get_name()!="headless","Depth test uses a rendered window")
	for spec in [
		{"id":"police","room":manager.police_interior,"npc":manager.police_interior.sergeant_npc,"clear":Vector2(1.2,3.5),"solid":Vector2(.2,.55)},
		{"id":"clinic","room":manager.clinic_interior,"npc":manager.clinic_interior.nurse_npc,"clear":Vector2(1.3,3.5),"solid":Vector2(-1.85,.25)},
	]:
		var room = spec.room
		var label: String = spec.id
		player.global_position=room.spawn_point.global_position
		player.velocity=Vector2.ZERO
		player.reset_physics_interpolation()
		await physics_frames(12)
		var player_adapter: Node = player.get_meta("interior_actor_presentation",null)
		check(is_instance_valid(player_adapter),"Player shares room depth: "+label)
		check(spec.npc.has_meta("interior_actor_presentation"),"Resident NPC shares room depth: "+label)
		if is_instance_valid(player_adapter): await _check_depth(room,player_adapter,"Player "+label)
		var visitor := preload("res://characters/AnimatedPedestrian3D.gd").new() as CharacterBody2D
		room.add_child(visitor)
		visitor.set_physics_process(false)
		visitor.global_position=room.to_global(room.project_floor(spec.clear))
		var adapter := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
		room.add_child(adapter)
		adapter.configure(visitor,room.room_camera,room.room_display)
		await physics_frames(4)
		await _check_depth(room,adapter,"Visitor "+label)
		var hit: KinematicCollision2D = visitor.move_and_collide(room.to_global(room.project_floor(spec.solid))-visitor.global_position)
		check(hit!=null and hit.get_collider() is StaticBody2D,"Visitor collides with furniture: "+label)
		adapter.restore()
		adapter.queue_free()
		visitor.queue_free()
		player.global_position=room.inline_entrance.to_global(Vector2(0,85))
		player.velocity=Vector2.ZERO
		await physics_frames(50)
		check(not spec.npc.has_meta("interior_actor_presentation"),"Resident depth restores outside: "+label)
		check(room.view.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Empty room pass is suspended: "+label)
	print("INLINE HARBOR SERVICES DEPTH: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)

func _check_depth(room,adapter: Node,label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	adapter._update_scale()
	adapter.set_process(false)
	var anchor: Node3D = adapter.anchor
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size=Vector3(4,4,.2)
	panel.mesh=mesh
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("427766")
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override=material
	room.view.add_child(panel)
	panel.position=anchor.position+Vector3.UP+(room.room_camera.position-anchor.position).normalized()*1.5
	panel.look_at(room.room_camera.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	var with_actor: Image = room.view.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var without_actor: Image = room.view.get_texture().get_image()
	var pixel: Vector2 = room.room_camera.unproject_position(anchor.position+Vector3.UP*.9)
	check(_changed_pixels(with_actor,without_actor,pixel)==0,label+" is hidden behind an opaque 3D object")
	panel.hide()
	anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	with_actor=room.view.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	without_actor=room.view.get_texture().get_image()
	check(_changed_pixels(with_actor,without_actor,pixel)>100,label+" is visible on open floor")
	panel.queue_free()
	anchor.show()
	adapter.set_process(true)

func _changed_pixels(a: Image,b: Image,center: Vector2) -> int:
	var changed := 0
	for y in range(maxi(0,int(center.y)-25),mini(a.get_height(),int(center.y)+25)):
		for x in range(maxi(0,int(center.x)-20),mini(a.get_width(),int(center.x)+20)):
			if a.get_pixel(x,y)!=b.get_pixel(x,y): changed+=1
	return changed
