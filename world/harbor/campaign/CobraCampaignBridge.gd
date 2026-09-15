extends CanvasLayer
## Production adapter. Extends the existing fixed board through its public API;
## does not replace arrival, Maciota, localization or the player's controller.
const LEDGER := preload("res://world/harbor/campaign/CobraCampaignState.gd")
const RUNTIME := preload("res://world/harbor/campaign/CobraCampaignController.gd")
const SCHEDULE := preload("res://world/harbor/campaign/ChapterOneSchedule.gd")
var ledger: RefCounted
var runtime: Node2D
var world: Node2D
var player: Node2D
var garage: Node2D
var board: Node2D
var _clock := 0.0
var _voice_audio: AudioStreamPlayer
var _journal: PanelContainer
var _entries: RichTextLabel
var _objective_card: PanelContainer
var _objective_tag: Label
var _objective: Label
var _journal_button: Button
var _rest_button: Button
var _cancel_race_button: Button
var _rest_reason: Label
var _close_button: Button
var _dialog: PanelContainer
var _dialog_speaker: Label
var _dialog_text: Label
var _continue: Button
var _messages: Array[Array] = []
var _locked := false
var _old_disabled := false
var _old_dialogue := false
var _resting := false
var _fade: ColorRect
var _marker: Node2D
var _shade: ColorRect
var _locked_vehicle: Node2D
var _vehicle_physics_enabled := false
var _previous_paused := false
var _time_transition := false
var _time_caption: Label

var navigation_target := Vector2.ZERO

func configure(scene: Node2D) -> void:
	add_to_group("medical_campaign_clock")
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = scene
	player = world.get_node("Player")
	garage = world.get_node("Interiors").garage_interior
	board = garage.mission_board
	ledger = LEDGER.new()
	ledger.bind(get_node("/root/CampaignState"))
	var discovery := preload("res://world/harbor/campaign/CobraDiscovery.gd").new()
	discovery.name = "CobraDiscovery"
	add_child(discovery)
	discovery.configure(world, ledger)
	runtime = RUNTIME.new()
	runtime.name = "CobraCampaignController"
	world.add_child(runtime)
	runtime.configure(player, ledger, world.get_node("CobraTerritory"))
	runtime.dialogue.connect(_message)
	runtime.changed.connect(_refresh)
	garage.mission_selected.connect(_selected)
	layer = 35
	_build_ui()
	world.campaign_controller.delivery_finished.connect(func(): _message("Maciota", runtime.get_brother_clue("primeiro_giro")))
	world.campaign_controller.objective_changed.connect(func(_text, _target): call_deferred("_refresh"))
	var interiors: Node = world.get_node_or_null("Interiors")
	if is_instance_valid(interiors):
		for prop in ["clinic_interior", "police_interior", "workshop_interior", "fire_station_interior", "garage_interior"]:
			var it: Node = interiors.get(prop) as Node
			if is_instance_valid(it) and it.has_signal("modal_opened"):
				it.modal_opened.connect(func() -> void: _refresh())
				it.modal_closed.connect(func() -> void: _refresh())
	# HarborArrivalMission also reacts to language_changed by rewriting the
	# board with its own single-row version; connecting here too (after it,
	# so this handler runs second on the same signal) re-applies the seven
	# fixed rows in the SAME frame instead of waiting up to 0.3s for the
	# next periodic _refresh() tick.
	var settings := get_node_or_null("/root/SettingsManager")
	if settings:
		var on_language_changed := _refresh.unbind(1)
		if not settings.language_changed.is_connected(on_language_changed):
			settings.language_changed.connect(on_language_changed)
	_refresh()

