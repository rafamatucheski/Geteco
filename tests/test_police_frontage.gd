extends "res://tests/test_world_editor_service_buildings.gd"
var frontage_checked := false

func _initialize() -> void:
	# Exercise the saved, shipped layout rather than a synthetic editor document.
	run.call_deferred()

func capture(label: String) -> void:
	if label == "exterior" and not frontage_checked:
		frontage_checked = true
		var row: Dictionary = preload("res://world/editing/WorldServiceBuildings.gd").row_for("harbor_police")
		check(DATA.validate_entity(row).is_empty(), "current shallow precinct accepted by editor")
		var invalid := row.duplicate(true)
		invalid.size[1] = 9.9
		check(not DATA.validate_entity(invalid).is_empty(), "depth below safe vestibule limit rejected")
		invalid = row.duplicate(true)
		invalid.size[0] = 10.0
		check(not DATA.validate_entity(invalid).is_empty(), "narrow entrance still rejected")
		var facade := find_facade()
		check(facade.building_size.is_equal_approx(Vector2(18,10)), "dressing uses current broad shallow footprint")
		for body in facade.find_children("*", "CollisionObject3D", true, false):
			check(body.global_basis.get_scale().is_equal_approx(Vector3.ONE), "rigid resized body " + str(body.name))
		var space := world.get_world_3d().direct_space_state
		var box := BoxShape3D.new()
		box.size = Vector3(1,3,3)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = box
		query.collision_mask = 1
		for x in range(56,76):
			query.transform.origin = Vector3(x,1.7,132.1)
			var blockers: Array[String] = []
			for hit in space.intersect_shape(query,32):
				if hit.collider is StaticBody3D: blockers.append(str(hit.collider.get_path()))
			check(blockers.is_empty(), "road lane clear at x="+str(x)+" "+str(blockers))
	if DisplayServer.get_name() == "headless": return
	var folder := "res://evidence/police-frontage-20260928/access"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder+"/"+label+".png") == OK, "capture "+label)
