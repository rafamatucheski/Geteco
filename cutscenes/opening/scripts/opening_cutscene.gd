class_name OpeningCutscene
extends Control

signal finished(destination_beat: StringName)
signal skipped(destination_beat: StringName)
signal cue_requested(cue_id: StringName, payload: Dictionary)

const Timeline = preload("res://cutscenes/opening/scripts/opening_cutscene_timeline.gd")

@export var auto_start := true
@export var show_studio_intro := false
@export var allow_skip := true
@export var show_preview_hud := false
@export_range(0.5, 2.0, 0.05) var playback_speed := 1.0
@export_file("*.tscn") var next_scene_path := ""
@export var destination_beat: StringName = Timeline.DESTINATION_BEAT

@onready var _frame_a: TextureRect = %FrameA
@onready var _frame_b: TextureRect = %FrameB
@onready var _black: ColorRect = %TransitionBlack
@onready var _subtitle: Label = %Subtitle
@onready var _shot_label: Label = %ShotLabel
@onready var _help_label: Label = %HelpLabel
@onready var _progress: ProgressBar = %Progress
@onready var _end_card: Label = %EndCard
@onready var _procedural_audio: Node = %ProceduralAudio

var _shots: Array[Dictionary] = Timeline.SHOTS
var _shot_index := -1
var _shot_elapsed := 0.0
var _total_elapsed := 0.0
var _fired_cue_indices: Dictionary = {}
var _active_frame: TextureRect
var _transition_tween: Tween
var _running := false
var _paused := false
var _finishing := false
var _completion_emitted := false
var _studio_card: Control
var _studio_elapsed := 0.0
var _studio_audio: AudioStreamPlayer
var _skip_button: Button
var _skip_dialog: ConfirmationDialog
var _studio_waiting_for_draw := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_frame_a.hide()
	_frame_b.hide()
	_black.color = Color(0.0, 0.0, 0.0, 1.0)
	_subtitle.hide()
	_end_card.hide()
	_shot_label.visible = show_preview_hud
	_help_label.visible = show_preview_hud
	_progress.visible = show_preview_hud
	_progress.max_value = Timeline.TOTAL_DURATION_SECONDS
	_validate_timeline()
	_skip_button = Button.new()
	_skip_button.text = tr("CGI_SKIP_BUTTON")
	_skip_button.position = Vector2(24, 24)
	_skip_button.pressed.connect(request_skip)
	add_child(_skip_button)
	_skip_dialog = ConfirmationDialog.new()
	_skip_dialog.title = tr("CGI_SKIP_TITLE")
	_skip_dialog.dialog_text = tr("CGI_SKIP_BODY")
	_skip_dialog.ok_button_text = tr("CGI_SKIP_OK")
	_skip_dialog.cancel_button_text = tr("CGI_SKIP_CANCEL")
	_skip_dialog.confirmed.connect(skip)
	_skip_dialog.canceled.connect(resume_playback)
	add_child(_skip_dialog)
	cue_requested.connect(_procedural_audio.play_cue)
	if show_studio_intro:
		preload("res://world/harbor/HarborAudioBank.gd").sound("water")
		preload("res://world/harbor/HarborAudioBank.gd").sound("logo")
	if auto_start:
		play()


func play() -> void:
	if _running and not _paused:
		return
	if _shot_index < 0 or _finishing:
		restart()
	else:
		_paused = false
		_running = true
		_update_help_text()


func restart() -> void:
	_kill_transition()
	_procedural_audio.reset()
	_shot_index = -1
	_shot_elapsed = 0.0
	_total_elapsed = 0.0
	_fired_cue_indices.clear()
	_active_frame = null
	_running = true
	_paused = false
	_finishing = false
	_completion_emitted = false
	_frame_a.hide()
	_frame_b.hide()
	_set_alpha(_frame_a, 1.0)
	_set_alpha(_frame_b, 1.0)
	_black.color = Color(0.0, 0.0, 0.0, 1.0)
	_subtitle.hide()
	_end_card.hide()
	_progress.value = 0.0
	if is_instance_valid(_studio_card):
		_studio_card.queue_free()
	if is_instance_valid(_studio_audio):
		_studio_audio.queue_free()
	_studio_elapsed = 0.0
	if show_studio_intro:
		preload("res://world/harbor/HarborAudioBank.gd").sound("water")
		_studio_card = preload("res://cutscenes/opening/scripts/rcm_studio_card.gd").new()
		add_child(_studio_card)
		_studio_audio = AudioStreamPlayer.new()
		_studio_audio.bus = "SFX"
		_studio_audio.volume_db = -12.0
		_studio_audio.stream = preload("res://world/harbor/HarborAudioBank.gd").sound("logo")
		add_child(_studio_audio)
		_studio_waiting_for_draw = true
		_start_studio_after_draw.call_deferred(_studio_audio)
	else:
		_begin_shot(0)
	move_child(_skip_button, get_child_count() - 1)
	_skip_button.visible = allow_skip
	_update_help_text()


