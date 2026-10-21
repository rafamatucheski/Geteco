@tool
extends RefCounted
## The async job outlives a closed panel without ever resuming a freed Control.
## Private arrays become the public selection index only when the job completes.
static func rebuild(control_ref: WeakRef, source_ref: WeakRef, tree: SceneTree) -> bool:
	var control: Variant = control_ref.get_ref()
	var source: Variant = source_ref.get_ref()
	if not is_instance_valid(control) or not is_instance_valid(source): return false
	if not is_instance_valid(control.editor): return false
	control.index_revision += 1
	var request: int = control.index_revision
	control.cancel()
	var next_meshes: Array = []
	var next_groups := {}
	var pending: Array = [[source,""]]
	var began := Time.get_ticks_usec()
	while not pending.is_empty():
		control = control_ref.get_ref()
		source = source_ref.get_ref()
		if not is_instance_valid(control) or not is_instance_valid(source): return false
		if not is_instance_valid(control.editor) or request != control.index_revision: return false
		var entry: Array = pending.pop_back()
		var node: Node = entry[0]
		if not is_instance_valid(node): continue
		# The replacement root may be hidden until assembly/indexing is complete.
		# Descendants keep their authored local visibility and hidden subtrees prune.
		if node is Node3D and not node.visible and node != source: continue
		var id := str(node.get_meta("editor_id",entry[1]))
		if node.has_meta("editor_id") and control.editor.canvas.objects.has(id):
			if not next_groups.has(id): next_groups[id] = []
			next_groups[id].append(node)
		if node is MeshInstance3D and node.mesh != null:
			next_meshes.append({"node":node,"id":id,"bounds":node.mesh.get_aabb()})
		for child in node.get_children(): pending.append([child,id])
		if Time.get_ticks_usec()-began >= 4000:
			await tree.process_frame
			began = Time.get_ticks_usec()
	control = control_ref.get_ref()
	if not is_instance_valid(control) or not is_instance_valid(source_ref.get_ref()): return false
	if request != control.index_revision: return false
	control.meshes = next_meshes
	control.groups = next_groups
	control.triangles.clear()
	control.queue_redraw()
	return true
