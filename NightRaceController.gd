class_name NightRaceController
extends Node2D

## Uma corrida clandestina noturna: cruze a largada de carro, de noite, pra
## começar; passe pelos pontos em ordem; cruze a largada de novo pra
## terminar. Sem rivais — percurso, cronômetro e bússola. Cada instância é
## configurada por setup() a partir de uma entrada de RaceCatalog, então
## várias corridas (curta/média/longa) podem existir ao mesmo tempo no mundo.

enum State { IDLE, RUNNING }

var race_id: String = ""
var race_name: String = "CORRIDA"
var length_label: String = "CURTA"
var start_pos: Vector2 = Vector2.ZERO
var checkpoints: Array = []
var reward: int = 200
var best_time_bonus: int = 100

var _state: int = State.IDLE
var _next_checkpoint_index: int = 0
var _elapsed: float = 0.0
var _best_time: float = -1.0
var _active_car: Node2D = null

var _timer_layer: CanvasLayer
var _timer_label: Label
var _compass_root: Control
var _compass_arrow: Polygon2D
var _distance_label: Label

var _start_sign_label: Label
var _start_ring: Polygon2D
var _start_clock: float = 0.0

## Chamar antes de add_child() — preenche a configuração que _ready() usa
## pra montar os marcadores.
func setup(def: Dictionary) -> void:
	race_id = String(def.get("id", ""))
	race_name = String(def.get("name", "CORRIDA"))
	length_label = String(def.get("length_label", "CURTA"))
	start_pos = def.get("start", Vector2.ZERO)
	checkpoints = def.get("checkpoints", [])
	reward = int(def.get("reward", 200))
	best_time_bonus = int(def.get("best_time_bonus", 100))

func _ready() -> void:
	add_to_group("night_race")
	_build_marker(start_pos, Color("#f6e58d"), true)
	for i in range(checkpoints.size()):
		_build_marker(checkpoints[i], Color("#ffa502"), false, i + 1)
	_build_timer_ui()

func _process(delta: float) -> void:
	_start_clock += delta
	if _start_ring:
		var is_night := _is_night()
		_start_ring.color.a = (0.30 if is_night else 0.10) + sin(_start_clock * 2.2) * (0.12 if is_night else 0.04)
	if _start_sign_label:
		_start_sign_label.modulate.a = 1.0 if _is_night() else 0.55

	if _state == State.RUNNING:
		_elapsed += delta
		if _timer_label:
			_timer_label.text = _format_time(_elapsed)
		_update_compass()
	if _timer_layer:
		_timer_layer.visible = _state == State.RUNNING

## Ponto que o jogador precisa alcançar agora: próximo checkpoint, ou a
## largada de novo depois do último.
func _get_current_target_position() -> Vector2:
	if _next_checkpoint_index >= checkpoints.size():
		return global_position + start_pos
	return global_position + checkpoints[_next_checkpoint_index]

func _update_compass() -> void:
	if not _compass_arrow or not is_instance_valid(_active_car):
		return
	var target := _get_current_target_position()
	var to_target := target - _active_car.global_position
	_compass_arrow.rotation = to_target.angle()
	if _distance_label:
		_distance_label.text = "%dm" % int(to_target.length() / 8.0)

func _format_time(t: float) -> String:
	var minutes := int(t) / 60
	var seconds := fmod(t, 60.0)
	return "%02d:%05.2f" % [minutes, seconds]

