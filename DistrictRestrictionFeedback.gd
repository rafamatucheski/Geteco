class_name DistrictRestrictionFeedback
extends CanvasLayer

enum DisplayState { HIDDEN, WARNING, BREACH }

@export var auto_connect: bool = true
@export var manager_path: NodePath = NodePath("/root/DistrictRestriction")
@export_range(0.25, 10.0, 0.05) var warning_duration: float = 2.8

@onready var alert_panel: PanelContainer = $Root/AlertPanel
@onready var alert_icon: Label = $Root/AlertPanel/Margin/Row/Icon
@onready var alert_label: Label = $Root/AlertPanel/Margin/Row/Message
@onready var warning_timer: Timer = $WarningTimer
@onready var warning_audio: AudioStreamPlayer = $WarningBeep
@onready var breach_audio: AudioStreamPlayer = $BreachAlarm

var display_state: DisplayState = DisplayState.HIDDEN
var _manager: Node = null
var _warning_style: StyleBoxFlat
var _breach_style: StyleBoxFlat
var _fade_tween: Tween = null
var _pulse_tween: Tween = null


func _ready() -> void:
	add_to_group("district_restriction_feedback")
	_warning_style = _make_panel_style(Color(0.11, 0.09, 0.025, 0.96), Color("f5c542"))
	_breach_style = _make_panel_style(Color(0.20, 0.025, 0.035, 0.97), Color("ff334f"))
	warning_audio.stream = _make_restriction_beep(false)
	breach_audio.stream = _make_restriction_beep(true)
	warning_timer.timeout.connect(_on_warning_timeout)
	_hide_immediately()
	if auto_connect:
		call_deferred("_connect_configured_manager")


func _exit_tree() -> void:
	_disconnect_manager()


## Public binding API used by tests and by scenes that prefer injection over
## the default /root/DistrictRestriction autoload.
func bind_manager(manager: Node) -> bool:
	if not is_instance_valid(manager):
		return false
	var required_signals := [
		&"boundary_warning_requested",
		&"boundary_breached",
		&"lethal_pursuit_requested",
		&"restriction_event_reset",
	]
	for signal_name in required_signals:
		if not manager.has_signal(signal_name):
			return false
	_disconnect_manager()
	_manager = manager
	_connect_once(&"boundary_warning_requested", Callable(self, "_on_boundary_warning_requested"))
	_connect_once(&"boundary_breached", Callable(self, "_on_boundary_breached"))
	_connect_once(&"lethal_pursuit_requested", Callable(self, "_on_lethal_pursuit_requested"))
	_connect_once(&"restriction_event_reset", Callable(self, "_on_restriction_event_reset"))
	return true


func is_manager_connected() -> bool:
	return is_instance_valid(_manager) and _manager.is_connected(
		&"boundary_warning_requested",
		Callable(self, "_on_boundary_warning_requested")
	)


func _connect_configured_manager() -> void:
	var manager := get_node_or_null(manager_path)
	if manager != null:
		bind_manager(manager)


func _connect_once(signal_name: StringName, callable: Callable) -> void:
	if not _manager.is_connected(signal_name, callable):
		_manager.connect(signal_name, callable)


func _disconnect_manager() -> void:
	if not is_instance_valid(_manager):
		_manager = null
		return
	var connections := {
		&"boundary_warning_requested": Callable(self, "_on_boundary_warning_requested"),
		&"boundary_breached": Callable(self, "_on_boundary_breached"),
		&"lethal_pursuit_requested": Callable(self, "_on_lethal_pursuit_requested"),
		&"restriction_event_reset": Callable(self, "_on_restriction_event_reset"),
	}
	for signal_name in connections:
		var callable: Callable = connections[signal_name]
		if _manager.is_connected(signal_name, callable):
			_manager.disconnect(signal_name, callable)
	_manager = null


