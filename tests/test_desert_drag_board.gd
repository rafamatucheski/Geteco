extends SceneTree
const BOARD := preload("res://activities/desert_drag/DesertDragBoard.gd")
const PROGRESS := preload("res://activities/desert_drag/DesertDragProgress.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	print("DRAG_BOARD ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	RenderingServer.set_default_clear_color(Color("080c11"))
	root.get_node("BuildWatermark").hide()
	root.get_node("V2Settings").show_fps=false
	root.get_node("V2Settings")._update_fps_overlay()
	var board := BOARD.new()
	root.add_child(board)
	board.position=Vector2(190,40)
	var state: Dictionary={}
	board.show_progress(PROGRESS.data(state))
	check(board.rows.size()==6 and board.current=="digo" and not board.race_button.disabled,"six selectable rivals; first opponent can race")
	board.rows[2].pressed.emit()
	check(board.selected=="raul" and board.race_button.disabled,"click previews a locked rival without bypassing progression")
	PROGRESS.record_finish(state,"digo",false,22)
	board.show_progress(PROGRESS.data(state))
	check(board.wins.is_empty() and board.current=="digo","defeat preserves the current opponent")
	PROGRESS.record_finish(state,"digo",true,21)
	board.show_progress(PROGRESS.data(state),"digo")
	check(board.current=="livia" and "digo" in board.wins,"real progress unlocks the next rival")
	check(board.selected=="digo" and not board.race_button.disabled and board.race_button.text.begins_with("REVANCHE"),"winner remains available for an immediate rematch")
	check(board.best.get("digo")==21.0,"board displays the personal best")
	var restored: Dictionary=JSON.parse_string(JSON.stringify(PROGRESS.data(state)))
	board.show_progress(restored)
	check(PROGRESS.validate_snapshot(restored) and "digo" in board.wins and not board.race_button.disabled,"restored save preserves rematch availability")
	board.rows[1].pressed.emit()
	check(board.selected=="livia" and not board.race_button.disabled,"click selects current rival")
	var requests: Array[String]=[]
	board.race_requested.connect(func(id: String): requests.append(id))
	board.race_button.pressed.emit()
	check(requests==["livia"],"race button emits selected identity without modifying save")
	board.rows[0].pressed.emit()
	board.race_button.pressed.emit()
	check(requests==["livia","digo"],"rematch emits the defeated rival identity")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var folder := "res://evidence/desert-drag-board"
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder+"/board.png")
		root.size=Vector2i(960,640)
		board.scale=Vector2.ONE*.96
		board.position=(Vector2(root.size)-Vector2(900,640)*board.scale)*.5
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/board-960.png")
	board.free()
	quit(0 if failures.is_empty() else 1)
