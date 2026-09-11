extends Control
signal finished(destination_beat: StringName)
signal skipped(destination_beat: StringName)
signal cue_requested(cue_id: StringName, payload: Dictionary)
const Timeline=preload("res://cutscenes/opening/v3/opening_timeline.gd")
const Stage=preload("res://cutscenes/opening/v3/opening_stage.gd")
@export var auto_start:=true
@export var show_studio_intro:=false
@export var allow_skip:=true
@export var show_preview_hud:=false
@export_range(.5,2,.05) var playback_speed:=1.0
@export_file("*.tscn") var next_scene_path:=""
@export var destination_beat: StringName=Timeline.DESTINATION_BEAT
@onready var _black: ColorRect=%TransitionBlack
@onready var _subtitle: Label=%Subtitle
@onready var _shot_label: Label=%ShotLabel
@onready var _help_label: Label=%HelpLabel
@onready var _progress: ProgressBar=%Progress
@onready var _end_card: Label=%EndCard
@onready var _procedural_audio: Node=%ProceduralAudio
var _shots:=Timeline.SHOTS
var _shot_index:=-1
var _shot_elapsed:=0.0
var _total_elapsed:=0.0
var _running:=false
var _paused:=false
var _finishing:=false
var _completion_emitted:=false
var _studio_elapsed:=0.0
var _studio_waiting_for_draw:=false
var _studio_card: Control
var _studio_audio: AudioStreamPlayer
var _skip_button: Button
var _skip_dialog: ConfirmationDialog
var _view: SubViewport
var stage: Node3D
var _timing: Dictionary
var _captions: Array=[]
var _fired: Dictionary={}
var _finish_time:=0.0
var _skip_finish:=false
var _starting:=false
var _end_fade_duration:=.4
var _generation:=0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	%FrameA.hide(); %FrameB.hide()
	var surface:=SubViewportContainer.new(); surface.name="CinematicSurface"
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.stretch=true; surface.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(surface); move_child(surface,2)
	_view=SubViewport.new(); _view.name="CinematicWorld"; _view.own_world_3d=true
	_view.size=Vector2i(1280,720); _view.msaa_3d=Viewport.MSAA_2X
	_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	surface.add_child(_view); stage=Stage.new(); _view.add_child(stage)
	var grade:=ColorRect.new(); grade.name="FilmGrade"
	grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); grade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var shader:=Shader.new()
	shader.code="""shader_type canvas_item;
uniform sampler2D screen_texture: hint_screen_texture, filter_linear;
void fragment(){
 vec3 c=texture(screen_texture,SCREEN_UV).rgb;
 vec2 q=SCREEN_UV-.5;
 float vignette=1.0-smoothstep(.18,.75,length(q))*0.24;
 c=mix(vec3(dot(c,vec3(.2126,.7152,.0722))),c,0.91);
 COLOR=vec4(c*vignette,1.0);
}"""
	var grade_material:=ShaderMaterial.new(); grade_material.shader=shader; grade.material=grade_material
	add_child(grade); move_child(grade,3)
	# Faixas discretas preservam o enquadramento e a leitura de legenda.
	$VignetteTop.color=Color.BLACK; $VignetteBottom.color=Color.BLACK
	$VignetteTop.offset_bottom=36; $VignetteBottom.offset_top=-64
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_subtitle.offset_left=60; _subtitle.offset_right=-60
	_subtitle.offset_top=-106; _subtitle.offset_bottom=-32
	_subtitle.add_theme_font_size_override("font_size",24)
	_subtitle.add_theme_constant_override("outline_size",5)
	_subtitle.hide(); _end_card.hide()
	_shot_label.visible=show_preview_hud; _help_label.visible=show_preview_hud; _progress.visible=show_preview_hud
	_progress.max_value=Timeline.TOTAL_DURATION_SECONDS
	_timing=preload("res://cutscenes/opening/v3/voice_timing.gd").LINES
	_skip_button=Button.new(); _skip_button.text=tr("CGI_SKIP_BUTTON")
	_skip_button.position=Vector2(20,9); _skip_button.add_theme_font_size_override("font_size",14)
	_skip_button.pressed.connect(request_skip); add_child(_skip_button)
	_skip_dialog=ConfirmationDialog.new(); _skip_dialog.title=tr("CGI_SKIP_TITLE")
	_skip_dialog.dialog_text=tr("CGI_SKIP_BODY"); _skip_dialog.ok_button_text=tr("CGI_SKIP_OK")
	_skip_dialog.cancel_button_text=tr("CGI_SKIP_CANCEL")
	_skip_dialog.confirmed.connect(skip); _skip_dialog.canceled.connect(resume_playback); add_child(_skip_dialog)
	_black.color=Color.BLACK
	if auto_start: play()

