extends SceneTree
## Actual visible-rig hand/weapon and rope contact contracts, for every tier.
const MODEL := preload("res://gameplay/PoliceModel.gd")
const OFFICER := preload("res://gameplay/PoliceAgent.gd")
const RAPPLE := preload("res://gameplay/police_response/air_k9/PoliceRappelPose.gd")
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
const POSES := preload("res://gameplay/WeaponPoseData.gd")
var failures: Array[String] = []
var checks := 0
var scene: Node3D
var folder := ""

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("OFFICER_POSE PASS " if ok else "OFFICER_POSE FAIL ") + label)
	if not ok: failures.append(label)

func hand_position(model: Node3D, index: int) -> Vector3:
	return model.body.forearms[index].to_global(Vector3(0, -KIT.FOREARM - .06, 0))

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "capture " + label)

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	folder = OS.get_temp_dir().path_join("geteco-officer-poses")
	DirAccess.make_dir_recursive_absolute(folder)
	root.size = Vector2i(1440, 900)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(5, 3.6, -7)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -24, 0)
	scene.add_child(sun)
	var models: Array[Node3D] = []
	for tier in 5:
		var model := MODEL.new()
		model.tier = tier
		model.appearance_index = tier
		model.position.x = (tier - 2) * 1.35
		scene.add_child(model)
		model.equip("pistol" if tier == 0 else ("smg" if tier == 1 else "m4a1"))
		model._install_body()
		model.body.set_process(false)
		models.append(model)
		for mode in ["rest", "aim", "reload_fetch", "reload_insert", "reload_rack"]:
			var aiming: bool = mode == "aim"
			var reload: bool = mode.begins_with("reload")
			var progress := .25 if mode == "reload_fetch" else (.5 if mode == "reload_insert" else .73)
			for frame in 60:
				model.update_pose(1.0 / 60.0, aiming, reload, progress, 0.0)
				model.body._pose(1.0 / 60.0)
			var right := model.weapon.to_global(POSES.GRIPS[model.weapon_id])
			check(hand_position(model, 0).distance_to(right) < .035, "tier%d %s right glove on actual weapon grip" % [tier, mode])
			var targets: Array = model.weapon_hand_contacts()
			if targets[1] is Vector3:
				check(hand_position(model, 1).distance_to(targets[1]) < .035, "tier%d %s support/reload hand reaches its physical target" % [tier, mode])
			if not reload and (tier > 0 or aiming):
				check(hand_position(model, 1).distance_to(model.weapon.to_global(POSES.SUPPORT_GRIPS[model.weapon_id])) < .035, "tier%d %s left glove on actual foregrip" % [tier, mode])
			if aiming:
				check((-model.weapon.global_basis.z).normalized().dot((-model.global_basis.z).normalized()) > .97, "tier%d muzzle points forward, away from head" % tier)
			check(model.body.to_local(right).y < 1.46, "tier%d %s grip remains below eyes" % [tier, mode])
		model.update_pose(1.0, false, false, 0.0, 0.0)
		model.body._pose(.016)
	await capture("01-five-tier-low-ready")
	for model in models:
		model.update_pose(1.0, true, false, 0.0, 0.0)
		model.body._pose(.016)
	await capture("02-five-tier-aim")
	camera.size = 2.9
	camera.position = Vector3(3.3, 2.2, -5.0)
	camera.look_at(Vector3(0, .95, 0))
	for index in models.size(): models[index].visible = index == 2
	await capture("02-swat-aim-close")
	var swat: Node3D = models[2]
	swat.update_pose(1.0, false, true, .25, 0.0)
	swat.body._pose(.016)
	await capture("02-swat-reload-fetch-close")
	swat.update_pose(1.0, false, true, .50, 0.0)
	swat.body._pose(.016)
	await capture("02-swat-reload-insert-close")
	for model in models: model.hide()
	var officer := OFFICER.new()
	officer.tier = 2
	scene.add_child(officer)
	officer.set_physics_process(false)
	var pose := RAPPLE.new()
	check(pose.configure(officer), "rappel drives actual anatomical officer rig")
	var rope_top := Vector3(.2, 6, -.2)
	for phase in ["attach", "descend", "land", "release"]:
		var contacts: Dictionary = {}
		for frame in 30: contacts = pose.update(1.0 / 60.0, phase, float(frame) / 30.0, rope_top)
		check(contacts.has("harness") and contacts.harness.distance_to(officer.visual.rappel_harness.global_position) < .001, "%s rope attaches to modeled descender" % phase)
		if phase in ["attach", "descend", "land"]:
			check(hand_position(officer.visual, 0).distance_to(contacts.upper_hand) < .001 and hand_position(officer.visual, 1).distance_to(contacts.lower_hand) < .001, "%s rope contact uses real solved glove endpoints" % phase)
			check(contacts.upper_hand.y > contacts.harness.y and contacts.lower_hand.y < contacts.harness.y + .05, "%s upper grip bears load and lower grip brakes" % phase)
		await capture("03-rappel-" + phase)
	pose.finish()
	pose.finish()
	officer.visual.update_pose(1.0, true, false, 0.0, 0.0)
	officer.visual.body._pose(.016)
	check(not officer.visual.rappel_pose_active and officer.visual.weapon.get_parent() == officer.visual, "rappel cleanup restores weapon parent and pose ownership once")
	check(hand_position(officer.visual, 0).distance_to(officer.visual.weapon.to_global(POSES.GRIPS["m4a1"])) < .035, "post-landing weapon stays in anatomical hand")
	await capture("04-landed-ready")
	print("OFFICER_POSE checks=%d failures=%s" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