func _start_studio_after_draw(player: AudioStreamPlayer) -> void:
	# O mixer não deve se antecipar ao primeiro quadro visível da identidade.
	_studio_card.elapsed = 0.04
	_studio_card.queue_redraw()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	if not is_instance_valid(player) or player != _studio_audio or _finishing: return
	_studio_waiting_for_draw = false
	player.play()
	player.stream_paused = _paused

func pause_playback() -> void:
	if not _running or _finishing:
		return
	_paused = true
	_procedural_audio.set_paused(true)
	if is_instance_valid(_studio_audio):
		_studio_audio.stream_paused = true
	_update_help_text()


func resume_playback() -> void:
	if not _running or _finishing:
		return
	_paused = false
	_procedural_audio.set_paused(false)
	if is_instance_valid(_studio_audio):
		_studio_audio.stream_paused = false
	_update_help_text()


func skip() -> void:
	if not allow_skip or _finishing:
		return
	_finish(true, 0.2)

func request_skip() -> void:
	if not allow_skip or _finishing or _skip_dialog.visible:
		return
	pause_playback()
	_skip_dialog.popup_centered(Vector2i(420, 150))
	_skip_dialog.get_cancel_button().grab_focus()


func jump_to_shot(index: int) -> void:
	if _shots.is_empty():
		return
	var clamped_index := clampi(index, 0, _shots.size() - 1)
	_kill_transition()
	_procedural_audio.reset()
	_finishing = false
	_running = true
	_paused = false
	_total_elapsed = 0.0
	for shot_index in range(clamped_index):
		_total_elapsed += float(_shots[shot_index]["duration"])
	_begin_shot(clamped_index, true)


func _process(delta: float) -> void:
	if _studio_waiting_for_draw: return
	if _running and not _paused and not _finishing and is_instance_valid(_studio_card):
		_studio_elapsed += delta * playback_speed
		_studio_card.elapsed = _studio_elapsed
		_studio_card.queue_redraw()
		if _studio_elapsed >= 3.7 and _studio_audio.stream != preload("res://world/harbor/HarborAudioBank.gd").sound("water"):
			_studio_audio.stream = preload("res://world/harbor/HarborAudioBank.gd").sound("water")
			_studio_audio.volume_db = -22.0
			_studio_audio.play()
		if _studio_elapsed >= 6.5:
			_studio_card.queue_free()
			_studio_card = null
			var audio_fade := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			audio_fade.tween_property(_studio_audio, "volume_db", -60.0, 0.8)
			audio_fade.tween_callback(_studio_audio.stop)
			_begin_shot(0)
		return
	if not _running or _paused or _finishing or _shot_index < 0:
		return
	var scaled_delta := delta * playback_speed
	_shot_elapsed += scaled_delta
	_total_elapsed += scaled_delta
	var shot := _shots[_shot_index]
	_update_frame_motion(shot)
	_update_caption(shot)
	_emit_due_cues(shot)
	_progress.value = minf(_total_elapsed, Timeline.TOTAL_DURATION_SECONDS)
	if _shot_elapsed >= float(shot["duration"]):
		if _shot_index + 1 < _shots.size():
			_begin_shot(_shot_index + 1)
		else:
			_finish(false, 0.8)


