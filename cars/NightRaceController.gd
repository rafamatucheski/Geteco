class_name NightRaceController
extends Node2D
const UI := preload("res://ui/MotorsportUI.gd")
enum State { IDLE, COUNTDOWN, RUNNING, RESULT }
var race_id := ""
var race_name := "VOLTA DO PORTO"
var length_label := "CURTA"
var start_pos := Vector2.ZERO
var checkpoints: Array = []
var reward := 400
var best_time_bonus := 200
var _state := State.IDLE
var _active_car: Node2D
var _next_checkpoint_index := 0
var _elapsed := 0.0
var _best_time := -1.0
var _countdown := 0.0
var _card: Dictionary
var _markers: Array[Node2D] = []
var _previous_position := Vector2.ZERO
var _visual_clock := 0.0

func setup(def: Dictionary) -> void:
	race_id = def.get("id", "")
	race_name = def.get("name", race_name)
	length_label = def.get("length_label", length_label)
	start_pos = def.get("start", Vector2.ZERO)
	checkpoints = def.get("checkpoints", [])
	reward = def.get("reward", reward)
	best_time_bonus = def.get("best_time_bonus",best_time_bonus)

func _ready() -> void:
	add_to_group("night_race")
	z_index = 5
	_card = UI.card(self, UI.RACE)
	var marker_material := CanvasItemMaterial.new()
	marker_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = marker_material
	for i in checkpoints.size():
		var marker := Node2D.new()
		marker.position = checkpoints[i]
		add_child(marker)
		UI.sign_at(marker,Vector2.ZERO,"%02d" % (i+1),UI.RACE)
		_markers.append(marker)
	_update_markers()

func _draw() -> void:
	var color := UI.RACE if _is_night() else Color("7e939e")
	UI.beacon(self,start_pos,color,_visual_clock)
	if _state == State.RUNNING:
		var target := to_local(_get_current_target_position())
		for side in [-1,1]:
			draw_polyline(PackedVector2Array([target+Vector2(side*42,-14),target+Vector2(side*35,0),target+Vector2(side*42,14)]),Color(UI.RACE,0.7),1.5,true)

func _is_night() -> bool:
	var weather := get_tree().get_first_node_in_group("day_night_manager")
	# A daytime storm darkens headlights, but does not make it night.
	return weather != null and (float(weather.time_of_day) > 0.78 or float(weather.time_of_day) < 0.28)

func _process(delta: float) -> void:
	_visual_clock += delta
	UI.animate(self,_card,_visual_clock)
	queue_redraw()
	if _state == State.RESULT:
		_countdown -= delta
		UI.present(self,_card,true,1)
		if _countdown <= 0: _state = State.IDLE
		return
	if _state == State.IDLE:
		_refresh_best_time()
		var car := UI.driver(self)
		UI.present(self,_card,is_instance_valid(car) and car.global_position.distance_to(to_global(start_pos)) < 175)
		if not _card.layer.visible: return
		_card.title.text = "Contrarrelógio · " + length_label.to_lower()
		if _best_time > 0.0: _card.title.text = "Concluída · " + length_label.to_lower()
		_card.value.text = race_name.capitalize()
		_card.detail.text = "%d pontos → largada · sem rivais\n$%d + recorde $%d" % [checkpoints.size(),reward,best_time_bonus]
		if _best_time > 0.0: _card.detail.text = "Recorde: %s\n%s" % [_format_time(_best_time), _card.detail.text]
		var ready: bool = car.global_position.distance_to(to_global(start_pos)) < 60 and car.velocity.length() < 25
		_card.hint.text = "Disponível das 18:43 às 06:43" if not _is_night() else "[%s] Preparar largada" % UI.key(self,"interact") if ready else "Pare na bandeira para começar"
		if ready and _is_night() and _best_time > 0.0: _card.hint.text = "[%s] Correr novamente" % UI.key(self,"interact")
		if ready and _is_night() and Input.is_action_just_pressed("interact"): _try_start_race(car)
		return
	if not is_instance_valid(_active_car) or _active_car.get("is_driven_by_player") != true or _active_car.get("is_broken") == true:
		_cancel("Você saiu do carro ou o veículo quebrou")
		return
	UI.present(self,_card,true,2)
	if _state == State.COUNTDOWN:
		if _active_car.global_position.distance_to(to_global(start_pos)) > 65:
			_cancel("Largada antecipada / pare na bandeira e tente de novo")
			return
		var beat := ceili(_countdown)
		_countdown -= delta
		if ceili(_countdown) != beat: UI.countdown(self, _countdown <= 0)
		_card.title.text = "Prepare-se · " + race_name.capitalize()
		_card.value.text = str(maxi(1,ceili(_countdown)))
		_card.detail.text = "Aguarde na largada"
		_card.hint.text = "Cronômetro começa no JÁ"
		if _countdown <= 0:
			_state = State.RUNNING
			_previous_position = _active_car.global_position
			_update_markers()
		return
	_elapsed += delta
	var target := _get_current_target_position()
	var closest := Geometry2D.get_closest_point_to_segment(target,_previous_position,_active_car.global_position)
	if closest.distance_to(target) < 58:
		if _next_checkpoint_index >= checkpoints.size():
			_finish_race()
			return
		_next_checkpoint_index += 1
		UI.checkpoint(self)
		_update_markers()
	_previous_position = _active_car.global_position
	_card.title.text = ("Já! · " if _elapsed < 1.5 else "Contrarrelógio · ") + race_name.capitalize()
	_card.value.text = _format_time(_elapsed)
	_card.detail.text = "Chegada · volte à bandeira" if _next_checkpoint_index >= checkpoints.size() else "Próximo ponto %d / %d" % [_next_checkpoint_index+1,checkpoints.size()]
	_card.hint.text = "%d m · siga a rota azul" % roundi(_active_car.global_position.distance_to(_get_current_target_position())/16.6)
	if _elapsed > 600: _cancel("Tempo limite de 10 minutos atingido")

