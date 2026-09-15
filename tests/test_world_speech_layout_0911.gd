extends SceneTree
const LAYOUT = preload("res://ui/WorldSpeechLayout.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	root.size = Vector2i(900,600)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var actors: Array[Node2D] = []
	var panels: Array[PanelContainer] = []
	for i in 10:
		var actor := Node2D.new()
		world.add_child(actor)
		actor.position = Vector2(35 + i * 60, 130)
		var panel := PanelContainer.new()
		var label := Label.new()
		label.text = "CUIDADO!"
		panel.add_child(label)
		actor.add_child(panel)
		LAYOUT.show_for(actor, panel, 3.0)
		actors.append(actor)
		panels.append(panel)
	await process_frame
	var layout = world.get_node("WorldSpeechLayout")
	layout.set_process(false)
	for zoom in [0.65,1.0,2.0]:
		root.canvas_transform = Transform2D(0,Vector2(40,30)).scaled(Vector2.ONE * zoom)
		layout._process(0.0)
		var rects: Array[Rect2] = []
		for panel in panels:
			if not panel.visible: continue
			var rect := panel.get_global_rect()
			for other in rects: check(not rect.intersects(other), "speech overlap at zoom " + str(zoom))
			check(root.get_visible_rect().encloses(rect), "speech stays on screen")
			rects.append(rect)
		check(rects.size() > 0 and rects.size() <= 4, "bounded readable crowd")
	LAYOUT.show_for(actors[9],panels[9],5.0)
	layout._process(3.1)
	check(panels[9].visible, "refresh survives previous expiry")
	actors[9].queue_free()
	await process_frame
	layout._process(0.0)
	await process_frame
	check(not is_instance_valid(panels[9]), "speaker deletion releases reparented panel")
	print("WORLD_SPEECH_LAYOUT failures=", failures)
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
