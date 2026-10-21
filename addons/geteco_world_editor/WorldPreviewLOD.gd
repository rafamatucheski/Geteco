@tool
extends RefCounted
const LAYER_META := "world_snapshot_visual_layers"
const HIDDEN_META := "world_preview_lod_hidden"
const HIDE_PIXELS := 1.15
const SHOW_PIXELS := 1.65

static func prepare(reference: WeakRef, source_ref: WeakRef, tree: SceneTree) -> bool:
	var panel = reference.get_ref()
	var source = source_ref.get_ref()
	if not is_instance_valid(panel) or not is_instance_valid(source): return false
	var epoch: int = panel.assembly_epoch
	var entries: Array = []
	var pending: Array = [[source,""]]
	var began := Time.get_ticks_usec()
	while not pending.is_empty():
		var item: Array = pending.pop_back()
		var node: Node = item[0]
		if node is Node3D and not node.visible and node != source: continue
		var id := str(node.get_meta("editor_id",item[1]))
		if node is MeshInstance3D and node.mesh != null:
			if not node.has_meta(LAYER_META): node.set_meta(LAYER_META,node.layers)
			entries.append({"node":node,"id":id,"bounds":node.mesh.get_aabb(),"layers":int(node.get_meta(LAYER_META))})
		for child in node.get_children(): pending.append([child,id])
		if Time.get_ticks_usec()-began > 3000:
			await tree.process_frame
			panel = reference.get_ref()
			if not is_instance_valid(panel) or not is_instance_valid(source_ref.get_ref()) or panel.assembly_epoch != epoch: return false
			began = Time.get_ticks_usec()
	panel.lod_entries = entries
	panel.lod_size = -1.0
	panel.lod_pixel_height = -1.0
	return true

static func selected(panel: Node) -> String:
	return str(panel.editor_owner.canvas.selected_id) if is_instance_valid(panel.editor_owner) and is_instance_valid(panel.editor_owner.canvas) else ""

static func request(panel: Node, force := false) -> void:
	if panel.camera == null or panel.surface == null: return
	var selection := selected(panel)
	var pixel_height := maxf(1.0,panel.surface.size.y)
	var active: bool = panel.built_radius < 0 and str(panel.built_interior).is_empty()
	if not force and panel.lod_selected == selection and panel.lod_active == active and panel.lod_size > 0 and absf(panel.view_size/panel.lod_size-1.0) < .05 and absf(pixel_height/panel.lod_pixel_height-1.0) < .05: return
	panel.lod_selected = selection
	panel.lod_size = panel.view_size
	panel.lod_pixel_height = pixel_height
	panel.lod_active = active
	panel.lod_revision += 1
	if not panel.lod_updating: update(weakref(panel),panel.get_tree())

static func update(reference: WeakRef, tree: SceneTree) -> void:
	var panel = reference.get_ref()
	if not is_instance_valid(panel): return
	panel.lod_updating = true
	while true:
		var generation: int = panel.lod_revision
		var epoch: int = panel.assembly_epoch
		var active: bool = panel.lod_active
		var selection: String = panel.lod_selected
		var scale: float = panel.lod_pixel_height/maxf(.1,panel.lod_size)
		var right: Vector3 = panel.camera.global_basis.x.abs()
		var up: Vector3 = panel.camera.global_basis.y.abs()
		var hidden := 0
		var shown := 0
		var began := Time.get_ticks_usec()
		var superseded := false
		for entry: Dictionary in panel.lod_entries:
			var node: MeshInstance3D = entry.node
			if not is_instance_valid(node): continue
			var extent: Vector3 = (node.global_transform*(entry.bounds as AABB)).size
			var pixels := maxf(right.dot(extent),up.dot(extent))*scale
			var threshold := SHOW_PIXELS if bool(node.get_meta(HIDDEN_META,false)) else HIDE_PIXELS
			var suppress: bool = active and not (not selection.is_empty() and str(entry.id) == selection) and pixels < threshold
			if bool(node.get_meta(HIDDEN_META,false)) != suppress:
				# Changing geometry layers corrupts light pair bookkeeping in the
				# project's Godot 4.7.2 renderer (upstream issue 121989). Toggle only
				# this instance's server visibility: Node.visible, layers, shared
				# resources and the editor's selection index remain untouched.
				RenderingServer.instance_set_visible(node.get_instance(),not suppress and node.is_visible_in_tree())
				node.set_meta(HIDDEN_META,suppress)
			if suppress: hidden += 1
			else: shown += 1
			if Time.get_ticks_usec()-began >= 3000:
				await tree.process_frame
				panel = reference.get_ref()
				if not is_instance_valid(panel): return
				if panel.assembly_epoch != epoch:
					panel.lod_updating = false
					return
				if panel.lod_revision != generation:
					superseded = true
					break
				began = Time.get_ticks_usec()
		if superseded: continue
		panel.lod_metrics = {"hidden":hidden,"shown":shown,"threshold_px":HIDE_PIXELS,"whole":active}
		panel.lod_updating = false
		panel._render_once()
		return