func _text(pt: String, en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt

func _is_any_interior_modal_open() -> bool:
	var interiors: Node = world.get_node_or_null("Interiors") if is_instance_valid(world) else null
	if not is_instance_valid(interiors):
		return false
	for prop in ["clinic_interior", "police_interior", "garage_interior", "fire_station_interior", "workshop_interior", "morgue_interior", "ammunation_interior"]:
		var interior: Node = interiors.get(prop) as Node
		if is_instance_valid(interior):
			for dialog_name in ["triage_dialog", "terminal_dialog", "diagnostic_dialog", "alarm_dialog", "bench_dialog", "registry_dialog", "counter_dialog"]:
				var d: Control = interior.get(dialog_name) as Control
				if is_instance_valid(d) and d.visible:
					return true
	return false

func _exit_tree() -> void:
	if _locked:
		get_tree().paused = _previous_paused
		if is_instance_valid(_locked_vehicle):
			_locked_vehicle.set_physics_process(_vehicle_physics_enabled)

func _process(delta: float) -> void:
	if not is_instance_valid(player) or ledger == null:
		return
	if not _messages.is_empty() and not _locked and not get_tree().paused and not _recovery_blocks_message():
		_show_pending_message()
	if not get_tree().paused and not _locked and player.get("is_dead") != true and player.get("is_control_disabled") != true and _onboarding_done():
		ledger.tick(delta)
		get_node("/root/NPCMedicalCare").advance_days(delta / LEDGER.DAY_SECONDS)
		# This campaign's day is ten playable minutes. Arrival weather remains
		# untouched; resting uses the same clock rather than the wall clock.
		world.weather.time_of_day = fposmod(0.35 + float(ledger.data.day_elapsed) / LEDGER.DAY_SECONDS, 1.0)
	_clock += delta
	if _clock >= 0.3:
		_clock = 0.0
		_refresh()

func _onboarding_done() -> bool:
	return get_node("/root/CampaignState").has_campaign_flag(&"harbor_delivery_complete")

func _refresh() -> void:
	if not is_inside_tree() or ledger == null or not is_instance_valid(_objective):
		return
	ledger.sync_legacy()
	_refresh_board()
	var enabled := _onboarding_done()
	_journal_button.visible = false
	_objective.visible = enabled and not _locked
	if not enabled:
		if is_instance_valid(_objective_card):
			_objective_card.hide()
		return
	if world.campaign_controller.has_method("set_objective_card_visible"):
		world.campaign_controller.set_objective_card_visible(false)
	elif is_instance_valid(world.campaign_controller.get("_obj_card")):
		(world.campaign_controller.get("_obj_card") as Control).hide()
	world.campaign_controller._objective_label.hide()
	var status: Dictionary = runtime.get_status()
	var description: String = runtime.get_objective()
	if str(ledger.data.active_id).is_empty():
		description = _text("O próximo serviço já está disponível no quadro do Maciota.", "The next job is ready on Maciota's board.")
		if bool(ledger.data.defeated):
			description = _text("Os Cobras perderam o controle de Ashbend. A pista sobre seu irmão continua.", "The Cobras have lost control of Ashbend. The lead on your brother remains.")
	var target: Vector2 = status.get("target", Vector2.ZERO)
	if target != Vector2.ZERO:
		if player.global_position.distance_to(garage.global_position) < 900.0:
			target = garage.exit_door.global_position
		description += " · %.0f m" % [player.global_position.distance_to(target) / 16.6]
	if target == Vector2.ZERO and not bool(ledger.data.defeated):
		target = garage.mission_board.global_position if player.global_position.distance_to(garage.global_position)<900 else world.get_node("District/Garage/Entrance").global_position
	navigation_target = target
	_objective.text = _text("DIA ", "DAY ") + str(ledger.data.day) + "  ·  " + description
	if is_instance_valid(_objective_tag):
		_objective_tag.text = _text("🎯 OBJETIVO ATUAL", "🎯 CURRENT OBJECTIVE")
	if is_instance_valid(_objective_card):
		var board_open: bool = bool(board.get("is_ui_open")) if is_instance_valid(board) else false
		var maciota: Node = (garage.get("jager_npc") if is_instance_valid(garage) else null) as Node
		var maciota_talking: bool = bool(maciota.get("is_talking")) if is_instance_valid(maciota) else false
		var terminal_open: bool = _is_any_interior_modal_open()
		var modal_open: bool = _journal.visible or _dialog.visible or board_open or maciota_talking or terminal_open or _locked or player.get("is_in_dialogue") == true
		_objective_card.visible = not str(ledger.data.active_id).is_empty() and not modal_open and player.get("is_dead") != true and player.get("is_arrested") != true
		_journal_button.visible = false
	_update_marker(target)
	_journal_button.text = _text("Diário [J]", "Journal [J]")
	_rest_button.text = _text("Descansar até amanhã · opcional", "Rest until tomorrow · optional")
	_close_button.text = _text("Voltar ao jogo [J / Esc]", "Back to game [J / Esc]")
	_rest_button.disabled = not can_rest()
	_cancel_race_button.visible = runtime.active_id == "cobra_race"
	_cancel_race_button.text = _text("Cancelar prova · tentar novamente sem custo", "Cancel trial · retry at no cost")
	var reason := _rest_block_reason()
	_rest_reason.text = reason
	_rest_reason.visible = not reason.is_empty()
	if _journal.visible:
		var lines := "[font_size=26]" + _text("HARBOR / O PRIMEIRO CAPÍTULO", "HARBOR / CHAPTER ONE") + "[/font_size]\n\n"
		lines += "[color=#ff914d]" + _text("AGORA", "NOW") + "[/color]\n" + description + "\n\n"
		lines += "[color=#ff914d]" + _text("SEUS SERVIÇOS", "YOUR JOBS") + "[/color]\n\n"
		var ordered: Array = board.campaign_missions.duplicate()
		ordered.sort_custom(func(a,b): return (2 if a.completed else (0 if a.enabled else 1)) < (2 if b.completed else (0 if b.enabled else 1)))
		for row in ordered:
			var title := String(row.title)
			var status_label := _text("Concluído", "Completed") if row.completed else (_text("Disponível", "Available") if row.enabled else _text("Bloqueado", "Locked"))
			lines += ("[s]" + title + "[/s]" if bool(row.completed) else title) + " · " + status_label + "\n"
			if bool(row.completed):
				var clue: String = runtime.get_brother_clue(str(row.id))
				if not clue.is_empty():
					lines += "[color=#e8b44f]" + clue + "[/color]\n"
			var requirement := String(row.get("requirement", ""))
			if not requirement.is_empty(): lines += "[color=#b8b4a6]" + requirement + "[/color]\n"
			lines += "\n"
		lines += _text("Moradores: ", "Residents: ") + str(ledger.data.civilian_reputation)
		lines += _text("  ·  Acesso Cobra: ", "  ·  Cobra access: ") + str(ledger.data.cobra_access)
		if ledger.data.secret_owned.has("ashbend_coupe"):
			lines += _text("\nDescoberta: Ashbend Copper Coupe recuperado. Pintura e estado ficam no save.", "\nDiscovery: Ashbend Copper Coupe recovered. Paint and condition persist in your save.")
		if bool(ledger.data.optional_flags.get("neighbor_route", false)):
			lines += _text("\nAliada: uma moradora ajudará a distrair um reforço no confronto final.", "\nAlly: a resident will help distract one reinforcement in the final confrontation.")
		lines += _text("\n\nPara descansar: volte à garagem, perto do Maciota, sem missão ou perseguição ativa.", "\n\nTo rest: return near Maciota in the garage, with no active mission or pursuit.")
		_entries.text = lines

func _refresh_board() -> void:
	var campaign := get_node("/root/CampaignState")
	var complete: bool = campaign.has_campaign_flag(&"harbor_delivery_complete")
	var started: bool = campaign.has_campaign_flag(&"harbor_delivery_started")
	var rows: Array[Dictionary] = [{"id": "arrival", "title": _text("Cheguei", "I've Arrived"), "description": _text("Rodoviária, telefone e Maciota.", "Terminal, phone and Maciota."), "enabled": false, "completed": campaign.has_campaign_flag(&"harbor_maciota_met"), "requirement": ""},
		{"id": "primeiro_giro", "title": tr("MISSION_PRIMEIRO_GIRO_TITLE"), "description": tr("MISSION_PRIMEIRO_GIRO_DESC"), "enabled": not started, "completed": complete, "requirement": tr("MISSION_STATUS_IN_PROGRESS") if started and not complete else ""}]
	for index in LEDGER.MISSION_IDS.size():
		var id: String = LEDGER.MISSION_IDS[index]
		var state: Dictionary = ledger.get_status(id)
		var requirement := ""
		match str(state.reason):
			"prerequisite": requirement = _text("Conclua o serviço anterior.", "Finish the previous job.")
			"active": requirement = _text("Há uma missão em andamento.", "A mission is already in progress.")
		var titles = LEDGER.TITLES_EN if TranslationServer.get_locale().begins_with("en") else LEDGER.TITLES_PT
		var detail := SCHEDULE.description(id, TranslationServer.get_locale().begins_with("en"))
		if detail.is_empty(): detail = runtime._briefing(id)
		rows.append({"id": id, "title": titles[index], "description": detail + _text(" · Recompensa $%d", " · Reward $%d") % LEDGER.REWARDS[index], "enabled": bool(state.available), "completed": bool(ledger.data.completed.get(id, false)), "requirement": requirement})
	rows[0].title = _text("Atrás do irmão", "Looking for My Brother")
	rows[0].description = _text("Delegacia, encontro no Neco e passeio até a garagem.", "Police station, meeting at Neco's and a ride to the garage.")
	rows[1].description = SCHEDULE.description("primeiro_giro", TranslationServer.get_locale().begins_with("en"))
	if board.campaign_missions != rows:
		garage.configure_mission_board(rows)

func _selected(id: String) -> void:
	if not LEDGER.MISSION_IDS.has(id) or player.get("is_dead") == true or not player.visible:
		return
	if player.global_position.distance_to(board.global_position) > 80.0:
		return
	if not bool(ledger.get_status(id).available): return
	if not prepare_story_time(id): return
	runtime.start_mission(id)
	_refresh()

func story_start_block_reason(allow_driver: bool = false) -> String:
	if _resting or _time_transition or _locked or get_tree().paused:
		return _text("Termine a conversa antes de iniciar o serviço.", "Finish the conversation before starting the job.")
	var driving: bool = allow_driver and is_instance_valid(runtime) and runtime._subject() != player and runtime._subject().get("is_driven_by_player") == true
	if player.get("is_dead") == true or player.get("is_arrested") == true or player.get("is_recovering") == true or (not player.visible and not driving):
		return _text("Recupere-se antes de iniciar o serviço.", "Recover before starting the job.")
	var wanted := get_node_or_null("/root/WantedManager")
	if (wanted and int(wanted.current_stars) > 0) or world.get_node("CobraTerritory").state == "combat":
		return _text("Despiste a polícia e saia do confronto antes de combinar o serviço.", "Lose the police and leave combat before arranging the job.")
	for manager in get_tree().get_nodes_in_group("mission_manager"):
		if str(manager.get("active_mission_id")) != "" and manager.get("current_state") in [1, 2, 3]:
			return _text("Conclua o outro serviço primeiro.", "Finish the other job first.")
	return ""

func prepare_story_time(id: String) -> bool:
	if not str(ledger.data.active_id).is_empty(): return false
	var reason := story_start_block_reason()
	if not reason.is_empty():
		if not _locked: _message("Maciota", reason)
		return false
	_advance_story_clock(id)
	return true

func ensure_race_night() -> bool:
	if str(ledger.data.active_id) != "cobra_race": return false
	var reason := story_start_block_reason(true)
	if not reason.is_empty():
		if not _locked and not _time_transition: _message("Ferrugem", reason)
		return false
	_advance_story_clock("cobra_race")
	return true

func _advance_story_clock(id: String) -> void:
	var current: float = world.weather.time_of_day
	var skipped := SCHEDULE.forward_days(current, id)
	if skipped <= 0.0: return
	# Align both clocks: the regular bridge tick must not undo this jump.
	ledger.data.day_elapsed = fposmod(current - 0.35, 1.0) * LEDGER.DAY_SECONDS
	ledger.tick(skipped * LEDGER.DAY_SECONDS)
	get_node("/root/NPCMedicalCare").advance_days(skipped)
	get_node("/root/CampaignState").advance_bank_days(skipped)
	world.weather.time_of_day = fposmod(current + skipped, 1.0)
	world.weather._update_lighting()
	_time_transition = true
	_fade.color.a = 1.0
	_fade.show()
	_time_caption.text = _text("MAIS TARDE", "LATER") + " · %02d:00" % int(SCHEDULE.HOURS[id])
	_time_caption.show()
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(0.45)
	tween.tween_property(_fade, "color:a", 0.0, 0.35)
	tween.tween_callback(func():
		_fade.hide()
		_time_caption.hide()
		_time_transition = false
	)

func can_rest() -> bool:
	if ledger == null or not _onboarding_done() or _resting or not str(ledger.data.active_id).is_empty():
		return false
	if not _locked and (player.get("is_control_disabled") == true or player.get("is_in_dialogue") == true):
		return false
	if player.get("is_dead") == true or not player.visible or player.global_position.distance_to(garage.jager_npc.global_position) > 130.0:
		return false
	var wanted := get_node_or_null("/root/WantedManager")
	return (wanted == null or int(wanted.current_stars) == 0) and world.get_node("CobraTerritory").state != "combat"

## Presentation-only companion to can_rest(): explains WHY the rest button is
## disabled instead of leaving an unexplained grey button. Never used to gate
## the actual rest action — can_rest() above (unchanged) still owns that rule.
## Only reachable states are covered (the journal/rest button cannot be shown
## at all before onboarding, mid-rest, or with no ledger).
func _rest_block_reason() -> String:
	if can_rest() or ledger == null or not _onboarding_done() or _resting:
		return ""
	if not str(ledger.data.active_id).is_empty():
		return _text("Você tem um serviço em andamento.", "You have an active job.")
	if not _locked and (player.get("is_control_disabled") == true or player.get("is_in_dialogue") == true):
		return _text("Termine a conversa ou a interface aberta primeiro.", "Finish the current conversation or open interface first.")
	if player.get("is_dead") == true or not player.visible:
		return _text("Você precisa estar de pé e em jogo.", "You need to be up and in play.")
	if player.global_position.distance_to(garage.jager_npc.global_position) > 130.0:
		return _text("Aproxime-se do Maciota na garagem.", "Get closer to Maciota in the garage.")
	var wanted := get_node_or_null("/root/WantedManager")
	if wanted != null and int(wanted.current_stars) > 0:
		return _text("Não dá para descansar durante uma perseguição.", "You can't rest during a police pursuit.")
	if world.get_node("CobraTerritory").state == "combat":
		return _text("Não dá para descansar durante um confronto.", "You can't rest during a fight.")
	return ""

func rest() -> bool:
	var skipped_days := 1.0 - float(ledger.data.day_elapsed) / LEDGER.DAY_SECONDS
	if not can_rest() or not ledger.rest_until_next_day(false):
		return false
	get_node("/root/NPCMedicalCare").advance_days(skipped_days)
	get_node("/root/CampaignState").advance_bank_days(skipped_days)
	_resting = true
	_journal.hide()
	_lock()
	_fade.show()
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.35)
	tween.tween_callback(func():
		world.weather.time_of_day = 0.35
		world.weather.set_biome(world.weather.current_biome)
	)
	tween.tween_interval(0.4)
	tween.tween_property(_fade, "color:a", 0.0, 0.45)
	tween.tween_callback(func():
		_fade.hide()
		_resting = false
		_unlock()
		_refresh()
	)
	return true

