extends "res://tools/capture_meshy_contact_refinement.gd"
## Mesmo enquadramento e luz para comparar a mão apresentada, não só a origem do osso.
var capture_states: Array = ["aim", "recoil", "reload-fetch", "reload-insert", "reload-rack", "run"]

func _initialize() -> void:
	super._initialize()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--states="): capture_states = Array(arg.substr(9).split(","))

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8fa3ad")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b9c4cc")
	environment.environment.ambient_light_energy = 0.8
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 35, 0)
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.18
	for source in sources:
		var subject: Node3D
		var gun: Node3D
		var actor: Node3D
		var police: Node3D
		var driver: RefCounted
		var label: String = source.get_file().get_basename()
		if source == "dante":
			actor = preload("res://scripts/Actor.gd").new()
			actor.is_player = true
			stage.add_child(actor)
			actor.set_physics_process(false)
			gun = Node3D.new()
			stage.add_child(gun)
			preload("res://gameplay/ArsenalWeapon3D.gd").build(gun, weapon_id)
			actor.set_combat_weapon_mount(gun, preload("res://gameplay/WeaponPoseData.gd").GRIPS[weapon_id])
			driver = preload("res://gameplay/WeaponRigPose.gd").new()
			subject = actor
		else:
			var path: String = source if source.begins_with("res://") else "res://assets/civilians/meshy/%s.glb" % source
			CATALOG.override[2] = _prepare_source(path)
			police = MODEL.new()
			police.tier = 2
			police.appearance_index = 2
			stage.add_child(police)
			police.equip(weapon_id)
			for step in 8: await process_frame
			print("HAND_PROFILE ", label, " enabled=", police.body.palm_grip_enabled, " shapes=", police.body.mesh_node.get_blend_shape_count())
			if "--solid-hands" in OS.get_cmdline_user_args():
				var diagnostic := StandardMaterial3D.new()
				diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				diagnostic.albedo_color = Color("d99080")
				if "--two-sided-hands" in OS.get_cmdline_user_args(): diagnostic.cull_mode = BaseMaterial3D.CULL_DISABLED
				police.body.mesh_node.set_surface_override_material(1, diagnostic)
			for piece in police.body.find_children("Equip_*", "MeshInstance3D", true, false): piece.hide()
			gun = police.weapon
			subject = police
		for state in capture_states:
			if police: police.body.set_process(true)
			var moving: bool = state == "run"
			var reloading: bool = state.begins_with("reload")
			var progress: float = {"reload-fetch": .18, "reload-insert": .48, "reload-rack": .72}.get(state, 0.0)
			for step in 90:
				if actor:
					actor.combat_facing = 0.0
					actor.combat_stance = "gun"
					var speed := 6.5 if moving else 0.0
					actor._pose_locomotion(Vector3.FORWARD, speed, Vector3.FORWARD * speed / 60.0, speed)
					if state == "recoil" and step == 89: driver.attack(weapon_id)
					var packet: Dictionary = driver.update(weapon_id, 1.0/60.0, not moving, reloading, progress, moving, moving, actor.phase, actor.combat_rig_info())
					actor.set_combat_weapon_pose(weapon_id, packet)
					actor._apply_combat_weapon_pose()
					gun.global_transform = actor.combat_weapon_transform(preload("res://gameplay/WeaponPoseData.gd").GRIPS[weapon_id])
				else:
					if moving: police.position.z -= 4.5 / 60.0
					if state == "recoil" and step == 89: police.attack()
					police.update_pose(1.0/60.0, not moving, reloading, progress, 0.0)
					if state == "idle":
						police.body.hand_provider = Callable()
						police.body.hand_targets = [null, null]
						gun.visible = false
				await process_frame
			await create_timer(0.0).timeout
			if police: police.body.set_process(false)
			if "--hide-weapon-for-inspection" in OS.get_cmdline_user_args(): gun.hide()
			if police:
				var bones: Array = []
				var skeleton: Skeleton3D = police.body.skeleton
				for bone in skeleton.get_bone_count():
					var pose := skeleton.get_bone_global_pose(bone)
					bones.append({"name": skeleton.get_bone_name(bone), "matrix": [
						[pose.basis.x.x, pose.basis.y.x, pose.basis.z.x, pose.origin.x],
						[pose.basis.x.y, pose.basis.y.y, pose.basis.z.y, pose.origin.y],
						[pose.basis.x.z, pose.basis.y.z, pose.basis.z.z, pose.origin.z], [0, 0, 0, 1]]})
				FileAccess.open("%s/%s-%s-bones.json" % [output_dir, label, state], FileAccess.WRITE).store_string(JSON.stringify(bones))
			for view in [["front", Vector3(0, 0, -4)], ["side", Vector3(4, 0, 0)], ["other-side", Vector3(-4, 0, 0)]]:
				var center := subject.position + Vector3(0, 1.33, 0)
				camera.position = center + view[1]
				camera.look_at(center)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s-%s-%s-%s.png" % [output_dir, label, weapon_id, state, view[0]]))
				if police and "--compare-targets" in OS.get_cmdline_user_args():
					# A mesma pose congelada e os mesmos ossos, alternando só o solver.
					for optimized in [false, true]:
						MODEL.optimize_weapon_targets = optimized
						preload("res://assets/civilians/MeshyBodyRig.gd").optimize_pose_chain = optimized
						police.body._meshy._cache[0] = Transform3D.IDENTITY
						police.body._pose(0.0)
						police.body._meshy.sync(0.0)
						await process_frame
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s-%s-%s-%s-%s.png" % [output_dir, label, weapon_id, state, view[0], "after" if optimized else "before"]))
		subject.queue_free()
		if actor: gun.queue_free()
		await process_frame
	CATALOG.override.clear()
	print("Comparação de mãos em ", output_dir)
	quit()