func _try_start_race(car: Node2D) -> void:
	if not _is_night() or not UI.available(self) or checkpoints.is_empty(): return
	_refresh_best_time()
	add_to_group("active_motorsport")
	_active_car = car
	_state = State.COUNTDOWN
	_countdown = 3
	_elapsed = 0
	_next_checkpoint_index = 0
	UI.present(self,_card,true,2)
	UI.cue(self)

func _get_current_target_position() -> Vector2:
	return to_global(start_pos if _next_checkpoint_index >= checkpoints.size() else checkpoints[_next_checkpoint_index])

func _update_markers() -> void:
	for i in _markers.size(): _markers[i].visible = _state == State.RUNNING and i == _next_checkpoint_index
	queue_redraw()

func _format_time(t: float) -> String:
	var centiseconds := maxi(0, roundi(t * 100.0))
	return "%02d:%02d.%02d" % [centiseconds / 6000, (centiseconds / 100) % 60, centiseconds % 100]

func _refresh_best_time() -> void:
	var campaign := get_node_or_null("/root/CampaignState")
	if campaign and not race_id.is_empty():
		_best_time = campaign.get_race_best_time(race_id)

func _cancel(reason: String) -> void:
	_show_result("CORRIDA CANCELADA",reason,"Sem prêmio / tente de novo")

func _show_result(title: String, detail: String, hint: String) -> void:
	remove_from_group("active_motorsport")
	_state = State.RESULT
	_countdown = 5
	_active_car = null
	_card.title.text = title
	_card.value.text = _format_time(_elapsed)
	_card.detail.text = detail
	_card.hint.text = hint
	_update_markers()

func _finish_race() -> void:
	UI.cue(self,true)
	_refresh_best_time()
	var record := _best_time < 0 or _elapsed < _best_time
	if record: _best_time = _elapsed
	var campaign := get_node_or_null("/root/CampaignState")
	if campaign: campaign.record_race_time(race_id, _elapsed)
	var prize := reward + (best_time_bonus if record else 0)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.money += prize
		if player.has_method("report_race_finished"): player.report_race_finished(record)
		if player.has_method("_refresh_weapon_ui"): player._refresh_weapon_ui()
	_show_result("CORRIDA CONCLUÍDA","%s\n+$%d%s" % [race_name.capitalize(),prize," · Novo recorde!" if record else ""],"Recorde: " + _format_time(_best_time))
	var saves := get_node_or_null("/root/SaveManager")
	if saves: saves.request_autosave("Corrida concluída: " + race_name.capitalize())
