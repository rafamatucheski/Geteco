extends Control
## Prerendered native 3D film. Portuguese performance is embedded in the movie;
## subtitles follow its media clock, ambience/music retain the user's separate buses.
signal finished(destination_beat: StringName)
signal skipped(destination_beat: StringName)
const DESTINATION := &"passenger_terminal_arrival"
const BASE := "res://cutscenes/opening/ferry/"
var video: VideoStreamPlayer
var stems: Array[AudioStreamPlayer] = []
var subtitle: Label
var skip_button: Button
var skip_dialog: ConfirmationDialog
var black: ColorRect
var lines: Array = []
var duration := 73.0
var language := "pt"
var _paused := false
var _finishing := false
var _completed := false
var _started := false
var _start_generation := 0
var _sync_clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	language = "en" if TranslationServer.get_locale().begins_with("en") else "pt"
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	video = VideoStreamPlayer.new()
	video.name = "FerryMovie"
	video.expand = true
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	video.stream = load(BASE+"arrival.ogv") as VideoStream
	video.finished.connect(func(): _finish(false))
	add_child(video)
	var timing: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE+"timing.json"))
	if timing is Dictionary:
		lines = timing.get("lines",[])
		duration = float(timing.get("duration",73.0))
	for entry in [["ambience","Ambient"],["music","Music"]]:
		var player := AudioStreamPlayer.new()
		player.name = entry[0]
		player.stream = load(BASE+entry[0]+".ogg") as AudioStream
		player.bus = entry[1] if AudioServer.get_bus_index(entry[1]) >= 0 else "Master"
		add_child(player)
		stems.append(player)
	subtitle = Label.new()
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_constant_override("outline_size",5)
	subtitle.add_theme_color_override("font_outline_color",Color(0,0,0,.95))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subtitle)
	skip_button = Button.new()
	skip_button.text = tr("CGI_SKIP_BUTTON")
	skip_button.pressed.connect(request_skip)
	add_child(skip_button)
	skip_dialog = ConfirmationDialog.new()
	skip_dialog.title = tr("CGI_SKIP_TITLE")
	skip_dialog.dialog_text = tr("CGI_SKIP_BODY")
	skip_dialog.ok_button_text = tr("CGI_SKIP_OK")
	skip_dialog.cancel_button_text = tr("CGI_SKIP_CANCEL")
	skip_dialog.confirmed.connect(skip)
	skip_dialog.canceled.connect(resume_playback)
	add_child(skip_dialog)
	black = ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	resized.connect(_layout)
	_layout()
	_start_after_draw.call_deferred(_start_generation)

func _layout() -> void:
	if video == null: return
	var film_size := Vector2(size.x,size.x*9.0/16.0)
	if film_size.y > size.y: film_size = Vector2(size.y*16.0/9.0,size.y)
	video.size = film_size
	video.position = (size-film_size)*.5
	subtitle.position = Vector2(size.x*.08,video.position.y+film_size.y*.875)
	subtitle.size = Vector2(size.x*.84,film_size.y*.115)
	subtitle.add_theme_font_size_override("font_size",clampi(roundi(film_size.y*.033),16,36))
	skip_button.position = Vector2(20,36)
	skip_button.add_theme_font_size_override("font_size",18)

func _start_after_draw(generation: int) -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	if generation != _start_generation or _finishing: return
	if video.stream == null:
		push_error("Missing Harbor ferry opening movie")
		_finish(true)
		return
	video.play()
	video.paused = _paused
	for stem in stems:
		stem.play()
		stem.stream_paused = _paused
	_started = true
	black.color.a = 0.0

func _process(delta: float) -> void:
	if not _started or _paused or _finishing: return
	var time := video.stream_position
	# The final 0.6 s is a baked fade to black, with no dialogue. Finish from the
	# real media clock in that black tail: Theora's native EOF rewind can stall.
	if time >= duration-.15:
		video.paused = true
		_finish(false)
		return
	_show_caption(time)
	_sync_clock += delta
	if _sync_clock >= 1.0:
		_sync_clock = 0.0
		# Only repair a demonstrated drift (e.g. OS suspension); do not seek every frame.
		for stem in stems:
			var audio_time := stem.get_playback_position()+AudioServer.get_time_since_last_mix()
			if stem.playing and absf(audio_time-time) > .18: stem.seek(time)

func _show_caption(time: float) -> void:
	subtitle.text = ""
	for line in lines:
		if time >= float(line.start) and time < float(line.end)+.18:
			var speaker := "Dante" if line.speaker == "dante" else ("Passenger" if language == "en" else "Passageiro")
			if line.speaker == "caller": speaker = "Voice on the phone" if language == "en" else "Voz ao telefone"
			if line.get("memory",false): speaker += " · memory" if language == "en" else " · lembrança"
			subtitle.text = speaker+"\n"+str(line.en if language == "en" else line.text)
			break

func pause_playback() -> void:
	if _finishing: return
	_paused = true
	video.paused = true
	for stem in stems: stem.stream_paused = true

func resume_playback() -> void:
	if _finishing: return
	_paused = false
	video.paused = false
	for stem in stems: stem.stream_paused = false

func request_skip() -> void:
	if _finishing or skip_dialog.visible: return
	pause_playback()
	skip_dialog.popup_centered(Vector2i(420,150))
	skip_dialog.get_cancel_button().grab_focus()

func skip() -> void: _finish(true)

func _finish(was_skipped: bool) -> void:
	if _finishing: return
	_finishing = true
	_start_generation += 1
	skip_dialog.hide()
	skip_button.hide()
	subtitle.hide()
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	var fade_time := .25 if was_skipped else .35
	tween.tween_property(black,"color:a",1.0,fade_time)
	tween.tween_property(video,"volume_db",-60.0,fade_time)
	for stem in stems: tween.tween_property(stem,"volume_db",-60.0,fade_time)
	tween.chain().tween_callback(_complete.bind(was_skipped))

func _complete(was_skipped: bool) -> void:
	if _completed: return
	_completed = true
	video.stop()
	for stem in stems: stem.stop()
	if was_skipped: skipped.emit(DESTINATION)
	else: finished.emit(DESTINATION)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		request_skip()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	_start_generation += 1
	if video != null:
		video.stop()
		video.stream = null
	for stem in stems:
		stem.stop()
		stem.stream = null
