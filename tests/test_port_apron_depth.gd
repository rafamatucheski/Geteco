extends SceneTree
## The port finish must never compete with road edges at the same depth.
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var region = preload("res://world/regions/NativeRegion.gd").new()
	region.initial_prewarm_only = true
	root.add_child(region)
	region.set_process(false)
	var chunk := Node3D.new()
	region.add_child(chunk)
	region._build_surfaces(chunk, Rect2(256,192,64,64), Vector2i(4,3))
	var apron := chunk.get_node_or_null("SouthPortConcrete") as MeshInstance3D
	check(apron != null,"Port apron is present in the production surface builder")
	if apron != null:
		var top: float = apron.position.y + (apron.mesh as BoxMesh).size.y * .5
		check(top > 0,"Port finish stays above the physical quay")
		for layer in region.harbor_road_geometry._layers:
			check(top + .003 <= float(layer.y),"Port finish is separated from road layer " + str(layer.name))
		check(apron.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Flat apron does not cast shadows onto road borders")
		check(apron.get_child_count() == 0,"Visual apron adds no raised collision lip")
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(280,2,220),Vector3(280,-1,220),1)
	var hit := root.world_3d.direct_space_state.intersect_ray(query)
	check(not hit.is_empty(),"Production quay retains physical support")
	if not hit.is_empty(): check(absf(hit.position.y) < .001,"Quay collision stays at its original ground height")
	region.queue_free()
	await process_frame
	print("PORT_APRON_DEPTH failures=", failures)
	quit(0 if failures.is_empty() else 1)
