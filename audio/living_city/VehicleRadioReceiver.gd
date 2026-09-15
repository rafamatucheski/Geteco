extends Node
## Compartilhado por carros, motos e caminhões: mixagem, sintonia e identificação.
var _audio: AudioStreamPlayer2D
var _last_stream: AudioStream
var _was_driven := false
var _saved_position := 0.0
var _notice: Label
var _notice_time := 0.0
var _focus := 1.0
static var muted := false

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
		if _audio.playing:
			# O mixer pode ainda reportar zero no quadro de play/seek.
			var playback_position := _audio.get_playback_position()
			if playback_position > 0.0:
				_saved_position = playback_position
		var actor := get_tree().get_first_node_in_group("player")
		var focused: bool = is_instance_valid(actor) and actor.get("is_in_dialogue") == true
		_focus = move_toward(_focus, 0.2 if focused else 1.0, delta * 3.0)
		_audio.volume_db = -80.0 if muted else -12.0 + linear_to_db(maxf(_focus, 0.001))
	_was_driven = driven
	_notice_time = maxf(0.0, _notice_time - delta)
	if is_instance_valid(_notice):
		_notice.visible = driven and _notice_time > 0.0
	if not driven:
		_notice_time = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	if get_tree().paused or _audio.get_parent().get("is_driven_by_player") != true:
		return
	var actor := get_tree().get_first_node_in_group("player")
	if is_instance_valid(actor) and actor.get("is_in_dialogue") == true:
		return
	var input_manager := get_node_or_null("/root/GameInput")
	if input_manager != null and input_manager.get("remapping") == true:
		return
	_change_station(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
	get_viewport().set_input_as_handled()

func _change_station(direction: int) -> void:
	var car := _audio.get_parent()
	if car.get("is_driven_by_player") != true:
		return
	var tracks: Array = car.get("radio_tracks")
	if tracks.is_empty():
		return
	var index := posmod(int(car.get("radio_index")) + direction, tracks.size())
	car.set("radio_index", index)
	_audio.stream = tracks[index]
	_audio.play()
	_show_station()

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
	_notice_time = 3.0
	_notice.show()
