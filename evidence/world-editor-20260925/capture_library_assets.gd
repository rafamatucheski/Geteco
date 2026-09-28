extends SceneTree
const LIB := preload("res://addons/geteco_world_editor/WorldAssetLibrary.gd")
const BUILD := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const PROPS := preload("res://world/editing/WorldPropFactory.gd")
var failures: Array[String] = []
var output: SubViewport
var thumbnail_views: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func bounds(node: Node, result: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var box: AABB = node.global_transform*node.mesh.get_aabb()
		result.append(box)
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
	camera.size = maxf(box.size.y,maxf(box.size.x,box.size.z)) * 1.75
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
func run() -> void:
	root.get_node("BuildWatermark").hide()
	root.get_node("V2Settings").show_fps = false
	root.get_node("V2Settings")._update_fps_overlay()
	output = SubViewport.new()
	output.size = Vector2i(1600,1200)
	output.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(output)
	var bg := ColorRect.new()
	bg.color = Color("111d27")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	output.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	output.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",14)
	margin.add_child(content)
	heading(content,"Biblioteca de assets · modelos reais do jogo",28)
	heading(content,"6 famílias de prédios · dimensões e altura editáveis",20)
	var buildings := GridContainer.new()
	buildings.columns = 3
	buildings.add_theme_constant_override("h_separation",18)
	buildings.add_theme_constant_override("v_separation",12)
	content.add_child(buildings)
	var entries := LIB.build({})
	var seen := {}
	var serial := 0
	for entry in entries:
		if entry.type != "building": continue
		var model := building(entry.row,serial)
		serial += 1
		if not is_equal_approx(model.height,float(entry.row.height)) or not model.building_size.is_equal_approx(Vector2(entry.row.size[0],entry.row.size[1])): failures.append(entry.label+" ignores dimensions")
		print("BUILDING ",entry.label," class=",model.get_script().resource_path," height=",model.height," size=",model.building_size)
		if seen.has(entry.row.model): model.free(); continue
		seen[entry.row.model] = true
		card(buildings,entry,model,500,255)
	heading(content,"Objetos de rua · pallets, lixo, caixotes e barreiras",20)
	var props := GridContainer.new()
	props.columns = 4
	props.add_theme_constant_override("h_separation",16)
	props.add_theme_constant_override("v_separation",12)
	content.add_child(props)
	seen.clear()
	for entry in entries:
		if entry.type != "prop" or seen.has(entry.row.model): continue
		seen[entry.row.model] = true
		card(props,entry,PROPS.create(entry.row),372,210)
	for frame in 35: await process_frame
	await RenderingServer.frame_post_draw
	var capture := output.get_texture().get_image()
	capture.save_png("res://evidence/world-editor-20260925/library-assets.png")
	var thumbnail_folder := "res://addons/geteco_world_editor/thumbnails/"
	DirAccess.make_dir_recursive_absolute(thumbnail_folder)
	for model in thumbnail_views:
		var source: Image = thumbnail_views[model].get_texture().get_image()
		var crop_width := mini(source.get_width(), roundi(float(source.get_height())*4.0/3.0))
		var crop_height := mini(source.get_height(), roundi(float(crop_width)*3.0/4.0))
		var thumbnail := source.get_region(Rect2i((source.get_width()-crop_width)/2, (source.get_height()-crop_height)/2, crop_width, crop_height))
		thumbnail.resize(128,96,Image.INTERPOLATE_LANCZOS)
		var error := thumbnail.save_png(thumbnail_folder+str(model)+".png")
		if error != OK: failures.append("Thumbnail failed: "+str(model))
	print("THUMBNAILS exported=",thumbnail_views.size())
	print("LIBRARY_PREVIEW building_templates=",serial," errors=",failures)
	quit(0 if failures.is_empty() else 1)
