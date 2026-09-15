class_name DriftChallengeZone
extends Node2D
const UI := preload("res://ui/MotorsportUI.gd")
const MAX_DURATION := 25.0
const COMBO_GRACE := 1.0
const MIN_LATERAL_TO_SCORE := 35.0
var zone_id := ""
var zone_name := "PÁTIO DE DRIFT"
var radius := 125.0
var reward_per_1000 := 150
var _active_car: Node2D
var _running := false
var _score := 0.0
var _combo := 1.0
var _elapsed := 0.0
var _no_drift_timer := 0.0
var _outside := 0.0
var _best_score := 0
var _result_time := 0.0
var _card: Dictionary
var _visual_clock := 0.0

func setup(def: Dictionary) -> void:
	zone_id = def.get("id", "")
	zone_name = def.get("name", zone_name)
	radius = def.get("radius", radius)
	reward_per_1000 = def.get("reward_per_1000", reward_per_1000)

func _ready() -> void:
	add_to_group("drift_zone")
	z_index = 5
	var marker_material := CanvasItemMaterial.new()
	marker_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = marker_material
	_card = UI.card(self, UI.DRIFT)
	queue_redraw()

func _draw() -> void:
	UI.beacon(self,Vector2.ZERO,UI.DRIFT,_visual_clock,true)
	if _running or (not _card.is_empty() and _card.layer.visible):
		# Dashed playable boundary stays visible during the invitation and run.
		for i in 32:
			var angle := i * TAU / 32.0
			draw_arc(Vector2.ZERO,radius,angle,angle+0.12,5,Color(UI.DRIFT,0.7),2.0,true)

func _process(delta: float) -> void:
	_visual_clock += delta
	UI.animate(self,_card,_visual_clock)
	queue_redraw()
	if _result_time > 0:
		_result_time -= delta
		UI.present(self,_card,true,1)
		return
	if not _running:
		var car := UI.driver(self)
		var near := is_instance_valid(car) and car.global_position.distance_to(global_position) < radius + 65
		UI.present(self,_card,near)
		if not _card.layer.visible: return
		_card.title.text = "Drift · " + zone_name.capitalize()
		_card.value.text = "Drift livre · 25 s"
		_card.detail.text = "%s\nDerrape dentro do círculo. $%d por 1.000 pts; sem meta mínima." % [_controls(), reward_per_1000]
		var ready: bool = car.global_position.distance_to(global_position) <= radius and car.velocity.length() < 35
		_card.hint.text = "[%s] Começar desafio" % UI.key(self,"interact") if ready else "Pare com o carro dentro do círculo"
		if ready and Input.is_action_just_pressed("interact"): _start(car)
		return
	if not is_instance_valid(_active_car) or _active_car.get("is_driven_by_player") != true or _active_car.get("is_broken") == true:
		_end_challenge(false)
		return
	UI.present(self,_card,true,2)
	_elapsed += delta
	var inside := _active_car.global_position.distance_to(global_position) <= radius
	_outside = 0.0 if inside else _outside + delta
	var lateral := absf(_active_car.velocity.dot(Vector2.from_angle(_active_car.global_rotation).orthogonal()))
	if inside and lateral > MIN_LATERAL_TO_SCORE and _active_car.velocity.length() > 60:
		_no_drift_timer = 0
		_combo = minf(5.0, _combo + delta * 0.18)
		_score += lateral * _combo * delta * 0.55
	else:
		_no_drift_timer += delta
		if _no_drift_timer > COMBO_GRACE: _combo = 1.0
	_card.title.text = "Drift · %02d s" % ceili(maxf(0,MAX_DURATION-_elapsed))
	_card.value.text = "%d pts    ×%.1f" % [int(_score),_combo]
	if not inside:
		_card.detail.text = "Fora do círculo: não pontua"
	elif _no_drift_timer == 0:
		_card.detail.text = "Derrapando! Combo crescendo"
	elif _active_car.velocity.length() <= 60:
		_card.detail.text = "Ganhe velocidade · [%s] acelerar" % UI.key(self,"move_up")
	else:
		_card.detail.text = "Vire e toque [%s] para soltar a traseira" % UI.key(self,"handbrake")
	_card.hint.text = "Solte o freio de mão e mantenha a curva" if inside else "Volte em %.1f s ou a tentativa termina" % maxf(0,3.0-_outside)
	if _elapsed >= MAX_DURATION or _outside >= 3.0: _end_challenge()

func _controls() -> String:
	return "[%s] acelerar · [%s/%s] virar\nToque [%s] em curva e solte" % [UI.key(self,"move_up"), UI.key(self,"move_left"), UI.key(self,"move_right"), UI.key(self,"handbrake")]

func _start(car: Node2D) -> void:
	if not UI.available(self): return
	add_to_group("active_motorsport")
	UI.cue(self)
	_active_car = car
	_running = true
	_score = 0
	_combo = 1
	_elapsed = 0
	_no_drift_timer = 0
	_outside = 0

func _end_challenge(completed := true) -> void:
	_running = false
	remove_from_group("active_motorsport")
	var score := int(_score) if completed else 0
	var record := score > _best_score
	if score > 0: UI.cue(self,true)
	_best_score = maxi(score,_best_score)
	var reward := int(score / 1000.0 * reward_per_1000)
	var player := get_tree().get_first_node_in_group("player")
	if player and completed:
		player.money += reward
		if player.has_method("report_drift_score"): player.report_drift_score(score,record)
		if player.has_method("_refresh_weapon_ui"): player._refresh_weapon_ui()
	_card.title.text = "Drift · " + ("novo recorde" if record else "resultado" if completed else "cancelado")
	_card.value.text = "%d pts · +$%d" % [score,reward]
	_card.detail.text = "Melhor nesta sessão: %d PTS" % _best_score
	_card.hint.text = "Pare no pátio para tentar de novo"
	_result_time = 4.0
	_active_car = null
