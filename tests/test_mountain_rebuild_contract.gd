extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)

func run() -> void:
	create_timer(70).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var npc := preload("res://world/mountain_pass/WinterResident.gd").new()
	npc.is_stationary = true
	world.add_child(npc)
	npc.set_physics_process(false)
	var player := preload("res://Player.gd").new()
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	collision.shape = CircleShape2D.new()
	collision.shape.radius = 7.0
	player.add_child(collision)
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	player.collision_mask = 1
	npc.collision_mask = 1
	var scripts := ["ResortShopFacade","SummitSkiLodgeExterior","MountainSkiLift","MountainHelipad","MountainWaterfallCaveExterior","ResortPromenadeProp"]
	for script in scripts:
		var modes := ["brazier","rack","lamp"] if script == "ResortPromenadeProp" else [""]
		for mode in modes:
			var prop: Node2D = load("res://world/mountain_pass/"+script+".gd").new()
			if not mode.is_empty(): prop.kind = mode
			world.add_child(prop)
			prop.set_process(false)
			for actor in [player,npc]:
				var helper := preload("res://world/shared/interiors/InteriorActorPresentation.gd").new()
				world.add_child(helper)
				actor.global_position = prop.project_floor(Vector2(0,4.5))
				helper.configure(actor,prop.camera_3d,prop.sprite_3d)
				check(is_equal_approx(helper.anchor.scale.y*helper.standing_rig_height,1.8),"Resident and Dante share human scale")
				for shape in prop.solid_body.get_children():
					var rect: Rect2 = shape.get_meta("model_floor_rect")
					for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
						actor.global_position = prop.project_floor(rect.get_center()+direction*(rect.size*.5+Vector2.ONE*.6))
						helper._update_scale()
						await physics_frame
						var target: Vector2 = prop.project_floor(rect.get_center())
						var hit: KinematicCollision2D = actor.move_and_collide(target-actor.global_position)
						check(hit != null,"%s/%s blocks %s from %s"%[script,shape.name,actor.name,direction])
				if script == "MountainHelipad":
					actor.global_position = prop.project_floor(Vector2(0,4.0))
					helper._update_scale()
					await physics_frame
					check(actor.move_and_collide(prop.project_floor(Vector2.ZERO)-actor.global_position)==null,"Helipad deck accessible from approach")
				check(helper.rig.get_viewport()==prop.viewport_3d and not helper.display.visible,"Native actor shares object depth")
				if DisplayServer.get_name() != "headless": await depth_check(prop,helper,script+mode)
				helper.restore()
				check(not actor.has_meta("interior_actor_presentation"),"Restores exterior scale and depth")
				helper.queue_free()
				actor.global_position = Vector2(2000,2000)
			prop.queue_free()
			await process_frame
	# A referenced target can be freed between emergency queue ticks.
	var incidents := preload("res://world/shared/emergency/ServiceIncidents.gd").new()
	world.add_child(incidents)
	var target := Node2D.new()
	world.add_child(target)
	incidents.incidents.append({"service":"fire","targets":[target],"vehicle":null})
	target.free()
	incidents._process(1.1)
	check(incidents.incidents.is_empty(),"Freed incident targets are discarded without typed-call errors")
	world.queue_free()
	await process_frame
	print("MOUNTAIN_REBUILD_CONTRACT checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func depth_check(prop: Node2D, helper: Node, label: String) -> void:
	helper.actor.global_position = prop.project_floor(Vector2.ZERO)
	helper._update_scale()
	helper.set_process(false)
	# Place an opaque plane between the room camera and the actor, then remove
	# only the plane for the positive control. Real depth must hide both actors.
	var panel := MeshInstance3D.new()
	panel.mesh = QuadMesh.new()
	panel.mesh.size = Vector2(4,4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("244132")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = mat
	prop.viewport_3d.add_child(panel)
	panel.global_position = prop.camera_3d.global_position.lerp(Vector3(0,.85,0),.65)
	panel.global_basis = prop.camera_3d.global_basis
	var hidden := await difference(prop,helper)
	check(hidden==0,"Depth hides actor behind opaque foreground: "+label)
	panel.hide()
	# Remove other opaque geometry for the positive control at the SAME point.
	# The shop roof otherwise correctly occludes the probe independently of the panel.
	prop.model.hide()
	var visible := await difference(prop,helper)
	check(visible>20,"Unobstructed positive visibility: "+label)
	prop.model.show()
	panel.queue_free()
	helper.anchor.show()
	helper.set_process(true)

func difference(prop: Node2D, helper: Node) -> int:
	helper.anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	var a: Image = prop.viewport_3d.get_texture().get_image()
	helper.anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var b: Image = prop.viewport_3d.get_texture().get_image()
	var changed := 0
	var pixel: Vector2 = prop.camera_3d.unproject_position(helper.anchor.global_position+Vector3.UP*.85)
	# Compare the occluded actor region, excluding animated water/wheels elsewhere.
	for y in range(maxi(0,int(pixel.y)-20),mini(a.get_height(),int(pixel.y)+20)):
		for x in range(maxi(0,int(pixel.x)-15),mini(a.get_width(),int(pixel.x)+15)):
			var delta := a.get_pixel(x,y)-b.get_pixel(x,y)
			if absf(delta.r)+absf(delta.g)+absf(delta.b)+absf(delta.a) > .02: changed += 1
	return changed
