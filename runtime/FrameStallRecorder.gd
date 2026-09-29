extends Node
## Bounded on-device evidence. Disk writes happen only after pausing/backgrounding.
var world: Node
var previous_usec := 0
var was_active := false
var stalls: Array[Dictionary] = []
var frames := 0
var elapsed_ms := 0.0
var peak_ms := 0.0
var slow_frames := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var active: bool = is_instance_valid(world) and world.session != null and world.session.ready_for_play and not get_tree().paused and not world.session.modal
	if active and was_active and previous_usec > 0:
		var ms := (now - previous_usec) / 1000.0
		frames += 1
		elapsed_ms += ms
		peak_ms = maxf(peak_ms, ms)
		if ms > 50:
			slow_frames += 1
			if stalls.size() >= 128: stalls.pop_front()
			stalls.append({"at_ms":now / 1000,"frame_ms":ms,"cpu_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"position":str(world.player.global_position),"region":world.session.state.region_id,"place":world.session.state.place_id,"driving":world.driving.occupied})
	elif was_active and not active:
		flush()
	previous_usec = now
	was_active = active

func flush() -> void:
	if frames == 0 or "--no-save" in OS.get_cmdline_user_args(): return
	var file := FileAccess.open("user://frame-stalls.json", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"version":ProjectSettings.get_setting("application/config/version"),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"viewport":str(get_viewport().size),"render_scale":get_viewport().scaling_3d_scale,"msaa":get_viewport().msaa_3d,"max_fps":Engine.max_fps,"frames":frames,"elapsed_ms":elapsed_ms,"peak_ms":peak_ms,"over_50_ms":slow_frames,"last_stalls":stalls},"\t"))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		flush()
		was_active = false
		previous_usec = 0
