extends SceneTree
## Same production movie and render setup; baseline reconstructs only this
## change's preimage in memory, leaving the live FerryFilm.gd untouched.
var samples: Array[float] = []
var previous_us := 0
var started_us := 0
var film: Control
var baseline := false
var captured := false

func _initialize() -> void: run.call_deferred()

func run() -> void:
	baseline = "--baseline" in OS.get_cmdline_user_args()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.disable_3d = true
	root.get_node("V2Settings").voice_language = "en"
	TranslationServer.set_locale("en")
	var source := FileAccess.get_file_as_string("res://cutscenes/opening/ferry/FerryFilm.gd").replace("\r\n", "\n")
	if baseline:
		source = source.replace('var voice_language := "pt_BR"\n', '')
		source = source.replace('\tvoice_language = preload("res://audio/ExpressiveVoice.gd").selected_language()\n', '')
		source = source.replace('\tif voice_language == "en": video.volume_db = -80.0\n', '')
		var start := source.find('\tif voice_language == "en":\n')
		var end := source.find('\tsubtitle = Label.new()', start)
		assert(start >= 0 and end > start)
		source = source.left(start) + source.substr(end)
		source = source.replace('\t\tvar spoken_end := float(line.get("end_en", line.end)) if voice_language == "en" else float(line.end)\n', '')
		source = source.replace('time < spoken_end+.18', 'time < float(line.end)+.18')
	var script := GDScript.new()
	script.source_code = source
	assert(script.reload() == OK)
	film = script.new()
	root.add_child(film)
	film.finished.connect(finish)
	started_us = Time.get_ticks_usec()
	previous_us = started_us
	process_frame.connect(record_frame)

func record_frame() -> void:
	var now := Time.get_ticks_usec()
	var elapsed := float(now-started_us)/1000000.0
	if elapsed >= 2.0: samples.append(float(now-previous_us)/1000.0)
	previous_us = now
	if elapsed >= 18.0 and not captured:
		captured = true
		root.get_texture().get_image().save_png("res://evidence/ferry-dub-%s.png" % ("baseline" if baseline else "english"))
	if elapsed >= 72.0: finish()

func percentile(values: Array[float], fraction: float) -> float:
	return values[mini(values.size()-1, int(floor(fraction*values.size())))]

func finish(_destination: StringName = &"") -> void:
	if samples.is_empty(): return
	process_frame.disconnect(record_frame)
	var elapsed := 0.0
	var over33 := 0
	var over66 := 0
	for value in samples:
		elapsed += value
		if value > 33.3: over33 += 1
		if value > 66.7: over66 += 1
	samples.sort()
	var report := {"baseline":baseline,"samples":samples.size(),"seconds":elapsed/1000.0,
		"fps":samples.size()*1000.0/elapsed,"p50_ms":percentile(samples,.5),"p95_ms":percentile(samples,.95),
		"p99_ms":percentile(samples,.99),"max_ms":samples[-1],"over33":over33,"over66":over66,
		"resolution":"1280x720","vsync":false,"max_fps":0,"scene":"production ferry film, hidden 3D disabled", "frame_times_ms":samples}
	var file := FileAccess.open("res://evidence/ferry-dub-%s.json" % ("baseline" if baseline else "english"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	report.erase("frame_times_ms")
	print("FERRY_DUB_PERFORMANCE ", JSON.stringify(report))
	film.free()
	quit()
