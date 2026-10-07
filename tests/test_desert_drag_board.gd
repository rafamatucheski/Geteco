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
	var board := BOARD.new()
	root.add_child(board)
	board.position=Vector2(190,40)
	var state: Dictionary={}
	board.show_progress(PROGRESS.data(state))
	check(board.rows.size()==5 and board.current=="digo" and not board.race_button.disabled,"five selectable rivals; first opponent can race")
	board.rows[2].pressed.emit()
	check(board.selected=="raul" and board.race_button.disabled,"click previews a locked rival without bypassing progression")
	PROGRESS.record_finish(state,"digo",false,22)
	board.show_progress(PROGRESS.data(state))
	check(board.wins.is_empty() and board.strike.is_empty(),"defeat does not strike the name")
	PROGRESS.record_finish(state,"digo",true,21)
	board.show_progress(PROGRESS.data(state),"digo")
	check(board.current=="livia" and board.strike.digo==0.0,"real progress unlocks next rival; new strike begins unpainted")
	await create_timer(1.1).timeout
	check(is_equal_approx(board.strike.digo,1.0),"handwritten victory strike completes")
	var restored: Dictionary=JSON.parse_string(JSON.stringify(PROGRESS.data(state)))
	board.show_progress(restored)
	check(PROGRESS.validate_snapshot(restored) and board.strike.digo==1.0,"restored save preserves crossed-out winner")
	board.rows[1].pressed.emit()
	check(board.selected=="livia" and not board.race_button.disabled,"click selects current rival")
	var requests: Array[String]=[]
	board.race_requested.connect(func(id: String): requests.append(id))
	board.race_button.pressed.emit()
	check(requests==["livia"],"race button emits selected identity without modifying save")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var folder := "res://evidence/desert-drag-board"
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder+"/board.png")
	board.free()
	quit(0 if failures.is_empty() else 1)
