extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var mission = load("res://district/harbor_preview/campaign/HarborArrivalMission.gd").new()
	root.add_child(mission)
	mission.set_process(false)
	paused = true
	for stream in [ProceduralAudio.get_mission_start_stream(), ProceduralAudio.get_powerup_stream(), ProceduralAudio.get_mission_passed_stream()]:
		mission._play_mission_feedback(stream)
		var sound := mission.get_child(mission.get_child_count() - 1) as AudioStreamPlayer
		assert(sound.playing and not sound.stream_paused, "Mission feedback must play even during dialogue pause")
		assert(sound.stream == stream)
	paused = false
	mission.queue_free()
	var forest_parent := Node2D.new()
	root.add_child(forest_parent)
	load("res://district/mountain_pass/MountainSceneryBuilder.gd").build_dense_pine_forest(forest_parent, null, true)
	forest_parent.free()
	await process_frame
	await process_frame
	print("MISSION_FEEDBACK_PAUSE_AND_STREAM_CANCEL PASS")
	quit()
