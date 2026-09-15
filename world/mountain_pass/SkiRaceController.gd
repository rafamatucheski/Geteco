class_name SkiRaceController
extends Node2D

const UI := preload("res://ui/MotorsportUI.gd")
enum State { IDLE, COUNTDOWN, RUNNING, RESULT }
var race_id := ""
var race_name := "DESCIDA"
var difficulty := "VERDE"
var start_pos := Vector2.ZERO
var checkpoints: Array = []
var reward := 250
var best_time_bonus := 100
var required_clues := 0
var _state := State.IDLE
var _player: CharacterBody2D
var _next_index := 0
var _elapsed := 0.0
var _best_time := -1.0
var _countdown := 0.0
var _card: Dictionary
var _previous_position := Vector2.ZERO
var _visual_clock := 0.0
var start_arch: Node2D
var finish_arch: Node2D

func setup(definition: Dictionary) -> void:
	race_id = definition.get("id", "")
	race_name = definition.get("name", race_name)
	difficulty = definition.get("difficulty", difficulty)
	start_pos = definition.get("start", Vector2.ZERO)
	checkpoints = definition.get("checkpoints", [])
	reward = definition.get("reward", reward)
	best_time_bonus = definition.get("best_time_bonus", best_time_bonus)
	required_clues = definition.get("required_clues", 0)

func _ready() -> void:
	add_to_group("ski_race")
	z_index = 6
	_card = UI.card(self, UI.SKI)
	_build_3d_arches()

func _build_3d_arches() -> void:
	start_arch = preload("res://world/mountain_pass/MountainSkiStartArch.gd").new()
	start_arch.name = "StartArch3D"
	start_arch.position = start_pos
	var col := Color("78a95c")
	if difficulty == "AZUL": col = Color("5286ad")
	elif difficulty == "PRETA": col = Color("333b42")
	add_child(start_arch)
	start_arch.setup(col)

	if checkpoints.size() > 0:
		finish_arch = preload("res://world/mountain_pass/MountainSkiFinishArch.gd").new()
		finish_arch.name = "FinishArch3D"
		finish_arch.position = checkpoints[checkpoints.size() - 1]
		add_child(finish_arch)

func _draw() -> void:
	UI.beacon(self, start_pos, UI.SKI, _visual_clock)
	if _state == State.RUNNING and _next_index < checkpoints.size():
		var target: Vector2 = checkpoints[_next_index]
		for side in [-1.0, 1.0]:
			draw_polyline(PackedVector2Array([target + Vector2(side * 42, -14), target + Vector2(side * 35, 0), target + Vector2(side * 42, 14)]), Color(UI.SKI, 0.72), 1.5, true)

func _process(delta: float) -> void:
	_visual_clock += delta
	UI.animate(self, _card, _visual_clock)
	queue_redraw()
	if _state == State.RESULT:
		_countdown -= delta
		UI.present(self, _card, true, 2)
		if _countdown <= 0.0: _state = State.IDLE
		return
	if _state == State.IDLE:
		_idle_process()
		return
	if not is_instance_valid(_player) or _player.get("is_skiing") != true or _player.is_dead:
		_cancel("Você deixou os skis durante a prova")
		return
	UI.present(self, _card, true, 3)
	if _state == State.COUNTDOWN:
		_countdown -= delta
		_player.ski_controller.race_hold = true
		_card.title.text = "Prepare-se · " + race_name.capitalize()
		_card.value.text = str(maxi(1, ceili(_countdown)))
		_card.detail.text = "Aguarde no portão"
		_card.hint.text = "Cronômetro começa no JÁ"
		if _countdown <= 0.0:
			_player.ski_controller.race_hold = false
			_state = State.RUNNING
			_previous_position = _player.global_position
			UI.countdown(self, true)
		return
	_elapsed += delta
	var target := to_global(checkpoints[_next_index])
	var closest := Geometry2D.get_closest_point_to_segment(target, _previous_position, _player.global_position)
	if closest.distance_to(target) < 52.0:
		_next_index += 1
		UI.checkpoint(self)
		if _next_index >= checkpoints.size():
			_finish()
			return
	_previous_position = _player.global_position
	_card.title.text = "Descida · " + race_name.capitalize()
	_card.value.text = _format_time(_elapsed)
	_card.detail.text = "Portão %d / %d" % [_next_index + 1, checkpoints.size()]
	_card.hint.text = "%d m · mantenha a linha" % roundi(_player.global_position.distance_to(target) / 16.6)

