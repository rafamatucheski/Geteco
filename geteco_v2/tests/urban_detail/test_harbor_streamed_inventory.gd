extends SceneTree
## Directed chunk-boundary validator for the productive Harbor inventory.
## It focuses every lot and its far visible edge; no save path is resolved.

const REGION := preload("res://world/regions/NativeRegion.gd")
const SCALE := 1.0 / 16.0

var failures := 0


func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Harbor streamed inventory validator refuses to run without --no-save")
		quit(2)
		return
	var region: Node3D = REGION.build_region("harbor")
	root.add_child(region)
	for frame in 16: await process_frame
	var checked := 0
	for data_value in region.buildings:
		var data := data_value as Dictionary
		var building_id := String(data.get("id", ""))
		if building_id == "Garage": continue # Root-owned Maciota place, outside NativeRegion.
		var center := data.position as Vector3
		var size := data.size as Vector2
		region.set_focus(center)
		for frame in 12: await process_frame
		var building := region.find_child(building_id, true, false) as Node3D
		check(building != null and is_instance_valid(building) and building.is_inside_tree(), "%s loads at its source lot" % building_id)
		if building != null:
			var meshes := building.find_children("*", "MeshInstance3D", true, false)
			check(building.find_children("V1SourceProjection", "MeshInstance3D", true, false).is_empty(), "%s never falls back to a 2D projection while streamed" % building_id)
			check(building.find_children("*", "SubViewport", true, false).is_empty(), "%s never creates a projection viewport while streamed" % building_id)
			check(meshes.size() >= 4, "%s keeps its composed native 3D model while streamed" % building_id)
			check(not building.find_children("*", "StaticBody3D", true, false).is_empty(), "%s keeps its 3D collision while streamed" % building_id)
		# Stand beyond the far visible edge. The centre chunk may change here, but
		# a still-visible source building must remain in one of the neighbour cells.
		var edge_focus := center + Vector3(minf(size.x * 0.5 + 8.0, 30.0), 0.0, 0.0)
		region.set_focus(edge_focus)
		for frame in 4: await process_frame
		building = region.find_child(building_id, true, false) as Node3D
		check(building != null and is_instance_valid(building) and not building.is_queued_for_deletion(), "%s does not disappear at its visible chunk edge" % building_id)
		checked += 1
	check(checked == 60, "all 60 NativeRegion buildings cross their visible chunk edge")
	print("HARBOR_STREAMED_INVENTORY checked=", checked, " failures=", failures)
	region.free()
	quit(1 if failures else 0)
