@tool
extends RefCounted
## Awaiting belongs to a static job, not to a panel which the user can close.
static func run(panel_ref: WeakRef, epoch: int, tree: SceneTree) -> void:
	var panel: Node = panel_ref.get_ref()
	if panel == null or panel.assembly_epoch != epoch: return
	var response: Dictionary = panel.loading_response
	var metrics: Dictionary = panel.assembly_metrics
	var area := str(response.get("area",panel.submitted.get("area","harbor")))
	var began := Time.get_ticks_usec()
	if not str(response.get("interior_id","")).is_empty():
		panel.interior_units_ready.emit(str(response.interior_id),response.get("interior_units",[]))
	elif is_instance_valid(panel.editor_owner) and panel.editor_owner.has_method("_merge_unit"):
		await preload("res://addons/geteco_world_editor/WorldEditorUnitIndex.gd").run(weakref(panel.editor_owner),tree,area,response.get("units",[]))
	else: panel.units_ready.emit(area,response.get("units",[]))
	metrics.merge_ms = (Time.get_ticks_usec()-began)/1000.0
	panel = panel_ref.get_ref()
	if panel == null or panel.assembly_epoch != epoch or not is_instance_valid(panel.assembling): return
	began = Time.get_ticks_usec()
	var indexed := true
	if is_instance_valid(panel.edit_control):
		indexed = await preload("res://addons/geteco_world_editor/World3DEditIndex.gd").rebuild(weakref(panel.edit_control),weakref(panel.assembling),tree)
	metrics.index_ms = (Time.get_ticks_usec()-began)/1000.0
	panel = panel_ref.get_ref()
	if panel == null or panel.assembly_epoch != epoch: return
	if indexed: indexed = await preload("res://addons/geteco_world_editor/WorldPreviewLOD.gd").prepare(panel_ref,weakref(panel.assembling),tree)
	panel = panel_ref.get_ref()
	if panel == null or panel.assembly_epoch != epoch: return
	panel._complete_assembly(epoch,indexed)