func _unhandled_input(event: InputEvent) -> void:
	if not show_preview_hud:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			request_skip()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		skip()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_paused = not _paused
		_procedural_audio.set_paused(_paused)
		_update_help_text()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		jump_to_shot(_shot_index - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		jump_to_shot(_shot_index + 1)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			restart()
			get_viewport().set_input_as_handled()


func _begin_shot(index: int, force_cut := false) -> void:
	_shot_index = index
	_shot_elapsed = 0.0
	_fired_cue_indices.clear()
	_subtitle.hide()
	var shot := _shots[index]
	_procedural_audio.enter_shot(StringName(shot.id))
	var incoming := _frame_b if _active_frame == _frame_a else _frame_a
	var outgoing := _active_frame
	var texture_path := String(shot["texture"])
	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_error("OpeningCutscene: não foi possível carregar " + texture_path)
		return
	incoming.texture = texture
	incoming.show()
	_prepare_frame(incoming, shot)
	var transition: StringName = &"cut" if force_cut else StringName(shot.get("enter", &"cut"))
	var transition_duration := float(shot.get("transition_duration", 0.0)) / playback_speed
	_kill_transition()
	if outgoing == null:
		_active_frame = incoming
		_set_alpha(incoming, 0.0)
		_black.color = Color(0.0, 0.0, 0.0, 1.0)
		_transition_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_transition_tween.set_parallel(true)
		_transition_tween.tween_property(incoming, "modulate:a", 1.0, transition_duration)
		_transition_tween.tween_property(_black, "color:a", 0.0, transition_duration)
	elif transition == &"crossfade" or transition == &"fade":
		_active_frame = incoming
		_set_alpha(incoming, 0.0)
		_set_alpha(outgoing, 1.0)
		_transition_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_transition_tween.set_parallel(true)
		_transition_tween.tween_property(incoming, "modulate:a", 1.0, transition_duration)
		_transition_tween.tween_property(outgoing, "modulate:a", 0.0, transition_duration)
		_transition_tween.chain().tween_callback(outgoing.hide)
	else:
		if outgoing != null:
			outgoing.hide()
		_set_alpha(incoming, 1.0)
		_active_frame = incoming
	_shot_label.text = "QUADRO %02d / %02d  ·  %s" % [index + 1, _shots.size(), String(shot["id"]).to_upper()]
	_emit_due_cues(shot)


func _prepare_frame(frame: TextureRect, shot: Dictionary) -> void:
	frame.pivot_offset = size * 0.5
	frame.scale = Vector2.ONE * float(shot.get("zoom_from", 1.0))
	frame.position = Vector2(shot.get("pan_from", Vector2.ZERO))


func _update_frame_motion(shot: Dictionary) -> void:
	if _active_frame == null:
		return
	_active_frame.pivot_offset = size * 0.5
	var duration := maxf(float(shot["duration"]), 0.001)
	var weight := clampf(_shot_elapsed / duration, 0.0, 1.0)
	weight = ease(weight, -1.6)
	var zoom := lerpf(float(shot.get("zoom_from", 1.0)), float(shot.get("zoom_to", 1.0)), weight)
	var pan_from := Vector2(shot.get("pan_from", Vector2.ZERO))
	var pan_to := Vector2(shot.get("pan_to", Vector2.ZERO))
	_active_frame.scale = Vector2.ONE * zoom
	_active_frame.position = pan_from.lerp(pan_to, weight)
	if StringName(shot["id"]) == &"bus_highway" or StringName(shot["id"]) == &"dante_bus_interior":
		_active_frame.position.y += sin(_shot_elapsed * 7.0) * 1.2


func _update_caption(shot: Dictionary) -> void:
	var visible_caption := ""
	for caption_variant in shot.get("captions", []):
		var caption := Dictionary(caption_variant)
		if _shot_elapsed >= float(caption["from"]) and _shot_elapsed < float(caption["to"]):
			# The timeline stores a translation key per caption/speaker (not the
			# literal text); DANTE/HARBOR fall through tr() unchanged, matching
			# how proper names stay untranslated elsewhere in the campaign.
			var speaker := tr(String(caption.get("speaker", "")))
			visible_caption = tr(String(caption["text"]))
			if not speaker.is_empty():
				visible_caption = speaker + "\n" + visible_caption
			break
	_subtitle.text = visible_caption
	_subtitle.visible = not visible_caption.is_empty()


func _emit_due_cues(shot: Dictionary) -> void:
	var cues: Array = shot.get("cues", [])
	for cue_index in range(cues.size()):
		if _fired_cue_indices.has(cue_index):
			continue
		var cue := Dictionary(cues[cue_index])
		if _shot_elapsed >= float(cue.get("at", 0.0)):
			_fired_cue_indices[cue_index] = true
			cue_requested.emit(StringName(cue["id"]), cue)


func _finish(was_skipped: bool, fade_duration: float) -> void:
	if _finishing:
		return
	_finishing = true
	_skip_dialog.hide()
	_skip_button.hide()
	_running = false
	_subtitle.hide()
	if is_instance_valid(_studio_card):
		move_child(_black, get_child_count() - 1)
		_black.color.a = 0.0
	_kill_transition()
	_transition_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition_tween.tween_property(_black, "color:a", 1.0, fade_duration)
	if is_instance_valid(_studio_audio):
		_transition_tween.parallel().tween_property(_studio_audio, "volume_db", -60.0, fade_duration)
	_transition_tween.tween_callback(_complete_finish.bind(was_skipped))


func _complete_finish(was_skipped: bool) -> void:
	if _completion_emitted:
		return
	_completion_emitted = true
	if is_instance_valid(_studio_audio):
		_studio_audio.stop()
	_procedural_audio.stop_all()
	if was_skipped:
		skipped.emit(destination_beat)
	else:
		finished.emit(destination_beat)
	if not next_scene_path.is_empty():
		var error := get_tree().change_scene_to_file(next_scene_path)
		if error != OK:
			push_error("OpeningCutscene: falha ao abrir cena seguinte: %s" % error_string(error))
		return
	_end_card.text = "CUTSCENE CONCLUÍDA\nDestino narrativo: %s\n\nR — REINICIAR" % String(destination_beat)
	_end_card.visible = show_preview_hud


func _set_alpha(node: CanvasItem, alpha: float) -> void:
	node.modulate = Color(1.0, 1.0, 1.0, alpha)


func _kill_transition() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = null


func _update_help_text() -> void:
	var state := "PAUSADO" if _paused else "REPRODUZINDO"
	_help_label.text = "%s  ·  ESPAÇO pausa  ·  ←/→ quadro  ·  R reinicia  ·  ESC pula" % state


func _validate_timeline() -> void:
	var duration_sum := 0.0
	for shot in _shots:
		duration_sum += float(shot.get("duration", 0.0))
		var texture_path := String(shot.get("texture", ""))
		if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
			push_error("OpeningCutscene: frame ausente no timeline: " + texture_path)
	if not is_equal_approx(duration_sum, Timeline.TOTAL_DURATION_SECONDS):
		push_error("OpeningCutscene: duração do timeline diverge do manifesto: %.2f" % duration_sum)