func _idle_process() -> void:
	_refresh_best()
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	var near := is_instance_valid(player) and player.global_position.distance_to(to_global(start_pos)) < 145.0
	UI.present(self, _card, near)
	if not _card.layer.visible: return
	var schedule := preload("res://world/mountain_pass/MountainSkiSchedule.gd")
	var is_open := schedule.is_open(self)

	var clues := _clue_count(player)
	_card.title.text = "Ski · " + difficulty.to_lower()
	_card.value.text = race_name.capitalize()
	if not is_open:
		_card.detail.text = "Pistas fechadas para manutenção noturna"
		_card.hint.text = "Funcionamento: 08:00 às 18:00 (%s)" % schedule.get_time_formatted(self)
		return
	if required_clues > clues:
		_card.detail.text = "A rota permanece fechada · encontre as pistas da expedição"
		_card.hint.text = "Pistas encontradas: %d / %d" % [clues, required_clues]
		return
	_card.detail.text = "$%d + recorde $%d%s" % [reward, best_time_bonus, "\nRecorde: " + _format_time(_best_time) if _best_time > 0.0 else ""]
	if player.get("ski_equipment_ready") != true:
		_card.hint.text = "Alugue a roupa e retire os skis no Cume Branco"
		return
	if player.get("is_skiing") != true:
		_card.hint.text = "Coloque os skis para alinhar na largada"
		return
	var ready := player.global_position.distance_to(to_global(start_pos)) < 48.0 and player.velocity.length() < 70.0
	_card.hint.text = "[%s] Preparar largada" % UI.key(self, "interact") if ready else "Pare junto ao portão de largada"
	if ready and Input.is_action_just_pressed("interact"):
		_start(player)

func _start(player: CharacterBody2D) -> void:
	if not UI.available(self) or checkpoints.is_empty(): return
	add_to_group("active_motorsport")
	_player = player
	_state = State.COUNTDOWN
	_countdown = 3.0
	_elapsed = 0.0
	_next_index = 0
	player.velocity = Vector2.ZERO
	player.ski_controller.race_hold = true
	UI.cue(self)

func _finish() -> void:
	UI.cue(self, true)
	_refresh_best()
	var record := _best_time < 0.0 or _elapsed < _best_time
	if record: _best_time = _elapsed
	var campaign := get_node_or_null("/root/CampaignState")
	if campaign: campaign.record_race_time(race_id, _elapsed)
	var prize := reward + (best_time_bonus if record else 0)
	_player.money += prize
	if _player.has_method("report_ski_race_finished"):
		_player.report_ski_race_finished(record)
	_player._refresh_weapon_ui()
	_show_result("PROVA CONCLUÍDA", "%s\n+$%d%s" % [race_name.capitalize(), prize, " · Novo recorde!" if record else ""], "Recorde: " + _format_time(_best_time))
	var saves := get_node_or_null("/root/SaveManager")
	if saves: saves.request_autosave("Prova de ski concluída: " + race_name.capitalize())

func _cancel(reason: String) -> void:
	if is_instance_valid(_player) and is_instance_valid(_player.ski_controller):
		_player.ski_controller.race_hold = false
	_show_result("PROVA CANCELADA", reason, "Volte ao portão para tentar novamente")

func _show_result(title: String, detail: String, hint: String) -> void:
	remove_from_group("active_motorsport")
	_state = State.RESULT
	_countdown = 4.5
	if is_instance_valid(_player) and is_instance_valid(_player.ski_controller):
		_player.ski_controller.race_hold = false
	_player = null
	_card.title.text = title
	_card.value.text = _format_time(_elapsed)
	_card.detail.text = detail
	_card.hint.text = hint

func _refresh_best() -> void:
	var campaign := get_node_or_null("/root/CampaignState")
	if campaign: _best_time = campaign.get_race_best_time(race_id)

func _clue_count(player: Node) -> int:
	if not is_instance_valid(player): return 0
	var total := 0
	for id in player.collectibles_found:
		if String(id).begins_with("mountain_expedition_"): total += 1
	return total

func _format_time(value: float) -> String:
	var centiseconds := maxi(0, roundi(value * 100.0))
	return "%02d:%02d.%02d" % [centiseconds / 6000, (centiseconds / 100) % 60, centiseconds % 100]