func _input(event: InputEvent) -> void:
	if not is_instance_valid(player) or not _onboarding_done() or (get_tree().paused and not _locked):
		return
	if event.is_pressed() and not event.is_echo():
		if _dialog.visible and event.is_action_pressed("ui_accept"):
			_next_message()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("journal") or (event.is_action_pressed("ui_cancel") and _journal.visible):
			_toggle_journal()
			get_viewport().set_input_as_handled()
		elif not _locked and event.is_action_pressed("radio_next") and runtime.active_id == "cobra_race":
			if runtime.interact():
				get_viewport().set_input_as_handled()
	# E belongs to vehicle exit in PlayerCar's physics polling, independent of
	# handled UI events. The race uses R so starting cannot eject its driver.
	if not _locked and runtime.active_id != "cobra_race" and player.visible and event.is_action_pressed("interact") and runtime.interact():
		get_viewport().set_input_as_handled()

func _toggle_journal() -> void:
	if _dialog.visible or _resting:
		return
	if _journal.visible:
		_journal.hide()
		get_viewport().gui_release_focus()
		_unlock()
	elif player.get("is_control_disabled") != true and (player.visible or runtime._subject() != player):
		_lock()
		_journal.show()
		_refresh()
		_close_button.grab_focus()
	_refresh()

