class_name DriftChallengeZone
extends Node2D

## Zona de desafio de derrapagem: entre de carro e derrape dentro do círculo.
## Pontos escalam com a velocidade lateral e um combo que cresce enquanto a
## derrapada não para. O desafio termina ao sair da zona ou depois de um
## tempo máximo — sem precisar de rivais nem trilha fixa.

const MAX_DURATION := 25.0
const COMBO_GRACE := 0.5
const COMBO_GROWTH := 0.18
const COMBO_MAX := 5.0
const MIN_LATERAL_TO_SCORE := 40.0

var zone_id: String = ""
var zone_name: String = "ZONA DE DRIFT"
var radius: float = 90.0
var reward_per_1000: int = 150

var _active_car: Node2D = null
var _running: bool = false
var _score: float = 0.0
var _combo: float = 1.0
var _no_drift_timer: float = 0.0
var _elapsed: float = 0.0
var _best_score: int = 0
var _pulse_clock: float = 0.0

var _ring_dashes: Array = []
var _fill: Polygon2D

var _hud_layer: CanvasLayer
var _score_label: Label
var _combo_label: Label

## Chamar antes de add_child() — preenche a configuração que _ready() usa.
func setup(def: Dictionary) -> void:
	zone_id = String(def.get("id", ""))
	zone_name = String(def.get("name", "ZONA DE DRIFT"))
	radius = float(def.get("radius", 90.0))
	reward_per_1000 = int(def.get("reward_per_1000", 150))

func _ready() -> void:
	add_to_group("drift_zone")
	_build_visual()
	_build_trigger()
	_build_hud()

func _build_visual() -> void:
	_fill = Polygon2D.new()
	_fill.color = Color(1.0, 0.65, 0.1, 0.08)
	_fill.polygon = _create_circle_polygon(radius, 28)
	_fill.z_index = -1
	add_child(_fill)

	# Anel tracejado (dashes) marcando o limite da zona.
	var dash_count := 18
	for i in range(dash_count):
		var ang := (float(i) / float(dash_count)) * TAU
		var dash := Polygon2D.new()
		dash.color = Color("#ffa502")
		var dir := Vector2(cos(ang), sin(ang))
		var tangent := Vector2(-dir.y, dir.x)
		var inner := dir * (radius - 4.0)
		var outer := dir * (radius + 4.0)
		var half_w := tangent * 5.0
		dash.polygon = PackedVector2Array([
			inner - half_w, outer - half_w, outer + half_w, inner + half_w
		])
		add_child(dash)
		_ring_dashes.append(dash)

	var name_label := Label.new()
	name_label.text = zone_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-90, -radius - 26)
	name_label.size = Vector2(180, 16)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color("#ffa502"))
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(name_label)

	var sub_label := Label.new()
	sub_label.text = "DERRAPE AQUI DENTRO"
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.position = Vector2(-90, -radius - 12)
	sub_label.size = Vector2(180, 12)
	sub_label.add_theme_font_size_override("font_size", 7)
	sub_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.85))
	sub_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	sub_label.add_theme_constant_override("shadow_offset_x", 1)
	sub_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(sub_label)

func _create_circle_polygon(r: float, points: int) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in range(points):
		var ang = (float(i) / float(points)) * TAU
		arr.append(Vector2(cos(ang), sin(ang)) * r)
	return arr

