extends SceneTree
const PANEL := preload("res://addons/geteco_world_editor/WorldLivePreview.gd")
const LOD := preload("res://addons/geteco_world_editor/WorldPreviewLOD.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(900,600)
	var panel := PANEL.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.geometry = Node3D.new()
	panel.scene_root.add_child(panel.geometry)
	var shared := BoxMesh.new()
	shared.size = Vector3.ONE*.1
	var meshes: Array[MeshInstance3D] = []
	for index in 120:
		var node := MeshInstance3D.new()
		node.mesh = shared
		node.layers = 4
		node.position = Vector3((index%12)*.12,0,(index/12)*.12)
		node.set_meta("editor_id","piece/light_repro/%d" % index)
		panel.geometry.add_child(node)
		meshes.append(node)
	var light := OmniLight3D.new()
	light.light_cull_mask = 4
	light.omni_range = 10.0
	light.shadow_enabled = true
	panel.geometry.add_child(light)
	check(await LOD.prepare(weakref(panel),weakref(panel.geometry),self),"Lit shared geometry enters the real preview LOD index")
	panel.built_radius = -1
	panel.focus = Vector3.ZERO
	for index in 30:
		panel.view_size = 2000.0 if index%2 == 0 else 2.0
		panel._pose()
		await process_frame
	panel.view_size = 2000.0
	panel._pose()
	for frame in 10: await process_frame
	check(meshes.all(func(node): return node.layers == 4 and node.visible and node.mesh == shared),"Repeated LOD transitions never modify node visibility, render layers or shared resources")
	check(meshes.all(func(node): return bool(node.get_meta("world_preview_lod_hidden",false))),"The final frame exercises light teardown while subpixel geometry is culled")
	# A issue 121989 do Godot upstream emitia antes erros do renderizador exatamente
	# nesta transição depois de modificar máscaras de camada da geometria. Mantém renderizado.
	light.free()
	for frame in 3:
		panel._render_once()
		await process_frame
	panel.free()
	print("WORLD_EDITOR_LOD_LIGHT_TEARDOWN checks=",checks," failures=",failures)
	# Also exercise immediate host free + process quit with pending retirements.
	quit(1 if failures else 0)
