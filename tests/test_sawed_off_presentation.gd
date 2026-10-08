extends "res://tests/test_firearm_rig.gd"
## Focused regression on the compact grip and articulated reload, using Dante's
## actual skeleton and meshes. No FPS or visual-quality claim from headless.
const SAWED = preload("res://gameplay/SawedOffPresentation.gd")
var _model: Node3D

func run() -> void:
	actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	root.add_child(actor)
	actor.set_physics_process(false)
	await process_frame
	var arrays: Array = actor._combat_skin.mesh.surface_get_arrays(0)
	_verts = arrays[Mesh.ARRAY_VERTEX]
	_norms = arrays[Mesh.ARRAY_NORMAL]
	_bones = arrays[Mesh.ARRAY_BONES]
	_weights = arrays[Mesh.ARRAY_WEIGHTS]
	_per = _bones.size() / _verts.size()
	_model = Node3D.new()
	root.add_child(_model)
	ARSENAL.build(_model, "sawed_off")
	var barrels := _model.get_node_or_null("BreakActionBarrels") as Node3D
	check(barrels != null and barrels.find_children("*", "MeshInstance3D", true, false).size() > 0, "barrels retain real moving geometry after finishing")
	check(not _model.has_node("Pump"), "compact double barrel has no pump")
	check(DATA.SUPPORT_GRIPS.sawed_off.distance_to(DATA.GRIPS.sawed_off) < 0.06, "support hand wraps pistol grip")
	var chamber_l := _model.get_node("BreakActionBarrels/ChamberLeft") as Node3D
	var chamber_r := _model.get_node("BreakActionBarrels/ChamberRight") as Node3D
	check(chamber_l.position.x < 0 and chamber_r.position.x > 0 and is_equal_approx(chamber_l.position.z, chamber_r.position.z), "two distinct side-by-side chambers remain after batching")
	var closed := chamber_l.global_position
	SAWED.update_parts(_model, SAWED.reload_open(SAWED.EJECT_AT))
	check(chamber_l.global_position.distance_to(closed) > 0.015, "breech opens before spent cases leave")
	SAWED.update_parts(_model, SAWED.reload_open(1.0))
	check(chamber_l.global_position.is_equal_approx(closed), "reload closes barrels exactly")
	var pose = POSE.new()
	for state in [["rest", Vector3.ZERO, 0.0, false, false], ["aim", Vector3.ZERO, 0.0, true, false],
		["fire", Vector3.ZERO, 0.0, true, false],
		["run", Vector3.FORWARD, 6.5, false, false], ["strafe aim", Vector3.RIGHT, 2.3, true, false],
		["reload", Vector3.ZERO, 0.0, false, true], ["reload running", Vector3.FORWARD, 6.5, false, true]]:
		var defects := {}
		var penetration := -INF
		var contact_error := 0.0
		var packet := {}
		for frame in 90:
			if state[0] == "fire" and frame in [30, 60]: pose.attack("sawed_off")
			var speed: float = state[2]
			var direction: Vector3 = state[1]
			actor.combat_facing = 0.0 if state[3] else NAN
			actor.visual.rotation.y = 0.0
			actor._pose_locomotion(direction, speed if speed > 0 else 3.5, direction * speed * DT, speed, DT)
			var progress := clampf(float(frame - 20) / 65.0, 0.0, 1.0)
			packet = pose.update("sawed_off", DT, state[3], state[4] and progress < 1.0, progress, speed > 0.1, speed > 4.2, actor.phase, actor.combat_rig_info())
			actor.set_combat_weapon_pose("sawed_off", packet)
			actor._apply_combat_weapon_pose()
			_model.global_transform = actor.combat_weapon_transform(DATA.GRIPS.sawed_off)
			SAWED.update_parts(_model, packet.break_open)
			if frame < 25: continue
			for defect in anatomy_defects(): defects[defect] = int(defects.get(defect, 0)) + 1
			if packet.support_locked:
				contact_error = maxf(contact_error, actor.combat_palm_position("Left").distance_to(_model.to_global(packet.support_point)))
			if frame % 16 == 0:
				_gun_points = _current_points()
				penetration = maxf(penetration, _skin_penetration("sawed_off", bool(packet.left_grip) and float(packet.support_weight) > 0.5))
		check(defects.is_empty(), "%s anatomy remains valid %s" % [state[0], defects])
		check(penetration <= SKIN_TOLERANCE, "%s skin penetration %.3f m" % [state[0], penetration])
		check(contact_error < 0.05, "%s supporting palm contacts handle %.3f m" % [state[0], contact_error])
		if state[0] in ["rest", "run"]:
			check(not packet.left_grip and not packet.support_locked and packet.right_grip, "%s carries from firing hand only" % state[0])
		if state[0] == "aim": check(packet.left_grip and not packet.long_weapon, "aim is a compact handgun grip")
	_model.free()
	_test_moving_parts()
	actor.queue_free()
	print("SAWED_OFF_PRESENTATION checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

func _current_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for child in _model.find_children("*", "MeshInstance3D", true, false):
		var part := child as MeshInstance3D
		var local := _model.global_transform.affine_inverse() * part.global_transform
		var faces := part.mesh.get_faces()
		for i in range(0, faces.size(), 3): points.append(local * faces[i])
	return points

func _test_moving_parts() -> void:
	var gameplay = preload("res://gameplay/Gameplay.gd").new()
	gameplay.player = actor
	var gun := Node3D.new()
	root.add_child(gun)
	gameplay.gun = gun
	ARSENAL.build(gun, "pistol")
	var slide := gun.get_node_or_null("Slide") as Node3D
	check(slide != null and slide.get_child_count() > 0, "pistol slide and its sights survive finishing")
	if slide != null:
		var slide_rest := slide.position
		var details := slide.get_child(0) as Node3D
		var detail_rest := details.global_position
		var pistol_pose = POSE.new()
		gameplay._pose_frame = pistol_pose.update("pistol", DT, false, true, 0.765, false, false, 0.0)
		gameplay._update_weapon_parts("pistol")
		check(slide.position.distance_to(slide_rest) > 0.03 and (details.global_position - detail_rest).is_equal_approx(slide.position - slide_rest), "reload pose moves slide and sights through actual gameplay hook")
		gameplay._pose_frame = {"slide": 0.0}
		gameplay._update_weapon_parts("pistol")
		check(slide.position.is_equal_approx(slide_rest), "pistol slide returns to battery")
	gun.free()
	gun = Node3D.new()
	root.add_child(gun)
	gameplay.gun = gun
	ARSENAL.build(gun, "ak47")
	var magazine := gun.get_node_or_null("CurvedMagazine") as Node3D
	check(magazine != null, "AK magazine survives geometry batching")
	if magazine != null:
		var rest := magazine.transform
		gameplay._reload_total = 1.0
		gameplay.reload_timer = 0.76
		gameplay._update_weapon_parts("ak47")
		check(not magazine.visible, "empty AK magazine leaves the gun during reload")
		gameplay.reload_timer = 0.0
		gameplay._update_weapon_parts("ak47")
		check(magazine.visible and magazine.transform.is_equal_approx(rest), "loaded AK magazine returns to its seat")
	gun.free()
	gameplay.free()
