extends CanvasLayer

## Original V1 scene and theme, adapted to the single V2 session/save.
const STYLE = preload("res://ui/GameStyle.gd")
var world: Node
var settings: Control
var collection_button: Button
var exit_confirmation: ConfirmationDialog

func _ready() -> void:
	visible = false
	for panel in [%SlotsModal, %AchievementsModal, %CollectiblesModal]: panel.hide()
	%BtnResume.set_meta("primary_action", true)
	STYLE.apply(%RootControl)
	%BtnResume.pressed.connect(resume_game)
	%BtnSaveGame.pressed.connect(func():
		if world.session.save_game(true): resume_game())
	%BtnLoadGame.pressed.connect(func():
		resume_game()
		world.session.load_game())
	%BtnSettings.pressed.connect(open_settings)
	%BtnQuit.pressed.connect(func(): get_tree().quit())
	%BtnMainMenu.pressed.connect(_confirm_main_menu)
	exit_confirmation = ConfirmationDialog.new()
	exit_confirmation.title = "Voltar ao menu principal?"
	exit_confirmation.dialog_text = "O progresso desde o último salvamento pode ser perdido."
	exit_confirmation.ok_button_text = "Salvar e voltar"
	exit_confirmation.cancel_button_text = "Continuar jogando"
	exit_confirmation.add_button("Voltar sem salvar", false, "without_save")
	add_child(exit_confirmation)
	exit_confirmation.confirmed.connect(func():
		if world.session.save_game(): world.session.return_to_main_menu())
	exit_confirmation.custom_action.connect(func(action):
		if action == "without_save": world.session.return_to_main_menu())
	exit_confirmation.canceled.connect(func(): %BtnMainMenu.grab_focus())
	%BtnAchievements.pressed.connect(func(): _show_collection(true))
	%BtnCollectibles.pressed.connect(func(): _show_collection(false))
	%BtnCloseAchievements.pressed.connect(_close_collection)
	%BtnCloseCollectibles.pressed.connect(_close_collection)
	settings = preload("res://ui/SettingsMenu.tscn").instantiate()
	add_child(settings)
	settings.hide()
	settings.closed.connect(func(): %RootControl.show(); %BtnSettings.grab_focus())

func toggle() -> void:
	if visible:
		if settings.visible: settings.close()
		elif %AchievementsModal.visible or %CollectiblesModal.visible: _close_collection()
		else: resume_game()
	else: pause_game()

func pause_game() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%RootControl.show()
	get_tree().paused = true
	var has_session: bool = world.session != null and world.session.has_method("save_game")
	%BtnSaveGame.disabled = not has_session
	%BtnLoadGame.disabled = not has_session
	if has_session:
		var session = world.session
		var in_transit: bool = session.controller.travel_busy or session.vehicle_transition_busy or session.respawn_busy or (session.passenger_transport != null and session.passenger_transport.riding)
		var save_reason: String = session.save_block_reason()
		%BtnSaveGame.disabled = not save_reason.is_empty()
		%BtnLoadGame.disabled = in_transit or world.driving.occupied
		%BtnSaveGame.tooltip_text = save_reason if not save_reason.is_empty() else session.last_save_error
		%BtnLoadGame.tooltip_text = "Desembarque e conclua a transição antes de carregar." if in_transit or world.driving.occupied else ""
	%BtnAchievements.disabled = not has_session
	%BtnCollectibles.disabled = not has_session
	%BtnMainMenu.disabled = not has_session
	STYLE.trap_focus(%RootControl)
	%BtnResume.grab_focus()

func resume_game() -> void:
	if settings.visible: settings.close()
	_close_collection()
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func open_settings() -> void:
	%RootControl.hide()
	settings.show()
	settings.open()

func _confirm_main_menu() -> void:
	exit_confirmation.get_ok_button().disabled = %BtnSaveGame.disabled
	exit_confirmation.popup_centered()

func _close_collection() -> void:
	%AchievementsModal.hide()
	%CollectiblesModal.hide()
	%RootControl.get_node("CenterPanel").show()
	STYLE.trap_focus(%RootControl)
	if collection_button != null: collection_button.grab_focus()

func _show_collection(achievements: bool) -> void:
	var data: Dictionary = world.session.state.economy.snapshot()
	var found: Array = data.achievements if achievements else data.collectibles
	var catalog: Dictionary = preload("res://data/catalogs/AchievementCatalog.gd").ACHIEVEMENTS if achievements else preload("res://data/catalogs/CollectibleCatalog.gd").ENTRIES
	var rows: VBoxContainer = %AchievementsList if achievements else %CollectiblesList
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var ids: Array = catalog.keys() if achievements else []
	if not achievements:
		for item in preload("res://activities/ActivityDefinitions.gd").collectibles():
			ids.append(item.id)
	for id in found:
		if not ids.has(id): ids.append(id)
	for id in ids:
		var entry: Dictionary = catalog.get(id, {})
		var row := Label.new()
		row.text = str(entry.get("name", id)) + (" · Concluído" if found.has(id) else " · Pendente")
		if achievements and entry.has("desc"): row.text += "\n" + str(entry.desc)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(row)
	var progress: Label = %AchievementsProgressLabel if achievements else %CollectiblesProgressLabel
	progress.text = "%d / %d" % [found.size(), ids.size()]
	var panel: Control = %AchievementsModal if achievements else %CollectiblesModal
	collection_button = %BtnAchievements if achievements else %BtnCollectibles
	%RootControl.get_node("CenterPanel").hide()
	panel.show()
	STYLE.apply(panel)
	STYLE.trap_focus(panel)
