extends SceneTree
## Covers the actual reusable Control after an asynchronous paddock return.
## A directly emitted pressed signal bypasses disabled, so assert availability.
const PANEL := preload("res://activities/desert_drag/DragNightPanel.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	print("DRAG_NIGHT_PANEL ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _run() -> void:
	var panel := PANEL.new()
	root.add_child(panel)
	await process_frame
	var presets := {"rua":{},"drag":{},"terra":{}}
	for step in [1,2,3]:
		panel.set_busy(true)
		check(panel.buttons["continue"].disabled and panel.buttons.back.disabled,"paddock transition blocks navigation at step %d"%step)
		panel.show_state({"step":step,"has_episode":true,"rival_id":"digo"},"Digo","Faísca",presets)
		check(not panel.buttons["continue"].disabled and not panel.buttons.back.disabled,"reopening permits continue and back at step %d"%step)
		check(panel.buttons.prepare.disabled==(step==2),"only second 402 m pass locks preparation at step %d"%step)
		var presets_correct := true
		for identity in presets:
			presets_correct=presets_correct and panel.buttons["preset:"+identity].disabled==(step==2)
		check(presets_correct,"owned presets obey only the 402 m pairing lock at step %d"%step)
	panel.show_state({"step":3,"has_episode":true,"rival_id":"digo"},"Digo","Faísca",{"drag":{}})
	check(not panel.buttons["preset:drag"].disabled and panel.buttons["preset:rua"].disabled and panel.buttons["preset:terra"].disabled,"a missing preset remains unavailable after the transition reset")
	panel.show_state({"step":0,"has_episode":false,"rival_id":"digo"},"Digo","Faísca",{})
	check(panel.buttons.abandon.disabled and not panel.buttons["continue"].disabled,"a new night can start but cannot abandon a missing inscription")
	panel.queue_free()
	await process_frame
	print("DRAG_NIGHT_PANEL_DONE checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