func _on_boundary_warning_requested(message: String, _exit_anchor: Node2D, _actor: Node2D, _distance: float) -> void:
	if display_state == DisplayState.BREACH:
		return
	display_state = DisplayState.WARNING
	alert_panel.add_theme_stylebox_override("panel", _warning_style)
	alert_icon.text = "⚠"
	alert_icon.add_theme_color_override("font_color", Color("ffd95a"))
	alert_label.add_theme_color_override("font_color", Color("fff3bd"))
	alert_label.text = message if not message.is_empty() else "TORNOZELEIRA: RETORNE AO BAIRRO."
	_stop_visual_tweens()
	_show_with_fade()
	warning_timer.start(warning_duration)
	warning_audio.play()


func _on_boundary_breached(_exit_anchor: Node2D, _actor: Node2D, destination_district: int) -> void:
	_show_breach("TORNOZELEIRA VIOLADA · DISTRITO %d BLOQUEADO" % destination_district)


func _on_lethal_pursuit_requested(minimum_stars: int, _exit_anchor: Node2D, _actor: Node2D) -> void:
	var message := "TORNOZELEIRA VIOLADA · PERSEGUIÇÃO ATIVA %d★" % minimum_stars
	if display_state != DisplayState.BREACH:
		_show_breach(message)
	else:
		alert_label.text = message


func _on_restriction_event_reset() -> void:
	_hide_immediately()


func _show_breach(message: String) -> void:
	display_state = DisplayState.BREACH
	warning_timer.stop()
	warning_audio.stop()
	alert_panel.add_theme_stylebox_override("panel", _breach_style)
	alert_icon.text = "!"
	alert_icon.add_theme_color_override("font_color", Color("ff4961"))
	alert_label.add_theme_color_override("font_color", Color("ffd6dc"))
	alert_label.text = message
	_stop_visual_tweens()
	_show_with_fade()
	breach_audio.play()
	_pulse_tween = alert_icon.create_tween().set_loops()
	_pulse_tween.tween_property(alert_icon, "modulate", Color(1.0, 0.32, 0.38, 1.0), 0.28)
	_pulse_tween.tween_property(alert_icon, "modulate", Color.WHITE, 0.28)


func _show_with_fade() -> void:
	alert_panel.show()
	alert_panel.modulate.a = 0.0
	_fade_tween = alert_panel.create_tween()
	_fade_tween.tween_property(alert_panel, "modulate:a", 1.0, 0.12)


func _on_warning_timeout() -> void:
	if display_state != DisplayState.WARNING:
		return
	display_state = DisplayState.HIDDEN
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = alert_panel.create_tween()
	_fade_tween.tween_property(alert_panel, "modulate:a", 0.0, 0.20)
	_fade_tween.tween_callback(alert_panel.hide)


func _hide_immediately() -> void:
	display_state = DisplayState.HIDDEN
	warning_timer.stop()
	warning_audio.stop()
	breach_audio.stop()
	_stop_visual_tweens()
	alert_icon.modulate = Color.WHITE
	alert_panel.modulate = Color.WHITE
	alert_panel.hide()


func _stop_visual_tweens() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_fade_tween = null
	_pulse_tween = null
	alert_icon.modulate = Color.WHITE


func _make_panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	style.shadow_size = 5
	return style


func _make_restriction_beep(is_breach: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.76 if is_breach else 0.30
	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index in sample_count:
		var time := float(index) / float(sample_rate)
		var pulse_length := 0.12 if is_breach else 0.14
		var local_time := fmod(time, pulse_length)
		var gate_length := 0.085 if is_breach else 0.075
		var gate := 1.0 if local_time < gate_length else 0.0
		var pulse_index := int(time / pulse_length)
		var frequency := (760.0 if pulse_index % 2 == 0 else 1120.0) if is_breach else 980.0
		var edge := minf(1.0, local_time * 90.0) * minf(1.0, maxf(0.0, gate_length - local_time) * 90.0)
		var sample := sin(TAU * frequency * time) * gate * edge * (0.38 if is_breach else 0.30)
		data.encode_s16(index * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream
