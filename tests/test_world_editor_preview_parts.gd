extends SceneTree
const PARTS := preload("res://addons/geteco_world_editor/WorldPreviewParts.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children(): count += count_nodes(child)
	return count

func run() -> void:
	var folder := "res://.godot/world_live_%d_parts_test" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(folder)
	var model := Node3D.new()
	model.name = "WorldPreviewGeometry"
	root.add_child(model)
	var mesh := BoxMesh.new()
	for block in 3:
		var holder := Node3D.new()
		holder.name = "Block_%d" % block
		holder.position = Vector3(block*10,2,-30)
		holder.rotation.y = .3
		holder.set_meta("editor_id","piece/block_%d" % block)
		model.add_child(holder)
		holder.owner = model
		for index in (500 if block == 0 else 30):
			var node := MeshInstance3D.new()
			node.name = "Thing_%d" % index
			node.mesh = mesh
			node.position = Vector3(index*.2,3,4)
			holder.add_child(node)
			node.owner = model
	var expected_count := count_nodes(model)
	var expected: Transform3D = model.get_node("Block_0/Thing_499").global_transform
	var result: Dictionary = await PARTS.write(model,folder,1,self,func(_phase,_done,_total,_force): pass,func(): return false)
	check(int(result.error) == OK,"Partitioned snapshot serializes successfully")
	check(result.parts.size() >= 3,"Large hierarchies are split into multiple bounded imports")
	var restored := (ResourceLoader.load(result.path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(restored)
	for row in result.parts:
		var part := (ResourceLoader.load(row.path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		check(count_nodes(part)-1 <= PARTS.MAX_PART_NODES,"Each part respects the maximum node count")
		var parent := restored.get_node(str(row.parent))
		PARTS.attach(part,parent)
		part.free()
	check(count_nodes(restored) == expected_count,"Assembly preserves every source node")
	check(restored.get_node("Block_0/Thing_499").global_transform.is_equal_approx(expected),"Assembly preserves nested transforms")
	check(restored.get_node("Block_0").get_meta("editor_id") == "piece/block_0","Assembly preserves inherited editor IDs")
	check(restored.get_node("Block_2/Thing_29").mesh != null,"Assembly retains mesh resources")
	check(restored.get_node("Block_0/Thing_499").owner == null,"Imported fragments never retain a freed temporary scene owner")
	check(restored.get_node("Block_0/Thing_0").mesh == restored.get_node("Block_2/Thing_29").mesh,"Shared generated meshes stay shared across imported parts")
	model.free()
	restored.free()
	# Persistent workers reuse procedural caches. A later revision must re-export
	# those resources, even if their old temporary resource_path is already set.
	var next := Node3D.new()
	next.name = "NextRevision"
	root.add_child(next)
	var item := MeshInstance3D.new()
	item.name = "ReusedMesh"
	item.mesh = mesh
	next.add_child(item)
	item.owner = next
	var second: Dictionary = await PARTS.write(next,folder,2,self,func(_phase,_done,_total,_force): pass,func(): return false)
	check(int(second.error) == OK,"A second worker revision re-exports cached generated resources")
	var independent := true
	for row in second.parts:
		for dependency in ResourceLoader.get_dependencies(row.path):
			if "view_1" in dependency: independent = false
	check(independent,"Later snapshots do not depend on deleted assets from older revisions")
	for filename in DirAccess.get_files_at(folder):
		if filename.begins_with("view_1"): DirAccess.remove_absolute(folder+"/"+filename)
	var second_part := ResourceLoader.load(second.parts[0].path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	check(second_part != null,"Rebuild loads with the previous revision removed and caches bypassed")
	if second_part != null:
		var second_scene := second_part.instantiate()
		check(second_scene.get_node("ReusedMesh").mesh != null,"Reused procedural mesh survives revision cleanup")
		second_scene.free()
	next.free()
	for filename in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder+"/"+filename)
	DirAccess.remove_absolute(folder)
	print("WORLD_EDITOR_PREVIEW_PARTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
