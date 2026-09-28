extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
var variant := "before"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--variant="): variant=argument.trim_prefix("--variant=")
	var folder := "res://evidence/port-logistics-20260928/editor-"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size=Vector2i(1440,900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=144
	var ui := UI.new()
	ui.draft_path="res://.godot/world_editor_freight_measure_unused.json"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 15: await process_frame
	ui._fit_world()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/full-map.png")
	ui.canvas.center=Vector2(-340,-55)
	ui.canvas.zoom=4.0
	var began := Time.get_ticks_usec()
	while Time.get_ticks_usec()-began<5000000:
		ui.canvas.center=Vector2(-340,-55)
		ui.canvas.zoom=4.0
		ui.canvas.queue_redraw()
		await process_frame
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	began=last
	while Time.get_ticks_usec()-began<30000000:
		ui.canvas.center=Vector2(-340,-55)
		ui.canvas.zoom=4.0
		ui.canvas.queue_redraw()
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-last)/1000.0)
		last=now
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/company-map.png")
	var ordered := samples.duplicate()
	ordered.sort()
	var total := 0.0
	var above33 := 0
	var above66 := 0
	for value in samples:
		total+=value
		if value>33.3: above33+=1
		if value>66.7: above66+=1
	var report := {"variant":variant,"frames":samples.size(),"duration_ms":total,"fps":samples.size()*1000.0/total,
		"p50_ms":ordered[int(ordered.size()*.5)],"p95_ms":ordered[int(ordered.size()*.95)],"p99_ms":ordered[int(ordered.size()*.99)],
		"max_ms":ordered[-1],"above_33ms":above33,"above_66ms":above66,"samples_ms":samples,"resolution":[1440,900],"vsync":false,"max_fps":144}
	var file := FileAccess.open(folder+"/metrics.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report))
	report.erase("samples_ms")
	print("EDITOR_FREIGHT_MEASURE ",JSON.stringify(report))
	ui._fit_world()
	ui.canvas.queue_redraw()
	for i in 5: await process_frame
	root.get_texture().get_image().save_png(folder+"/full-map.png")
	ui.free()
	for i in 3: await process_frame
	quit()