func _cancel_race() -> void:
	if runtime.active_id != "cobra_race" or not _journal.visible: return
	_journal.hide()
	get_viewport().gui_release_focus()
	_unlock()
	runtime.fail_mission(_text("Prova cancelada. Aceite novamente no quadro, sem custo.", "Trial cancelled. Accept it again at the board, at no cost."))
	_refresh()

func _lock() -> void:
	if _locked:
		return
	_old_disabled = bool(player.get("is_control_disabled"))
	_old_dialogue = bool(player.get("is_in_dialogue"))
	_previous_paused = get_tree().paused
	_locked = true
	player.set_dialogue_active(true)
	# A readable modal must also stop already-fired projectiles, not merely
	# prevent the next shot. This layer alone continues handling its own UI.
	get_tree().paused = true
	_shade.show()
	_objective.hide()
	if is_instance_valid(_objective_card):
		_objective_card.hide()
	_journal_button.hide()
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if vehicle is Node2D and vehicle.get("is_driven_by_player") == true:
			_locked_vehicle = vehicle
			_vehicle_physics_enabled = vehicle.is_physics_processing()
			vehicle.set_physics_process(false)
			break

func _unlock() -> void:
	if not _locked or not is_instance_valid(player):
		return
	player.set("is_control_disabled", _old_disabled)
	player.set("is_in_dialogue", _old_dialogue)
	if is_instance_valid(_locked_vehicle):
		_locked_vehicle.set_physics_process(_vehicle_physics_enabled)
	_locked_vehicle = null
	_locked = false
	get_tree().paused = _previous_paused
	_shade.hide()
	_objective.show()
	if is_instance_valid(_objective_card):
		_objective_card.hide()
	_refresh()

