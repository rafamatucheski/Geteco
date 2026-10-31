extends Node
## Uma voz do local, sem síntese nem consulta por quadro. A sessão
## chama sync a partir da atualização de local que já existe; os fades podem reverter ao reentrar.
const TRACK := "res://audio/workshop/digo_blues_loop.ogg"
const LEVEL_DB := -18.0
const SILENCE_DB := -70.0
const IN_SECONDS := .8
const OUT_SECONDS := 1.0
var _voice: AudioStreamPlayer
var _fade: Tween
var _audio_owner: WeakRef
var _active := false
var _claimed := false

func sync(should_play: bool, world_audio: Node) -> void:
	var previous: Object = _audio_owner.get_ref() if _audio_owner != null else null
	if previous != world_audio:
		shutdown()
		_audio_owner = weakref(world_audio) if is_instance_valid(world_audio) else null
	if should_play == _active: return
	if should_play:
		if not is_instance_valid(world_audio) or not world_audio.has_method("set_scoped_music_override"): return
		if not _ensure_voice(): return
		if not world_audio.set_scoped_music_override(self): return
		_claimed = true
		_active = true
		if not _voice.playing:
			_voice.volume_db = SILENCE_DB
			_voice.play()
		_fade_to(LEVEL_DB,IN_SECONDS)
	else:
		_active = false
		if is_instance_valid(_voice) and _voice.playing:
			_fade_to(SILENCE_DB,OUT_SECONDS)
			_fade.tween_callback(_finish_stop)
		else: _release_override()

func _ensure_voice() -> bool:
	if is_instance_valid(_voice): return true
	if not ResourceLoader.exists(TRACK): return false
	var source := load(TRACK) as AudioStreamOggVorbis
	if source == null: return false
	var stream := source.duplicate() as AudioStreamOggVorbis
	stream.loop = true
	stream.loop_offset = 0.0
	_voice = AudioStreamPlayer.new()
	_voice.name = "DigoWorkshopMusicVoice"
	_voice.stream = stream
	_voice.bus = &"Music" if AudioServer.get_bus_index(&"Music")>=0 else &"Master"
	_voice.process_mode = Node.PROCESS_MODE_ALWAYS
	_voice.volume_db = SILENCE_DB
	_voice.max_polyphony = 1
	add_child(_voice)
	return true

func _fade_to(level: float, seconds: float) -> void:
	if _fade != null and _fade.is_valid(): _fade.kill()
	_fade = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade.tween_property(_voice,"volume_db",level,seconds).set_trans(Tween.TRANS_SINE)

func _finish_stop() -> void:
	if _active: return
	if is_instance_valid(_voice): _voice.stop()
	_release_override()

func _release_override() -> void:
	var owner: Object = _audio_owner.get_ref() if _audio_owner != null else null
	if _claimed and is_instance_valid(owner) and owner.has_method("clear_scoped_music_override"):
		owner.clear_scoped_music_override(self)
	_claimed = false

func shutdown() -> void:
	if _fade != null and _fade.is_valid(): _fade.kill()
	_active = false
	if is_instance_valid(_voice): _voice.stop()
	_release_override()

func _exit_tree() -> void:
	shutdown()