func _build_timer_ui() -> void:
	_timer_layer = CanvasLayer.new()
	_timer_layer.layer = 5
	_timer_layer.visible = false
	add_child(_timer_layer)

	var name_label := Label.new()
	name_label.name = "RaceNameLabel"
	name_label.text = race_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color("#f6e58d"))
	name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.95))
	name_label.add_theme_constant_override("outline_size", 4)
	_timer_layer.add_child(name_label)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	name_label.offset_left = -160
	name_label.offset_right = 160
	name_label.offset_top = 68
	name_label.offset_bottom = 88

	_timer_label = Label.new()
	_timer_label.text = "00:00.00"
	_timer_label.add_theme_font_size_override("font_size", 26)
	_timer_label.add_theme_color_override("font_color", Color("#ffa502"))
	_timer_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.95))
	_timer_label.add_theme_constant_override("outline_size", 5)
	_timer_layer.add_child(_timer_label)
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_timer_label.offset_left = -80
	_timer_label.offset_right = 80
	_timer_label.offset_top = 96
	_timer_label.offset_bottom = 130
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Bússola: seta que aponta pro próximo ponto + distância aproximada.
	_compass_root = Control.new()
	_timer_layer.add_child(_compass_root)
	_compass_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_compass_root.offset_left = -30
	_compass_root.offset_right = 30
	_compass_root.offset_top = 138
	_compass_root.offset_bottom = 198
	_compass_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ring := Panel.new()
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(0.04, 0.06, 0.08, 0.55)
	ring_style.border_color = Color("#ffa502")
	ring_style.set_border_width_all(2)
	ring_style.set_corner_radius_all(30)
	ring.add_theme_stylebox_override("panel", ring_style)
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_compass_root.add_child(ring)

	# Seta desenhada apontando pra +X (ângulo 0), pivô no centro do círculo.
	_compass_arrow = Polygon2D.new()
	_compass_arrow.color = Color("#ffa502")
	_compass_arrow.polygon = PackedVector2Array([
		Vector2(16, 0), Vector2(-9, -9), Vector2(-3, 0), Vector2(-9, 9)
	])
	_compass_arrow.position = Vector2(30, 30)
	_compass_root.add_child(_compass_arrow)

	_distance_label = Label.new()
	_distance_label.text = "0m"
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.add_theme_font_size_override("font_size", 13)
	_distance_label.add_theme_color_override("font_color", Color("#ffa502"))
	_distance_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.95))
	_distance_label.add_theme_constant_override("outline_size", 4)
	_timer_layer.add_child(_distance_label)
	_distance_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_distance_label.offset_left = -60
	_distance_label.offset_right = 60
	_distance_label.offset_top = 202
	_distance_label.offset_bottom = 222

func _build_marker(pos: Vector2, color: Color, is_start: bool, index: int = 0) -> void:
	var marker := Node2D.new()
	marker.name = "StartFinish" if is_start else "Checkpoint%d" % index
	marker.position = pos
	add_child(marker)

	if is_start:
		_build_start_pad(marker)

	for side in [-1.0, 1.0]:
		var pylon := Polygon2D.new()
		pylon.color = color
		pylon.polygon = PackedVector2Array([
			Vector2(side * 46 - 4, -34), Vector2(side * 46 + 4, -34),
			Vector2(side * 46 + 4, 6), Vector2(side * 46 - 4, 6)
		])
		marker.add_child(pylon)
		var cap := Polygon2D.new()
		cap.color = color
		cap.polygon = PackedVector2Array([
			Vector2(side * 46, -44), Vector2(side * 46 + 8, -32), Vector2(side * 46 - 8, -32)
		])
		marker.add_child(cap)

	var beam := Polygon2D.new()
	beam.color = Color(color.r, color.g, color.b, 0.16)
	beam.polygon = PackedVector2Array([
		Vector2(-46, -34), Vector2(46, -34), Vector2(46, -4), Vector2(-46, -4)
	])
	marker.add_child(beam)

	if not is_start:
		var label := Label.new()
		label.text = "PONTO %d" % index
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(-40, -58)
		label.size = Vector2(80, 14)
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_color_override("font_color", color)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		marker.add_child(label)

	var trigger := Area2D.new()
	trigger.collision_layer = 0
	trigger.collision_mask = 1 # Mesma camada física do PlayerCar (default do CharacterBody2D)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(100, 44)
	col.shape = shape
	trigger.add_child(col)
	marker.add_child(trigger)

	if is_start:
		trigger.body_entered.connect(_on_start_line_entered)
	else:
		trigger.body_entered.connect(_on_checkpoint_entered.bind(index))

## Marcador de largada "no chão", estilo pista de corrida arcade: xadrez preto
## e branco + brilho pulsante + nome/comprimento da corrida flutuando acima.
## Visível o tempo todo (dá pra achar de dia), mas só acende forte à noite.
func _build_start_pad(marker: Node2D) -> void:
	_start_ring = Polygon2D.new()
	_start_ring.color = Color(1.0, 0.78, 0.2, 0.10)
	_start_ring.polygon = _create_circle_polygon(58.0, 20)
	_start_ring.z_index = -1
	marker.add_child(_start_ring)

	var checker := Node2D.new()
	checker.rotation = deg_to_rad(24.0)
	marker.add_child(checker)
	var square_size := 14.0
	for row in range(2):
		for col in range(6):
			var square := Polygon2D.new()
			var is_black := (row + col) % 2 == 0
			square.color = Color(0.08, 0.08, 0.08, 0.85) if is_black else Color(0.92, 0.92, 0.92, 0.85)
			var sx := (col - 2.5) * square_size
			var sy := (row - 0.5) * square_size
			square.polygon = PackedVector2Array([
				Vector2(sx, sy), Vector2(sx + square_size, sy),
				Vector2(sx + square_size, sy + square_size), Vector2(sx, sy + square_size)
			])
			checker.add_child(square)

	_start_sign_label = Label.new()
	_start_sign_label.text = "%s — %s" % [race_name, length_label]
	_start_sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_sign_label.position = Vector2(-80, -70)
	_start_sign_label.size = Vector2(160, 16)
	_start_sign_label.add_theme_font_size_override("font_size", 10)
	_start_sign_label.add_theme_color_override("font_color", Color("#f6e58d"))
	_start_sign_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_start_sign_label.add_theme_constant_override("shadow_offset_x", 1)
	_start_sign_label.add_theme_constant_override("shadow_offset_y", 1)
	marker.add_child(_start_sign_label)

	var sub_label := Label.new()
	sub_label.text = "DE NOITE: ENTRE DE CARRO PRA COMEÇAR"
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.position = Vector2(-90, -56)
	sub_label.size = Vector2(180, 12)
	sub_label.add_theme_font_size_override("font_size", 7)
	sub_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.85))
	sub_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	sub_label.add_theme_constant_override("shadow_offset_x", 1)
	sub_label.add_theme_constant_override("shadow_offset_y", 1)
	marker.add_child(sub_label)

