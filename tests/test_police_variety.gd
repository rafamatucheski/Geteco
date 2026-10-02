extends SceneTree
## Visible body geometry must preserve the authored weight differences.
const MODEL := preload("res://gameplay/PoliceModel.gd")
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
const POSES := preload("res://gameplay/WeaponPoseData.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var models: Array = []
	for index in 10:
		var model := MODEL.new()
		model.appearance_index = index
		host.add_child(model)
		model._install_body()
		model.equip("pistol")
		model.body.set_process(false)
		models.append(model)
		check(model.body.spine.is_visible_in_tree(), "profile %d uses visible body" % index)
		for mode in ["rest", "aim", "reload"]:
			for frame in 60:
				model.update_pose(1.0 / 60.0, mode == "aim", mode == "reload", .5, 0.0)
				model.body._pose(1.0 / 60.0)
			var hand: Vector3 = model.body.forearms[0].to_global(Vector3(0, -KIT.FOREARM - .06, 0))
			check(hand.distance_to(model.weapon.to_global(POSES.GRIPS.pistol)) < .035, "profile %d %s hand reaches pistol" % [index, mode])
			if mode == "rest":
				var local_hand: Vector3 = model.body.to_local(hand)
				check(absf(local_hand.x) > float(model.body.wardrobe.body_profile.waist.x) + .05, "profile %d resting grip clears belly" % index)
		check(model.body.head_node.scale.is_equal_approx(model.body.wardrobe.head_scale), "profile %d retains head proportions during animation" % index)
		var arrays: Array = model.body.head_node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var scalp_top := -INF
		var cap_top := -INF
		for vertex_index in vertices.size():
			var slot := int(colors[vertex_index].r * 16.0)
			if slot in [KIT.SLOT_SKIN, KIT.SLOT_HAIR]: scalp_top = maxf(scalp_top, vertices[vertex_index].y)
			if slot == KIT.SLOT_ACCENT: cap_top = maxf(cap_top, vertices[vertex_index].y)
		check(cap_top > scalp_top + .015, "profile %d scalp and hair remain beneath cap crown" % index)
	var slim: AABB = models[0].body.spine.mesh.get_aabb()
	for index in [2, 5]:
		var heavy: AABB = models[index].body.spine.mesh.get_aabb()
		check(heavy.size.x > slim.size.x * 1.20, "heavy %d visibly wider than slim" % index)
		check(heavy.end.z > slim.end.z * 1.35, "heavy %d has a projected belly" % index)
	check(models[2].body.head_node.mesh != models[5].body.head_node.mesh, "heavy officers have different faces/facial hair")
	var replacement := MODEL.new()
	replacement.appearance_index = 5
	host.add_child(replacement)
	replacement._install_body()
	check(replacement.body.spine.mesh == models[5].body.spine.mesh, "recreated identity reuses body mesh")
	check(replacement.body.head_node.mesh == models[5].body.head_node.mesh, "recreated identity keeps face")
	var civilian := preload("res://assets/CivilianModel.gd").new()
	host.add_child(civilian)
	var w: Dictionary = civilian.wardrobe
	check(civilian.spine.mesh == KIT.chest_mesh(KIT.build_profile(w.female, w.build), w.top, w.backpack, -w.bag), "unmodified civilian uses original geometry")
	print("POLICE_VARIETY checks=%d failures=%s" % [checks, failures])
	host.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
