extends "res://evidence/world-editor-20260925/capture_library_assets.gd"
const GROUND := preload("res://world/editing/WorldGroundFactory.gd")
func run() -> void:
	root.get_node("BuildWatermark").hide()
	root.get_node("V2Settings").show_fps = false
	root.get_node("V2Settings")._update_fps_overlay()
	output = SubViewport.new()
	output.size = Vector2i(1400,760)
	output.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(output)
	var background := ColorRect.new()
	background.color = Color("19252c")
	output.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	output.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	var content := VBoxContainer.new()
	margin.add_child(content)
	heading(content,"Terrenos e pisos",26)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",16)
	content.add_child(grid)
	for index in GROUND.SURFACES.size():
		var row := {"id":"capture","position":[0,0],"size":[8,8],"rotation":0,"surface":GROUND.SURFACES[index],"model":GROUND.SURFACES[index]}
		card(grid,{"label":GROUND.LABELS[index],"row":row},GROUND.create(row,Rect2(-8,-8,16,16)),322,310)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	output.get_texture().get_image().save_png("res://evidence/world-editor-20260925/ground-materials.png")
	print("GROUND_CAPTURE complete")
	quit()