func _message(speaker: String, text: String) -> void:
	_messages.append([speaker, text])
	if _messages.size() == 1:
		# Death/arrest recovery must finish before a modal takes ownership of
		# pause and controls. Otherwise respawn runs inside that modal's lock.
		if _recovery_blocks_message(): return
		_show_pending_message()

func _recovery_blocks_message() -> bool:
	return player.get("is_dead") == true or player.get("is_arrested") == true or player.get("is_recovering") == true or (not _locked and player.get("is_control_disabled") == true)

func _show_pending_message() -> void:
	_lock()
	if is_instance_valid(_dialog_speaker):
		_dialog_speaker.text = str(_messages[0][0]).to_upper()
	_dialog_text.text = str(_messages[0][1])
	_play_recorded_voice(str(_messages[0][0]), str(_messages[0][1]))
	_continue.text = _text("Continuar [Enter / Espaço]", "Continue [Enter / Space]")
	_dialog.show()
	_continue.grab_focus()

func _next_message() -> void:
	if _time_transition: return
	var personal_car := get_tree().get_first_node_in_group("personal_car_manager")
	if personal_car != null and personal_car.get("delivery_in_progress") == true:
		return
	if _messages.is_empty():
		return
	_messages.pop_front()
	if _messages.is_empty():
		_dialog.hide()
		if is_instance_valid(_voice_audio): _voice_audio.stop()
		get_viewport().gui_release_focus()
		_unlock()
	else:
		if is_instance_valid(_dialog_speaker):
			_dialog_speaker.text = str(_messages[0][0]).to_upper()
		_dialog_text.text = str(_messages[0][1])
		_play_recorded_voice(str(_messages[0][0]),str(_messages[0][1]))