func _build_trigger() -> void:
	var trigger := Area2D.new()
	trigger.collision_layer = 0
	trigger.collision_mask = 1 # Mesma camada física do PlayerCar
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	col.shape = shape
	trigger.add_child(col)
	add_child(trigger)
	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 5
	_hud_layer.visible = false
	add_child(_hud_layer)

	_score_label = Label.new()
	_score_label.text = "0"
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 30)
	_score_label.add_theme_color_override("font_color", Color("#ffa502"))
	_score_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.95))
	_score_label.add_theme_constant_override("outline_size", 5)
	_hud_layer.add_child(_score_label)
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score_label.offset_left = -100
	_score_label.offset_right = 100
	_score_label.offset_top = 96
	_score_label.offset_bottom = 134

	_combo_label = Label.new()
	_combo_label.text = "COMBO x1.0"
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.add_theme_font_size_override("font_size", 15)
	_combo_label.add_theme_color_override("font_color", Color("#f6e58d"))
	_combo_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.95))
	_combo_label.add_theme_constant_override("outline_size", 4)
	_hud_layer.add_child(_combo_label)
	_combo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_combo_label.offset_left = -100
	_combo_label.offset_right = 100
	_combo_label.offset_top = 134
	_combo_label.offset_bottom = 156

func _is_player_vehicle(body: Node) -> bool:
	return body is Node and body.is_in_group("vehicle") and body.get("is_driven_by_player") == true

func _on_body_entered(body: Node2D) -> void:
	if _running or not _is_player_vehicle(body):
		return
	_running = true
	_active_car = body
	_score = 0.0
	_combo = 1.0
	_no_drift_timer = 0.0
	_elapsed = 0.0
	_hud_layer.visible = true
	_update_hud()

func _on_body_exited(body: Node2D) -> void:
	if _running and body == _active_car:
		_end_challenge()

func _process(delta: float) -> void:
	_pulse_clock += delta
	var pulse := 0.5 + sin(_pulse_clock * 2.0) * 0.5
	for dash in _ring_dashes:
		dash.color.a = 0.55 + pulse * 0.35
	if _fill:
		_fill.color.a = 0.06 + pulse * 0.05

	if not _running:
		return
	if not is_instance_valid(_active_car):
		_end_challenge()
		return

	_elapsed += delta
	var is_drifting: bool = bool(_active_car.get("is_skidding"))
	var lateral: float = float(_active_car.get("lateral_speed"))

	if is_drifting and lateral > MIN_LATERAL_TO_SCORE:
		_no_drift_timer = 0.0
		_combo = minf(COMBO_MAX, _combo + COMBO_GROWTH * delta)
		_score += lateral * _combo * delta * 0.55
	else:
		_no_drift_timer += delta
		if _no_drift_timer > COMBO_GRACE:
			_combo = 1.0

	_update_hud()
	if _elapsed >= MAX_DURATION:
		_end_challenge()

func _update_hud() -> void:
	if _score_label:
		_score_label.text = str(int(_score))
	if _combo_label:
		_combo_label.text = "COMBO x%.1f" % _combo

func _end_challenge() -> void:
	_running = false
	_hud_layer.visible = false
	var final_score := int(_score)
	var is_new_best := final_score > _best_score
	if is_new_best:
		_best_score = final_score
	var reward := int(float(final_score) / 1000.0 * reward_per_1000)

	var player := get_tree().get_first_node_in_group("player")
	if player:
		if reward > 0 and "money" in player:
			player.money += reward
		if player.has_method("report_drift_score"):
			player.report_drift_score(final_score, is_new_best)
		if player.has_method("_refresh_weapon_ui"):
			player._refresh_weapon_ui()

	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_notice"):
		if final_score <= 0:
			hud.show_notice("%s: SAIU SEM PONTUAR" % zone_name, Color(0.7, 0.7, 0.7))
		else:
			var msg := "%s: %d PONTOS! +$%d" % [zone_name, final_score, reward]
			if is_new_best:
				msg += " (RECORDE)"
			hud.show_notice(msg, Color("#ffa502"))

	if final_score > 0:
		var p := AudioStreamPlayer2D.new()
		p.bus = &"SFX"
		p.stream = ProceduralAudio.get_ui_click_stream()
		p.pitch_scale = 0.9
		p.volume_db = -6.0
		p.max_distance = 700.0
		get_tree().current_scene.add_child(p)
		p.global_position = global_position
		p.play()
		p.finished.connect(p.queue_free)

	_active_car = null
	_score = 0.0
	_combo = 1.0
	_elapsed = 0.0
