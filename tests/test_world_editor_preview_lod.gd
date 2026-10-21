extends SceneTree
const PANEL := preload("res://addons/geteco_world_editor/WorldLivePreview.gd")
const LOD := preload("res://addons/geteco_world_editor/WorldPreviewLOD.gd")
class Selection extends Node:
	var selected_id := ""
class Owner extends Node:
	var canvas: Selection
	var _merging_units := false
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func finish_lod(panel: Node) -> void:
	for frame in 120:
		if not panel.lod_updating: return
		await process_frame
func mesh(parent: Node,id: String,extent: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = Vector3.ONE*extent
	node.mesh = shape
	node.layers = 4
	node.set_meta("editor_id",id)
	parent.add_child(node)
	return node
func run() -> void:
	var panel := PANEL.new()
	root.add_child(panel)
	var owner := Owner.new()
	owner.canvas = Selection.new()
	root.add_child(owner)
	owner.add_child(owner.canvas)
	panel.editor_owner = owner
	panel.geometry = Node3D.new()
	panel.scene_root.add_child(panel.geometry)
	var tiny := mesh(panel.geometry,"piece/tiny",.1)
	var large := mesh(panel.geometry,"piece/large",100.0)
	check(await LOD.prepare(weakref(panel),weakref(panel.geometry),self),"LOD prepares the real snapshot in bounded slices")
	panel.built_radius = -1
	panel.surface.size = Vector2(900,600)
	panel.view_size = 2000.0
	panel._pose()
	await finish_lod(panel)
	check(bool(tiny.get_meta("world_preview_lod_hidden",false)) and tiny.layers == 4 and tiny.visible,"Subpixel culling preserves authored layers and Node visibility for picking")
	check(large.layers == 4,"Large visible structures retain their authored render layers")
	check(tiny.get_meta("world_snapshot_visual_layers") == 4,"The original layers survive for copying and restoration")
	var generation: int = panel.lod_revision
	panel.yaw += .2
	panel._pose()
	check(panel.lod_revision == generation,"Orbiting does not scan every world mesh each frame")
	owner.canvas.selected_id = "piece/tiny"
	panel.refresh_lod_selection()
	await finish_lod(panel)
	check(not bool(tiny.get_meta("world_preview_lod_hidden",false)) and tiny.layers == 4,"A selected object remains visible regardless of projected size")
	owner.canvas.selected_id = ""
	panel.view_size = 1.0
	panel._pose()
	await finish_lod(panel)
	check(not bool(tiny.get_meta("world_preview_lod_hidden",false)) and tiny.layers == 4,"Zooming restores server visibility with the exact authored layers")
	panel.view_size = 2000.0
	panel.built_radius = 0
	panel._pose()
	await finish_lod(panel)
	check(tiny.layers == 4 and not panel.lod_metrics.whole,"Nearby editing always renders authored details")
	panel.free()
	owner.free()
	print("WORLD_EDITOR_PREVIEW_LOD checks=",checks," failures=",failures)
	quit(1 if failures else 0)
