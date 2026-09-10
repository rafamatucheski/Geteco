extends Node
## Compartilhado pelos dois tipos de carro: mixagem, sintonia e identificação.
var _audio: AudioStreamPlayer2D
var _last_stream: AudioStream
var _was_driven := false
var _saved_position := 0.0
var _notice: Label
var _notice_time := 0.0
var _focus := 1.0

static func attach(audio: AudioStreamPlayer2D) -> void:
	var receiver := preload("res://audio/living_city/VehicleRadioReceiver.gd").new()
	receiver.name = "RadioReceiver"
	audio.add_child(receiver)

func _ready() -> void:
	_audio = get_parent() as AudioStreamPlayer2D
	_audio.bus = &"Music"
	_audio.volume_db = -12.0

func _process(delta: float) -> void:
	var car := _audio.get_parent()
	var driven: bool = car.get("is_driven_by_player") == true
	if driven:
		var changed := _audio.stream != _last_stream
		if changed or not _was_driven:
			if changed:
				_last_stream = _audio.stream
				_saved_position = 0.0
			elif _saved_position > 0.0 and _audio.playing:
				_audio.seek(_saved_position)
			_show_station()
		if _audio.playing:
			# O mixer pode ainda reportar zero no quadro de play/seek.
			var playback_position := _audio.get_playback_position()
			if playback_position > 0.0:
				_saved_position = playback_position
		var actor := get_tree().get_first_node_in_group("player")
		var focused: bool = is_instance_valid(actor) and actor.get("is_in_dialogue") == true
		_focus = move_toward(_focus, 0.2 if focused else 1.0, delta * 3.0)
		_audio.volume_db = -12.0 + linear_to_db(maxf(_focus, 0.001))
	_was_driven = driven
	_notice_time = maxf(0.0, _notice_time - delta)
	if is_instance_valid(_notice):
		_notice.visible = driven and _notice_time > 0.0
		_notice.modulate.a = minf(1.0, _notice_time)

func _show_station() -> void:
	if not is_instance_valid(_notice):
		var layer := CanvasLayer.new()
		layer.layer = 8
		add_child(layer)
		_notice = Label.new()
		_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_notice.position = Vector2(-230, 82)
		_notice.size = Vector2(460, 58)
		_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_notice.add_theme_font_size_override("font_size", 18)
		_notice.add_theme_color_override("font_color", Color("f2e2b9"))
		_notice.add_theme_color_override("font_outline_color", Color("172022"))
		_notice.add_theme_constant_override("outline_size", 6)
		layer.add_child(_notice)
	var title := _audio.stream.resource_name if _audio.stream else "RADIO OFF"
	if title == "RADIO OFF":
		var settings := get_node_or_null("/root/SettingsManager")
		title = "RÁDIO DESLIGADO" if settings == null or String(settings.language).begins_with("pt") else "RADIO OFF"
	_notice.text = title
	_notice_time = 3.5