func _play_recorded_voice(speaker: String, text: String) -> void:
	if not is_instance_valid(_voice_audio):
		_voice_audio = AudioStreamPlayer.new()
		_voice_audio.volume_db = -8.0
		add_child(_voice_audio)
		get_node("/root/MissionVoiceMixer").track(_voice_audio)
	_voice_audio.stop()
	_voice_audio.stream = preload("res://ExpressiveVoice.gd")._recording(text,speaker.to_lower())
	if _voice_audio.stream != null: _voice_audio.play()

func _build_ui() -> void:
	# Faixa discreta de objetivo; sem cabeçalho ou moldura de notificação.
	_objective_card = PanelContainer.new()
	_objective_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_objective_card.offset_left = -344
	_objective_card.offset_right = -24
	_objective_card.offset_top = 180
	_objective_card.offset_bottom = 180
	_objective_card.custom_minimum_size = Vector2(320, 0)
	_objective_card.set_meta("preserve_panel_style", true)
	_objective_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_card.add_theme_stylebox_override("panel", preload("res://ui/GameStyle.gd").objective_strip())
	add_child(_objective_card)
	world.get_node("HUD").place_objective_card(_objective_card)
	_objective_card.hide()

	var obj_vbox := VBoxContainer.new()
	obj_vbox.add_theme_constant_override("separation", 2)
	_objective_card.add_child(obj_vbox)

	_objective_tag = Label.new()
	_objective_tag.text = _text("🎯 OBJETIVO ATUAL", "🎯 CURRENT OBJECTIVE")
	_objective_tag.add_theme_font_size_override("font_size", 12)
	_objective_tag.add_theme_color_override("font_color", Color("#e8b44f"))
	_objective_tag.hide()
	obj_vbox.add_child(_objective_tag)

	_objective = Label.new()
	_objective.custom_minimum_size = Vector2(298, 0)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.add_theme_font_size_override("font_size", 15)
	_objective.add_theme_color_override("font_color", Color.WHITE)
	_objective.add_theme_color_override("font_shadow_color", Color.BLACK)
	_objective.add_theme_constant_override("shadow_offset_x", 1)
	_objective.add_theme_constant_override("shadow_offset_y", 1)
	obj_vbox.add_child(_objective)

	_journal_button = Button.new()
	_journal_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_journal_button.offset_left = -205
	_journal_button.offset_right = -25
	_journal_button.offset_top = 150
	_journal_button.offset_bottom = 188
	_journal_button.add_theme_font_size_override("font_size", 14)
	_journal_button.pressed.connect(_toggle_journal)
	add_child(_journal_button)
	_journal_button.hide()

	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.015, 0.02, 0.025, 0.65)
	add_child(_shade)
	_shade.hide()

	# Modal centralizado do Diário na área útil
	_journal = _panel(Vector2(760, 560))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_journal.add_child(column)

	_entries = RichTextLabel.new()
	_entries.bbcode_enabled = true
	_entries.custom_minimum_size = Vector2(700, 340)
	_entries.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_entries)

	_rest_button = Button.new()
	_rest_button.custom_minimum_size = Vector2(0, 38)
	_rest_button.add_theme_font_size_override("font_size", 15)
	_rest_button.pressed.connect(rest)
	column.add_child(_rest_button)

	_rest_reason = Label.new()
	_rest_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rest_reason.add_theme_font_size_override("font_size", 13)
	_rest_reason.add_theme_color_override("font_color", Color("#e8b44f"))
	_rest_reason.visible = false
	column.add_child(_rest_reason)
	_cancel_race_button = Button.new()
	_cancel_race_button.custom_minimum_size = Vector2(0, 38)
	_cancel_race_button.add_theme_font_size_override("font_size", 14)
	_cancel_race_button.pressed.connect(_cancel_race)
	column.add_child(_cancel_race_button)

	_close_button = Button.new()
	_close_button.custom_minimum_size = Vector2(0, 44)
	_close_button.set_meta("primary_action",true)
	_close_button.add_theme_font_size_override("font_size", 14)
	_close_button.pressed.connect(_toggle_journal)
	column.add_child(_close_button)

	# Diálogo narrativo em faixa inferior centralizada
	_dialog = PanelContainer.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_dialog.offset_left = 140
	_dialog.offset_right = -140
	_dialog.offset_top = -225
	_dialog.offset_bottom = -28
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	var dialog_style := StyleBoxFlat.new()
	dialog_style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	dialog_style.border_color = Color("a67b49")
	dialog_style.set_border_width_all(2)
	dialog_style.set_corner_radius_all(8)
	dialog_style.content_margin_left = 24
	dialog_style.content_margin_right = 24
	dialog_style.content_margin_top = 16
	dialog_style.content_margin_bottom = 16
	dialog_style.shadow_color = Color(0, 0, 0, 0.6)
	dialog_style.shadow_size = 12
	_dialog.add_theme_stylebox_override("panel", dialog_style)
	add_child(_dialog)
	_dialog.hide()

	var dialog_column := VBoxContainer.new()
	dialog_column.add_theme_constant_override("separation", 8)
	_dialog.add_child(dialog_column)

	_dialog_speaker = Label.new()
	_dialog_speaker.add_theme_font_size_override("font_size", 16)
	_dialog_speaker.add_theme_color_override("font_color", Color("#e8b44f"))
	dialog_column.add_child(_dialog_speaker)

	_dialog_text = Label.new()
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size = Vector2(0, 75)
	_dialog_text.add_theme_font_size_override("font_size", 23)
	_dialog_text.add_theme_color_override("font_color", Color("#ffffff"))
	dialog_column.add_child(_dialog_text)

	_continue = Button.new()
	_continue.custom_minimum_size = Vector2(220, 36)
	_continue.size_flags_horizontal = Control.SIZE_SHRINK_END
	_continue.add_theme_font_size_override("font_size", 14)
	_continue.pressed.connect(_next_message)
	dialog_column.add_child(_continue)

	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.02, 0.025, 0.03, 0)
	add_child(_fade)
	_fade.hide()
	_time_caption = Label.new()
	_time_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_time_caption.offset_left = -250
	_time_caption.offset_right = 250
	_time_caption.offset_top = -28
	_time_caption.offset_bottom = 28
	_time_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_caption.add_theme_font_size_override("font_size", 30)
	_fade.add_child(_time_caption)
	_time_caption.hide()

	_marker = Node2D.new()
	_marker.name = "CobraObjectiveMarker"
	_marker.z_index = 20
	var diamond := Polygon2D.new()
	diamond.name = "ObjectiveShape"
	diamond.polygon = PackedVector2Array([Vector2(0,-24),Vector2(13,-11),Vector2(0,2),Vector2(-13,-11)])
	diamond.color = Color(0.85, 0.64, 0.30, 0.85)
	_marker.add_child(diamond)
	world.add_child(_marker)

func _panel(size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -size.x / 2
	panel.offset_right = size.x / 2
	panel.offset_top = -size.y / 2
	panel.offset_bottom = size.y / 2
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172126f5")
	style.border_color = Color("a67b49")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 14
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	panel.hide()
	return panel

func _update_marker(target: Vector2) -> void:
	if is_instance_valid(_marker):
		_marker.visible = target != Vector2.ZERO
		_marker.global_position = target
		var shape := _marker.get_node("ObjectiveShape") as Polygon2D
		var contact_mission: bool = is_instance_valid(runtime) and runtime.active_id == "cobra_contact"
		if contact_mission:
			# Small downward arrow above Ferrugem, leaving his face unobstructed.
			shape.polygon = PackedVector2Array([Vector2(-2,-34),Vector2(2,-34),Vector2(2,-29),Vector2(5,-29),Vector2(0,-24),Vector2(-5,-29),Vector2(-2,-29)])
			if is_instance_valid(runtime._contact):
				_marker.global_position = runtime._contact.global_position
		else:
			shape.polygon = PackedVector2Array([Vector2(0,-24),Vector2(13,-11),Vector2(0,2),Vector2(-13,-11)])
