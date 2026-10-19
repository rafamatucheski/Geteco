extends SceneTree
const PANEL := preload("res://activities/desert_drag/DragRivalChallengePanel.gd")
const PROGRESS := preload("res://activities/desert_drag/DragRivalChallengeProgress.gd")
const RESULTS := preload("res://activities/desert_drag/DesertDragResults.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks+=1
	print("RIVAL_PANEL ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var panel := PANEL.new()
	root.add_child(panel)
	await process_frame
	var state := PROGRESS.status({},"digo")
	state.has_car=true
	panel.show_state(state)
	check(not panel.buttons.start.disabled and panel.buttons["step:1"].disabled,"new player can start first proof but cannot skip to the second")
	check(panel.buttons.install.disabled,"unearned gift cannot be collected from the panel")
	panel.set_busy(true)
	check(panel.buttons.start.disabled and panel.buttons.back.disabled,"return transition disables actions")
	panel.show_state(state)
	check(not panel.buttons.start.disabled and not panel.buttons.back.disabled,"reopening restores available actions")
	state=PROGRESS.status({},"rauhz")
	state.has_car=true
	panel.show_state(state)
	check(panel.buttons.start.disabled,"locked rival cannot be started by the card")
	var result_panel := RESULTS.new()
	root.add_child(result_panel)
	await process_frame
	result_panel.show_result({"challenge":true,"challenge_step":0,"challenge_success":true,"telemetry":{"launch":"BOA LARGADA","good_shifts":2,"splits":{"201":10.2}}},"Digo")
	check(result_panel.buttons[0].text=="PRÓXIMA PROVA" and result_panel.buttons[1].text=="VER DESAFIOS","successful first proof presents the next proof and workshop overview")
	check(result_panel.telemetry_button.visible,"real telemetry can be inspected")
	check(result_panel.buttons[2].find_next_valid_focus()==result_panel.telemetry_button,"keyboard focus reaches passage telemetry after the result actions")
	result_panel.telemetry_button.pressed.emit()
	check(result_panel.telemetry_open and not result_panel.buttons[0].disabled,"telemetry view keeps replay and navigation usable")
	result_panel.show_result({"challenge":true,"challenge_step":1,"challenge_success":false},"Digo")
	check(result_panel.buttons[0].text=="REPETIR PROVA" and not result_panel.telemetry_button.visible,"failed proof offers retry without inventing telemetry")
	check(result_panel.buttons[2].find_next_valid_focus()==result_panel.buttons[0],"keyboard skips the unavailable telemetry action")
	var night := preload("res://activities/desert_drag/DragNightPanel.gd").new()
	root.add_child(night)
	await process_frame
	night.show_state({"step":0,"rival_id":"digo","category":"street","has_episode":false},"Digo","Faísca",{})
	check(not night.buttons["category:street"].disabled and "✓" in night.buttons["category:street"].text,"category choice shows the selected cap before registration")
	night.show_state({"step":1,"rival_id":"digo","category":"street","has_episode":true},"Digo","Faísca",{})
	check(night.buttons["category:street"].disabled and night.buttons["category:livre"].disabled,"category is fixed during the four-pass episode")
	night.queue_free()
	panel.queue_free()
	result_panel.queue_free()
	await process_frame
	print("RIVAL_PANEL_DONE checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
