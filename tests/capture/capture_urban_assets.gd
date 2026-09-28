extends "res://tests/capture/UrbanAssetPreview.gd"
const SKYLINE := preload("res://world/urban_detail/UrbanSkylineCatalog.gd")
const LOWRISE := preload("res://world/urban_detail/UrbanLowriseCatalog.gd")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.get_node("BuildWatermark").hide()
	root.get_node("V2Settings").show_fps = false
	root.get_node("V2Settings")._update_fps_overlay()
	output = SubViewport.new()
	output.size = Vector2i(1600,1700)
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
	content.add_theme_constant_override("separation",16)
	margin.add_child(content)
	heading(content,"GETECO · Prédios urbanos e torres",30)
	heading(content,"6 arquiteturas · 12 assets · largura × profundidade × altura em metros",20)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",18)
	grid.add_theme_constant_override("v_separation",18)
	content.add_child(grid)
	var serial := 0
	var lowrise := "--lowrise" in OS.get_cmdline_user_args()
	if lowrise:
		content.get_child(0).text = "GETECO · Casas e galpões"
		content.get_child(1).text = "4 arquiteturas · 8 assets · largura × profundidade × altura em metros"
		output.size = Vector2i(1600,1320)
	for entry in LIB.build({}):
		if entry.type != "building" or entry.row.model not in (LOWRISE.TYPES if lowrise else SKYLINE.TYPES): continue
		var row: Dictionary = entry.row
		var caption := entry.duplicate(true)
		caption.label += " · %s×%s×%s" % [row.size[0],row.size[1],row.height]
		card(grid,caption,building(row,serial),500,365)
		serial += 1
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://evidence/urban-assets-20260926"
	DirAccess.make_dir_recursive_absolute(folder)
	output.get_texture().get_image().save_png(folder+("/lowrise-catalog.png" if lowrise else "/catalog.png"))
	for model in thumbnail_views:
		var source: Image = thumbnail_views[model].get_texture().get_image()
		source.resize(128,96,Image.INTERPOLATE_LANCZOS)
		source.save_png("res://addons/geteco_world_editor/thumbnails/"+model+".png")
	print("URBAN_ASSETS_CAPTURE count=",serial," thumbnails=",thumbnail_views.size())
	quit(0 if serial == (8 if lowrise else 12) else 1)
