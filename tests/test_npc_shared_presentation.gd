extends SceneTree
const OUTPUT := "res://docs/measurements/npc-presentation-0910/"
var failures: Array[String] = []
var checks := 0
var actors: Array[Node2D] = []
var labels: Array[String] = []
var scene: Node2D

class ResidentDisplay extends Node2D:
	var viewport_3d: SubViewport
	var model_root: Node3D

func add_resident(path: String, label: String) -> void:
	var display := ResidentDisplay.new()
	scene.add_child(display)
	display.viewport_3d = SubViewport.new()
	display.viewport_3d.size = Vector2i(96,96)
	display.viewport_3d.transparent_bg = true
	display.viewport_3d.own_world_3d = true
	display.add_child(display.viewport_3d)
	display.model_root = load(path).new()
	display.viewport_3d.add_child(display.model_root)
	display.model_root.set_process(false)
	display.set_meta("faces_positive_z", true)
	var camera := Camera3D.new()
	camera.position = Vector3(0,3.2,-1.4)
	camera.fov = 35
	display.viewport_3d.add_child(camera)
	camera.look_at(Vector3(0,.8,0),Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-30,0)
	display.viewport_3d.add_child(light)
	var world_env := WorldEnvironment.new()
	world_env.environment = Environment.new()
	world_env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.environment.ambient_light_color = Color("c2c9d6")
	world_env.environment.ambient_light_energy = .8
	display.viewport_3d.add_child(world_env)
	actors.append(display)
	labels.append(label)

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func add_actor(path: String, label: String, properties := {}) -> Node2D:
	var actor: Node2D = load(path).new()
	for key in properties: actor.set(key, properties[key])
	actor.set_meta("quiet_patrol", true)
	scene.add_child(actor)
	actor.position = Vector2(200 + actors.size()*80, 200)
	actor.set_physics_process(false)
	actor.set_process(false)
	if actor.has_method("ensure_presentation"): actor.ensure_presentation()
	var rig := actor.get_node_or_null("NPCCombatRig")
	if rig: rig.set_physics_process(false)
	actors.append(actor)
	labels.append(label)
	return actor

