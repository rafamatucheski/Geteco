extends Control
## Authored opening using the established home artwork. New words only play when
## an exact matching recording exists; their PT/EN captions remain authoritative.
signal finished(destination_beat: StringName)
signal skipped(destination_beat: StringName)
const DESTINATION := &"passenger_terminal_arrival"
const DIALOGUE := preload("res://runtime/ArrivalDialogue.gd")
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const DURATION := 34.0
const LINE_TIMES := [[8.0,10.0],[10.0,13.2],[13.2,17.0],[17.0,24.0],[24.0,26.0]]
const SHOTS := [
	[0.0,"res://cutscenes/opening/frames/frame_v2_morning_coffee.png"],
	[4.0,"res://cutscenes/opening/frames/frame_v2_phone.png"],
	[8.0,"res://cutscenes/opening/frames/frame_v2_call.png"],
	[13.2,"res://cutscenes/opening/frames/frame_expanded_call_close.png"],
	[24.0,"res://cutscenes/opening/frames/frame_phone_reply.png"],
	[27.0,"res://cutscenes/opening/frames/frame_06_backpack_departure.png"],
	[31.0,"res://cutscenes/opening/frames/frame_expanded_empty_kitchen.png"],
]
var elapsed := 0.0
var line_times: Array = LINE_TIMES.duplicate(true)
var duration := DURATION
var subtitle: Label
var skip_dialog: ConfirmationDialog
var voice: AudioStreamPlayer
var ring: AudioStreamPlayer
var music: AudioStreamPlayer
var image: TextureRect
var black: ColorRect
var skip_button: Button
var language := "pt"
var _paused := false
var _finishing := false
var _completed := false
var _shot := -1
var _line := -1
var _rang := false
var _textures: Array[Texture2D] = []
var _shots: Array = SHOTS.duplicate(true)
var _recorded_lines: Array[AudioStream] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	language = "en" if TranslationServer.get_locale().begins_with("en") else "pt"
	_configure_recorded_timing()
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	image = TextureRect.new()
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	for shot in SHOTS: _textures.append(load(str(shot[1])) as Texture2D)
	voice = _audio("HomeCallVoice", "SFX", -8)
	ring = _audio("HomePhoneRing", "SFX", -14)
	music = _audio("HomeCallMusic", "Music", -23)
	music.stream = preload("res://cutscenes/opening/ferry/music.ogg")
	music.play()
	subtitle = Label.new()
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle.offset_left = 50
	subtitle.offset_right = -50
	subtitle.offset_top = -112
	subtitle.offset_bottom = -28
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size",24)
	subtitle.add_theme_constant_override("outline_size",5)
	subtitle.add_theme_color_override("font_outline_color",Color.BLACK)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subtitle)
	skip_button = Button.new()
	skip_button.text = tr("CGI_SKIP_BUTTON")
	skip_button.position = Vector2(20,36)
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
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	_apply_shot(0.0)
	create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(black,"color:a",0.0,.4)

func _audio(label: String, bus_name: String, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = label
	player.bus = bus_name if AudioServer.get_bus_index(bus_name) >= 0 else "Master"
	player.volume_db = volume
	add_child(player)
	return player

func _process(delta: float) -> void:
	if _paused or _finishing: return
	elapsed += delta
	_apply_shot(elapsed)
	_show_caption(elapsed)
	if elapsed >= 5.0 and not _rang:
		_rang = true
		ring.stream = DIALOGUE.phone_ring()
		ring.play()
	for index in line_times.size():
		if elapsed >= float(line_times[index][0]) and elapsed < float(line_times[index][1]) and index != _line:
			_line = index
			voice.stop()
			voice.stream = _recorded_lines[index]
			if voice.stream != null: voice.play()
	if elapsed >= duration: _finish(false)

func _configure_recorded_timing() -> void:
	var shift := 0.0
	for index in DIALOGUE.HOME_CALL.size():
		var line: Array = DIALOGUE.HOME_CALL[index]
		var spoken: String = line[2] if language == "en" else line[1]
		var stream := VOICE.recorded_line(spoken,"dante" if line[0] == "DANTE" else "caller")
		_recorded_lines.append(stream)
		var start: float = float(LINE_TIMES[index][0])+shift
		var span: float = float(LINE_TIMES[index][1])-float(LINE_TIMES[index][0])
		# English and missing takes keep the authored default. Available PT takes
		# may only extend it; a voice is never sped up or truncated to fit a shot.
		var voiced_span := maxf(span,stream.get_length()+.35) if language == "pt" and stream != null else span
		line_times[index] = [start,start+voiced_span]
		shift += voiced_span-span
	duration = DURATION+shift
	_shots[3][0] = line_times[2][0]
	_shots[4][0] = line_times[4][0]
	_shots[5][0] = 27.0+shift
	_shots[6][0] = 31.0+shift

func _apply_shot(time: float) -> void:
	var chosen := 0
	for index in _shots.size():
		if time >= float(_shots[index][0]): chosen = index
	if chosen == _shot: return
	_shot = chosen
	image.texture = _textures[chosen]

func _show_caption(time: float) -> void:
	subtitle.text = ""
	for index in line_times.size():
		if time >= float(line_times[index][0]) and time < float(line_times[index][1]):
			var line: Array = DIALOGUE.HOME_CALL[index]
			var speaker := str(line[0])
			if speaker == "VOZ AO TELEFONE" and language == "en": speaker = "VOICE ON THE PHONE"
			subtitle.text = speaker+"\n"+str(line[2] if language == "en" else line[1])
			return

func pause_playback() -> void:
	if _finishing: return
	_paused = true
	for player in [voice,ring,music]: player.stream_paused = true

func resume_playback() -> void:
	if _finishing: return
	_paused = false
	for player in [voice,ring,music]: player.stream_paused = false

func request_skip() -> void:
	if _finishing or skip_dialog.visible: return
	pause_playback()
	skip_dialog.popup_centered(Vector2i(420,150))
	skip_dialog.get_cancel_button().grab_focus()

func skip() -> void: _finish(true)

func _finish(was_skipped: bool) -> void:
	if _finishing: return
	_finishing = true
	skip_dialog.hide()
	skip_button.hide()
	subtitle.hide()
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	tween.tween_property(black,"color:a",1.0,.25)
	for player in [voice,ring,music]: tween.tween_property(player,"volume_db",-60.0,.25)
	tween.chain().tween_callback(_complete.bind(was_skipped))

func _complete(was_skipped: bool) -> void:
	if _completed: return
	_completed = true
	for player in [voice,ring,music]: player.stop()
	if was_skipped: skipped.emit(DESTINATION)
	else: finished.emit(DESTINATION)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		request_skip()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	for player in [voice,ring,music]:
		if is_instance_valid(player): player.stop(); player.stream = null
