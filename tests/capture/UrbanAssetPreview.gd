extends SceneTree
const LIB := preload("res://addons/geteco_world_editor/WorldAssetLibrary.gd")
const BUILD := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
var output: SubViewport
var thumbnail_views: Dictionary = {}
func _initialize() -> void: run.call_deferred()
func run() -> void: quit(2)
func bounds(node: Node, result: Array) -> void:
	if node is MeshInstance3D and node.mesh != null: result.append(node.global_transform*node.mesh.get_aabb())
	elif node is MultiMeshInstance3D and node.multimesh != null:
		for index in node.multimesh.instance_count:
			result.append(node.global_transform*node.multimesh.get_instance_transform(index)*node.multimesh.mesh.get_aabb())
	for child in node.get_children(): bounds(child,result)
func heading(parent: Node, text: String, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("e1e7eb"))
	parent.add_child(label)
func building(row: Dictionary, serial: int) -> Node3D:
	return BUILD.build_building({"id":"library_preview_%d" % serial,"kind":row.model,"size":Vector2(row.size[0],row.size[1]),"height_override":row.height,"color":row.color,"position":Vector3.ZERO,"original_name":""})
func card(parent: Node, entry: Dictionary, model: Node3D, width: int, height: int) -> void:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(width,height)
	parent.add_child(panel)
	heading(panel,entry.label,18)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(width,height-30)
	panel.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(width,height-30)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	thumbnail_views[str(entry.row.model)] = viewport
	viewport.add_child(model)
	var parts: Array = []
	bounds(model,parts)
	var box: AABB = parts[0]
	for part in parts: box = box.merge(part)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(box.size.y,maxf(box.size.x,box.size.z))*1.75
	camera.near = .01
	camera.far = 500
	viewport.add_child(camera)
	camera.position = box.get_center()+Vector3(1.1,1.0,1.65).normalized()*camera.size*2.0
	camera.look_at(box.get_center(),Vector3.UP)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("263441")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dbe3e7")
	environment.ambient_light_energy = .85
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-30,0)
	light.light_energy = 1.2
	viewport.add_child(light)