func play() -> void:
	if _paused: resume_playback(); return
	if _running or _starting: return
	restart()

func restart() -> void:
	_generation+=1
	_procedural_audio.stop_all(); _fired.clear()
	_running=false; _starting=true; _paused=false; _finishing=false; _completion_emitted=false
	_total_elapsed=0; _shot_elapsed=0; _shot_index=-1; _studio_elapsed=0
	_subtitle.hide(); _end_card.hide(); _black.color.a=1
	_skip_button.visible=allow_skip
	if is_instance_valid(_studio_card): _studio_card.queue_free(); _studio_card=null
	if is_instance_valid(_studio_audio): _studio_audio.queue_free(); _studio_audio=null
	var lang:="en" if TranslationServer.get_locale().begins_with("en") else "pt"
	_captions=_timing[lang]; stage.lang=lang
	_procedural_audio.configure(lang,playback_speed)
	stage.set_time(0)
	if show_studio_intro:
		_studio_card=preload("res://cutscenes/opening/scripts/rcm_studio_card.gd").new()
		add_child(_studio_card); _studio_card.elapsed=.04
		_studio_audio=AudioStreamPlayer.new(); _studio_audio.bus="SFX"
		_studio_audio.volume_db=-15; _studio_audio.stream=preload("res://world/harbor/HarborAudioBank.gd").sound("logo")
		add_child(_studio_audio)
	_studio_waiting_for_draw=true
	_start_after_draw.call_deferred(_generation)

func _start_after_draw(generation: int) -> void:
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
	if generation!=_generation or _finishing: return
	_studio_waiting_for_draw=false; _starting=false; _running=true
	if is_instance_valid(_studio_audio):
		_studio_audio.play(); _studio_audio.stream_paused=_paused
	else:
		_procedural_audio.play_from(0); _procedural_audio.set_paused(_paused)
		_shot_index=0

func _process(delta: float) -> void:
	if _finishing and not _completion_emitted:
		_finish_time+=delta
		var w:=clampf(_finish_time/_end_fade_duration,0,1)
		_black.color.a=w; _procedural_audio.set_gain(lerpf(0,-55,w))
		if is_instance_valid(_studio_audio): _studio_audio.volume_db=lerpf(-15,-55,w)
		if w>=1: _complete_finish()
		return
	if not _running or _paused or _studio_waiting_for_draw: return
	if is_instance_valid(_studio_card):
		_studio_elapsed+=delta*playback_speed
		# A identidade RCM ocupa 2,8s; a cartela antiga de Harbor sai do prólogo.
		_studio_card.elapsed=_studio_elapsed*3.7/2.8
		_studio_card.queue_redraw()
		if _studio_elapsed>=2.8:
			_studio_card.queue_free(); _studio_card=null; _studio_audio.stop()
			_procedural_audio.play_from(0); _shot_index=0
		return
	_total_elapsed=minf(68,_total_elapsed+delta*playback_speed)
	_show_time(_total_elapsed)
	if _total_elapsed>=68: _finish(false,.18)