func _run() -> void:
	seed(9010)
	create_timer(60).timeout.connect(func(): quit(2))
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var wm := root.get_node("WantedManager")
	for stars in [1,3,4,5,6]:
		wm.current_stars = stars
		var officer = add_actor("res://police/PoliceOfficer.gd", "Policia %s" % stars)
		var crown: MeshInstance3D = officer.head_node.get_node("CoveredCrown")
		var bounds := crown.mesh.get_aabb()
		check(bounds.end.y + crown.position.y >= .20, "Crown covers scalp tier %s" % stars)
		check(bounds.size.x >= .349, "Crown covers sides tier %s" % stars)
		check(officer.has_meta("rig_tailored"), "Uniform details tier %s" % stars)
	wm.current_stars = 0
	var guard = add_actor("res://world/harbor/events/BankGuard.gd", "Seguranca / escopeta", {"uses_shotgun": true})
	check(guard.right_upper_arm.visible and guard.left_upper_arm.visible, "Bank guards retain articulated arms")
	check(guard.get_node("NPCCombatRig").active_weapon_id == "shotgun", "Guard gets actual shotgun profile")
	for data in [["Firefighter", "Bombeiro"], ["Paramedic", "Socorrista"], ["Mortician", "Agente funerario"]]:
		var actor = add_actor("res://%s.gd" % data[0], data[1])
		check(actor.has_meta("rig_tailored"), "%s detail coverage" % data[0])
		check(not actor.has_node("NPCCombatRig"), "%s retains service work animation" % data[0])
	add_actor("res://world/harbor/interiors/HarborConversationalNPC.gd", "Atendente")
	for archetype in [0,2,4,7]:
		var person = add_actor("res://AnimatedPedestrian3D.gd", "Civil %s" % archetype, {"archetype_override": archetype})
		check(person.has_meta("citizen_dressed"), "Base pedestrians receive details %s" % archetype)
		var count: int = person.head_node.get_child_count()
		preload("res://world/shared/pedestrians/CitizenDetails.gd").dress(person, archetype)
		check(person.head_node.get_child_count() == count, "Deferred/Harbor callbacks do not duplicate details")
	for role in ["lookout", "enforcer", "leader"]:
		var cobra = add_actor("res://world/harbor/cobras/CobraResident.gd", "Cobra " + role, {"combat_role": role})
		check(cobra.has_node("NPCCombatRig"), "Cobra %s shares weapon rig" % role)
		check(cobra.get_node("NPCCombatRig").active_weapon_id == cobra.weapon_id, "Cobra role weapon matches profile")
	var rig = actors[0].get_node("NPCCombatRig")
	for id in rig.POSE.PROFILES:
		rig.equip(id)
		for i in 100: rig.combat_pose.update(rig, 1.0/60, true, false, 0)
		var mount: Node3D = rig.weapon_mount_node
		var hand: Vector3 = rig.right_lower_arm.to_global(Vector3(0,-.20,0))
		check(hand.distance_to(mount.global_position) < .001, "%s firing grip anchored" % id)
		check(hand.distance_to(rig.current_gun_mesh.to_global(rig.POSE.GRIPS[id])) < .001, "%s actual handle in hand" % id)
		if rig.POSE.SUPPORT_GRIPS.has(id):
			var support: Vector3 = rig.left_lower_arm.to_global(Vector3(0,-.20,0))
			check(support.distance_to(rig.current_gun_mesh.to_global(rig.POSE.SUPPORT_GRIPS[id])) < .045, "%s support hand" % id)
		var aimed: Basis = mount.basis
		rig.attack()
		check(rig.combat_pose.action_age == 0, "%s shares attack event" % id)
		for i in 100: rig.combat_pose.update(rig, 1.0/60, false, true, .3)
		check(mount.transform.is_finite(), "%s sprint transform finite" % id)
		check(rig.combat_pose.recoil < .001, "%s recoil settles" % id)
		if id != "fists": check(not aimed.is_equal_approx(mount.basis), "%s aimed and carry poses differ" % id)
	rig.equip("pistol")
	for actor in actors:
		var combat := actor.get_node_or_null("NPCCombatRig")
		if combat:
			for i in 100: combat.combat_pose.update(combat, 1.0/60, true, false, 0)
			check(actor.muzzle_flash_3d.get_parent() == combat.weapon_mount_node, "Muzzle follows actual barrel")
			if combat.POSE.SUPPORT_GRIPS.has(combat.active_weapon_id):
				var grip: Vector3 = combat.current_gun_mesh.to_global(combat.POSE.SUPPORT_GRIPS[combat.active_weapon_id])
				check(grip.distance_to(combat.left_lower_arm.to_global(Vector3(0,-.20,0))) < .045, "Body proportions retain two-hand contact: %s" % combat.active_weapon_id)
	# A fall owns the arms; the late animation pass must never raise a dead NPC.
	rig.actor.is_dead = true
	var fallen_arm: Transform3D = rig.right_upper_arm.transform
	rig._physics_process(.25)
	check(rig.right_upper_arm.transform.is_equal_approx(fallen_arm), "Death is not overwritten by combat pose")
	rig.actor.is_dead = false
	add_resident("res://prototypes/living_cast/CivilianDriverModel.gd", "Motorista / cliente")
	add_resident("res://world/mountain_pass/WinterResidentModel.gd", "Morador da serra")
	var district = load("res://world/harbor/HarborDistrict.gd").new()
	var moved := false
	for lamp in district.get_street_lamp_points():
		check(lamp.pos != Vector2(650,315), "Bank entrance axis free of lamp")
		moved = moved or lamp.pos == Vector2(790,285)
	check(moved, "Lamp relocated beside bank frontage")
	district.free()
	for body in 5:
		var diverse = add_actor("res://world/harbor/cobras/CobraResident.gd", "Body coverage", {"combat_role":"enforcer", "body_type_override":body})
		var combat = diverse.get_node("NPCCombatRig")
		for id in combat.POSE.SUPPORT_GRIPS:
			combat.equip(id)
			for frame in 100: combat.combat_pose.update(combat,1.0/60,true,false,0)
			var support: Vector3 = combat.current_gun_mesh.to_global(combat.POSE.SUPPORT_GRIPS[id])
			check(support.distance_to(combat.left_lower_arm.to_global(Vector3(0,-.20,0))) < .045, "Body %s supports %s" % [body,id])
		actors.pop_back()
		labels.pop_back()
		diverse.free()
	# Rendering is optional; assertions also work with the dummy renderer.
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		await capture_gallery("gameplay", false)
		await capture_gallery("detalhes", true)
	for actor in actors: actor.free()
	scene.free()
	print("NPC_SHARED_PRESENTATION: %s checks, %s failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func capture_gallery(file: String, closeup: bool) -> void:
	var size := 256
	var rows := ceili(actors.size()/5.0)
	var atlas := Image.create(size*5, (size+30)*rows, false, Image.FORMAT_RGBA8)
	atlas.fill(Color("202b36"))
	for i in actors.size():
		var actor = actors[i]
		var viewport: SubViewport = actor.get("viewport_3d") if actor.get("viewport_3d") != null else actor.get("viewport")
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if closeup:
			viewport.size = Vector2i(size,size)
			var camera := viewport.get_camera_3d()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 2.25
			camera.position = Vector3(0,1.75,-3)
			actor.model_root.rotation.y = PI if actor.has_meta("faces_positive_z") else 0
			camera.look_at(Vector3(0,.85,0),Vector3.UP)
			if actor.has_meta("faces_positive_z"):
				camera.size = 2.2
				camera.look_at(Vector3(0,.90,0),Vector3.UP)
			var label := Label.new()
			label.text = labels[i]
			label.position = Vector2(5,234)
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_color_override("font_shadow_color", Color.BLACK)
			label.add_theme_constant_override("shadow_offset_y", 1)
			viewport.add_child(label)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	for i in actors.size():
		var actor = actors[i]
		var viewport: SubViewport = actor.get("viewport_3d") if actor.get("viewport_3d") != null else actor.get("viewport")
		var img := viewport.get_texture().get_image()
		img.resize(size,size,Image.INTERPOLATE_NEAREST)
		atlas.blend_rect(img,Rect2i(0,0,size,size),Vector2i((i%5)*size,(i/5)*(size+30)))
	atlas.save_png(get_output_directory() + file + ".png")

func get_output_directory() -> String:
	return OUTPUT
