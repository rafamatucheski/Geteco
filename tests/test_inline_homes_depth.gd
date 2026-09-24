extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "inline_homes_depth"
	arm_watchdog(160)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var homes: ResidenceManager = world.get_node("ResidencePrototype")
	player.money = 100000
	for id in ["westgate_garden","quayside_house","canal_north"]:
		homes.purchase_home(id)
		var room: ResidenceInterior = homes.residence_interiors[id]
		player.global_position = room.spawn_point.global_position
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		await physics_frames(12)
		await _check_room(room,player,id)
	var keeper_room: Node2D = world.get_node("Cemetery/KeeperHouse").room
	player.global_position = keeper_room.spawn_point.global_position
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	await physics_frames(12)
	await _check_room(keeper_room,player,"keeper")
	print("INLINE HOMES DEPTH: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)

func _check_room(room: Node2D,player: CharacterBody2D,label: String) -> void:
	var camera: Camera3D = room.room_camera
	var display: Sprite2D = room.room_display
	var viewport: SubViewport = room.viewport_3d
	var player_adapter: Node = player.get_meta("interior_actor_presentation",null)
	check(is_instance_valid(player_adapter),"Player has room depth adapter: "+label)
	if is_instance_valid(player_adapter): await _check_depth(viewport,camera,player_adapter,"Player "+label)
	var visitor := preload("res://characters/AnimatedPedestrian3D.gd").new() as CharacterBody2D
	room.add_child(visitor)
	visitor.set_physics_process(false)
	visitor.global_position = room.to_global(room.project_floor(Vector2(.2,0)))
	var adapter := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	room.add_child(adapter)
	adapter.configure(visitor,camera,display)
	await physics_frames(3)
	await _check_depth(viewport,camera,adapter,"NPC "+label)
	var target_floor := Vector2(-3.5,-3.0)
	if room is ResidenceInterior:
		var sofa: Rect2 = room.art.solid_rects["Sofa"]
		target_floor = sofa.get_center()
	var target: Vector2 = room.to_global(room.project_floor(target_floor))
	var hit: KinematicCollision2D = visitor.move_and_collide(target-visitor.global_position)
	check(hit != null and hit.get_collider() is StaticBody2D,"NPC body stops at furniture: "+label)
	adapter.restore()
	adapter.queue_free()
	visitor.queue_free()

func _check_depth(viewport: SubViewport,camera: Camera3D,adapter: Node,label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	adapter._update_scale()
	adapter.set_process(false)
	var anchor: Node3D = adapter.anchor
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4,4,.2)
	panel.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("427766")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = material
	viewport.add_child(panel)
	panel.position = anchor.position+Vector3.UP+(camera.position-anchor.position).normalized()*1.5
	panel.look_at(camera.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	var with_actor: Image = viewport.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var without_actor: Image = viewport.get_texture().get_image()
	var pixel: Vector2 = camera.unproject_position(anchor.position+Vector3.UP*.9)
	check(_changed_pixels(with_actor,without_actor,pixel)==0,label+" hides behind opaque 3D wall")
	panel.hide()
	anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	with_actor = viewport.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	without_actor = viewport.get_texture().get_image()
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