func _create_circle_polygon(radius: float, points: int) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in range(points):
		var ang = (float(i) / float(points)) * TAU
		arr.append(Vector2(cos(ang), sin(ang)) * radius)
	return arr

func _is_player_vehicle(body: Node) -> bool:
	return body is Node and body.is_in_group("vehicle") and body.get("is_driven_by_player") == true

func _get_weather_manager() -> Node:
	return get_tree().get_first_node_in_group("day_night_manager")

func _is_night() -> bool:
	var weather := _get_weather_manager()
	return weather != null and bool(weather.get("is_dark"))

func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")

func _on_start_line_entered(body: Node2D) -> void:
	if not _is_player_vehicle(body):
		return
	if _state == State.RUNNING and _next_checkpoint_index >= checkpoints.size():
		_finish_race()
		return
	if _state == State.IDLE:
		_try_start_race(body)

func _try_start_race(car: Node2D) -> void:
	var hud := _hud()
	if not _is_night():
		if hud and hud.has_method("show_notice"):
			hud.show_notice("%s: SÓ DE NOITE" % race_name, Color("#ffa502"))
		return
	_state = State.RUNNING
	_elapsed = 0.0
	_next_checkpoint_index = 0
	_active_car = car
	if hud and hud.has_method("show_notice"):
		hud.show_notice("%s INICIADA! SIGA OS PONTOS ATÉ VOLTAR AQUI" % race_name, Color("#f6e58d"))
	_play_cue(ProceduralAudio.get_mission_start_stream(), -6.0, 1.0, global_position + start_pos)

func _on_checkpoint_entered(body: Node2D, index: int) -> void:
	if not _is_player_vehicle(body):
		return
	if _state != State.RUNNING:
		return
	if index != _next_checkpoint_index + 1:
		return
	_next_checkpoint_index = index
	var hud := _hud()
	if hud and hud.has_method("show_notice"):
		if _next_checkpoint_index >= checkpoints.size():
			hud.show_notice("ÚLTIMO PONTO! VOLTE PRA LARGADA", Color("#ffa502"))
		else:
			hud.show_notice("PONTO %d/%d" % [_next_checkpoint_index, checkpoints.size()], Color("#ffa502"))
	_play_cue(ProceduralAudio.get_ui_click_stream(), -8.0, 1.3, global_position + checkpoints[index - 1])

func _finish_race() -> void:
	_state = State.IDLE
	_active_car = null
	var final_time := _elapsed
	var is_new_best := _best_time < 0.0 or final_time < _best_time
	var final_reward := reward
	if is_new_best:
		_best_time = final_time
		final_reward += best_time_bonus

	var player := get_tree().get_first_node_in_group("player")
	if player:
		if "money" in player:
			player.money += final_reward
		if player.has_method("report_race_finished"):
			player.report_race_finished(is_new_best)
		if player.has_method("_refresh_weapon_ui"):
			player._refresh_weapon_ui()

	var hud := _hud()
	if hud and hud.has_method("show_notice"):
		var msg := "%s CONCLUÍDA EM %s! +$%d" % [race_name, _format_time(final_time), final_reward]
		if is_new_best:
			msg += " (NOVO RECORDE)"
		hud.show_notice(msg, Color("#2ed573"))
	_play_cue(ProceduralAudio.get_mission_passed_stream(), -4.0, 1.0, global_position + start_pos)

func _play_cue(stream: AudioStream, volume_db: float, pitch: float, at_position: Vector2) -> void:
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = 900.0
	get_tree().current_scene.add_child(p)
	p.global_position = at_position
	p.play()
	p.finished.connect(p.queue_free)