func _show_time(time: float) -> void:
	_shot_index=Timeline.shot_at(time)
	_shot_elapsed=time-float(_shots[_shot_index].start)
	_black.color.a=1-smoothstep(0,.7,time)
	# Uma breve elipse na luz; os demais cortes pertencem a uma mesma ação.
	if time>41.85 and time<42.15: _black.color.a=1-absf(time-42)/.15
	var mouth:=0.0
	_subtitle.hide()
	for caption in _captions:
		if time>=float(caption.start)-.08 and time<float(caption.end)+.28:
			_subtitle.text=String(caption.text); _subtitle.show()
			if caption.id=="dante" and time<float(caption.end):
				mouth=(.5+.5*sin((time-float(caption.start))*23))*sin(clampf((time-float(caption.start))/.12,0,1)*PI/2)
	stage.set_time(time,mouth)
	_progress.value=time
	_shot_label.text="%02d · %s" % [_shot_index+1,_shots[_shot_index].id]
	for cue in Timeline.CUES:
		if time>=float(cue[0]) and not _fired.has(cue[1]):
			_fired[cue[1]]=true; cue_requested.emit(cue[1],{"at":cue[0]})

func jump_to_shot(index: int) -> void:
	seek(float(_shots[clampi(index,0,_shots.size()-1)].start))

func seek(time: float) -> void:
	_generation+=1; _starting=false; _studio_waiting_for_draw=false
	if is_instance_valid(_studio_card): _studio_card.queue_free(); _studio_card=null
	if is_instance_valid(_studio_audio): _studio_audio.stop()
	_total_elapsed=clampf(time,0,67.999); _fired.clear()
	for cue in Timeline.CUES:
		if float(cue[0])<_total_elapsed: _fired[cue[1]]=true
	_finishing=false; _completion_emitted=false; _running=true; _paused=false
	_end_card.hide(); _skip_button.visible=allow_skip
	_procedural_audio.configure(TranslationServer.get_locale(),playback_speed)
	var lang:="en" if TranslationServer.get_locale().begins_with("en") else "pt"
	_captions=_timing[lang]; stage.lang=lang
	_procedural_audio.play_from(_total_elapsed); _show_time(_total_elapsed)

func pause_playback() -> void:
	if _finishing: return
	_paused=true; _procedural_audio.set_paused(true)
	if is_instance_valid(_studio_audio): _studio_audio.stream_paused=true

func resume_playback() -> void:
	if _finishing: return
	_paused=false; _procedural_audio.set_paused(false)
	if is_instance_valid(_studio_audio): _studio_audio.stream_paused=false

func request_skip() -> void:
	if not allow_skip or _finishing or _skip_dialog.visible: return
	pause_playback(); _skip_dialog.popup_centered(Vector2i(420,150)); _skip_dialog.get_cancel_button().grab_focus()

func skip() -> void:
	if allow_skip and not _finishing: _finish(true,.25)

func _finish(was_skipped: bool, duration: float) -> void:
	if _finishing: return
	_generation+=1; _finishing=true; _running=false; _starting=false
	_skip_finish=was_skipped; _finish_time=0; _end_fade_duration=duration
	_subtitle.hide(); _skip_button.hide(); _skip_dialog.hide()
	if is_instance_valid(_studio_card): move_child(_black,get_child_count()-1)
	_procedural_audio.set_paused(false)

func _complete_finish() -> void:
	if _completion_emitted: return
	_completion_emitted=true; _procedural_audio.stop_all()
	if is_instance_valid(_studio_audio): _studio_audio.stop()
	if _skip_finish: skipped.emit(destination_beat)
	else: finished.emit(destination_beat)
	if not next_scene_path.is_empty(): get_tree().change_scene_to_file(next_scene_path)
	_end_card.visible=show_preview_hud

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE: request_skip(); get_viewport().set_input_as_handled()
		elif show_preview_hud:
			match event.keycode:
				KEY_SPACE:
					if _paused: resume_playback()
					else: pause_playback()
				KEY_RIGHT: jump_to_shot(_shot_index+1)
				KEY_LEFT: jump_to_shot(_shot_index-1)
				KEY_R: restart()
