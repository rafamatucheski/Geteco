extends SceneTree
const SOURCES := preload("res://runtime/cold/OriginalHeatSources.gd")
const ART := preload("res://runtime/cold/FireArt.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func _run() -> void:
	var view := preload("res://runtime/cold/HeatPresentation.gd").new()
	root.add_child(view)
	for source in SOURCES.SOURCES:
		var point := SOURCES.to_world(source.point)
		view.update_sources(1, point, true, false, 2)
		await physics_frame
		check(view.visuals.size() == 1, str(source.id) + " exactly one streamed heat source")
		if not view.visuals.has(source.id): quit(1); return
		var fire: Node3D = view.visuals[source.id]
		check(fire.find_children("*", "Light3D", true, false).is_empty(), str(source.id) + " no extra exterior light pass")
		check(fire.find_children("CharredFirewoodAndCoals", "MeshInstance3D", true, false).size() == 1, str(source.id) + " one detailed fuel bed")
		check(not fire.find_children("*", "StaticBody3D", true, false).is_empty(), str(source.id) + " heat source physically solid")
		for part in fire.find_children("*", "MeshInstance3D", true, false):
			if str(part.name) not in ["CharredFirewoodAndCoals", "OpenIronFireBowl", "FirepitStoneRing"]: continue
			var local: Transform3D = fire.global_transform.affine_inverse() * part.global_transform
			var bounds: AABB = local * part.get_aabb()
			var radius := .73 if source.id == "resort_brazier" else .67
			check(maxf(absf(bounds.position.x), absf(bounds.end.x)) <= radius + .01 and maxf(absf(bounds.position.z), absf(bounds.end.z)) <= radius + .01, str(source.id) + " fire geometry stays within collision footprint " + str(part.name))
		check(SOURCES.nearest(point).id == source.id, str(source.id) + " same thermal identity and position")
		var tongues := 0
		for node in fire.find_children("*", "MeshInstance3D", true, false):
			if node.mesh == ART.flame_mesh(): tongues += 1
		check(tongues == 5, str(source.id) + " five shared curved flame tongues")
		view.update_sources(1, point, true, false, 2)
		check(view.visuals[source.id] == fire, str(source.id) + " steady streaming reuses same instance")
		view.update_sources(1, Vector3.ZERO, false)
		await process_frame
		check(view.visuals.is_empty() and not is_instance_valid(fire), str(source.id) + " unload removes presentation")
	# Real native provider must retain ownership and not duplicate the fuel bed.
	var lake := preload("res://world/regions/NativeLake.gd").new()
	lake.variant = "secret"
	lake.position = SOURCES.to_world(Vector2(5450, -1150))
	root.add_child(lake)
	var provider: Node3D = lake.find_child("OriginalCampHeatSource", true, false)
	check(is_instance_valid(provider), "native smuggler heat provider exists")
	var point := SOURCES.to_world(Vector2(5655, -990))
	view.update_sources(1, point, true, false, 2)
	check(view.visuals.smuggler_camp.get_meta("reuses_native_heat_source", false), "native source borrowed without duplicate pit")
	check(lake.find_children("CharredFirewoodAndCoals", "MeshInstance3D", true, false).size() == 1, "native source owns one fuel bed")
	view.update_sources(1, point, false)
	await process_frame
	check(is_instance_valid(provider), "unload wrapper preserves native source")
	lake.free()
	view.free()
	for path in ["res://runtime/cold/HearthEffects.gd", "res://assets/regions/source/world/mountain_pass/MountainHearthEffects3D.gd"]:
		var effect: Node3D = load(path).new()
		root.add_child(effect)
		check(effect.flames.size() == 5 and effect.wisps.size() == 7, path + " unchanged effect count")
		check(effect.flames[0].mesh == ART.flame_mesh(), path + " shared modern flame mesh")
		var lights := effect.find_children("*", "Light3D", true, false)
		check(lights.size() == (1 if path.contains("MountainHearth") else 0), path + " unchanged lighting ownership")
		effect.free()
	print("FIRE_FINISH checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
