extends CanvasLayer

## Original V1 scene and theme, adapted to the single V2 session/save.
const STYLE = preload("res://ui/GameStyle.gd")
const COLLECTION = preload("res://ui/CollectionPresentation.gd")
var world: Node
var settings: Control
var collection_button: Button
var exit_confirmation: ConfirmationDialog
var developer_panel: CanvasLayer
var guide: Control
var guide_button: Button

func _ready() -> void:
	visible = false
	for panel in [%SlotsModal, %AchievementsModal, %CollectiblesModal]: panel.hide()
	COLLECTION.setup(%AchievementsModal,true,_show_collection)
	COLLECTION.setup(%CollectiblesModal,false,_show_collection)
	%BtnResume.set_meta("primary_action", true)
	developer_panel = preload("res://ui/DeveloperPanel.gd").new()
	developer_panel.world = world
	developer_panel.pause_menu = self
	add_child(developer_panel)
	var developer_button := Button.new()
	developer_button.text = "Desenvolvedor · F10"
	%BtnSettings.get_parent().add_child(developer_button)
	%BtnSettings.get_parent().move_child(developer_button, %BtnSettings.get_index()+1)
	developer_button.pressed.connect(developer_panel.open_panel)
	STYLE.apply(%RootControl)
	guide = preload("res://ui/GameGuide.gd").new()
	add_child(guide)
	guide_button = Button.new()
	guide_button.text = "Guia do jogo"
	%BtnSettings.get_parent().add_child(guide_button)
	%BtnSettings.get_parent().move_child(guide_button, %BtnSettings.get_index())
	STYLE.apply(guide_button)
	guide_button.pressed.connect(func(): %RootControl.hide(); guide.open())
	guide.closed.connect(func(): %RootControl.show(); STYLE.trap_focus(%RootControl, false); guide_button.grab_focus())
	preload("res://ui/HarborMenuPresentation.gd").pause(self, developer_button, guide_button)
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
	if developer_panel.visible:
		developer_panel.close_panel(false)
		return
	if visible:
		if guide.visible: guide.close()
		elif settings.visible: settings.close()
		elif %AchievementsModal.visible or %CollectiblesModal.visible: _close_collection()
		else: resume_game()
	else: pause_game()

func pause_game() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%RootControl.show()
	_set_drag_overlay(true)
	get_tree().paused = true
	var has_session: bool = world.session != null and world.session.has_method("save_game")
	%BtnSaveGame.disabled = not has_session
	%BtnLoadGame.disabled = not has_session
	if has_session:
		var session = world.session
		var in_transit: bool = session.controller.travel_busy or session.vehicle_transition_busy or session.respawn_busy or (session.passenger_transport != null and session.passenger_transport.riding) or (session.get("railway") != null and session.railway.busy())
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
	if guide.visible: guide.close()
	if settings.visible: settings.close()
	_close_collection()
	visible = false
	get_tree().paused = false
	_set_drag_overlay(false)
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN

func _set_drag_overlay(paused: bool) -> void:
	if world.session==null: return
	var desert = world.session.get("desert")
	if desert!=null and is_instance_valid(desert.drag): desert.drag.set_pause_overlay(paused)

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
	%AchievementsModal.hide()
	%CollectiblesModal.hide()
	var data: Dictionary = world.session.state.economy.snapshot()
	var values: Dictionary = COLLECTION.stats(world.session) if achievements else {}
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
		rows.add_child(COLLECTION.row(str(id),entry,found.has(id),achievements,values))
	var progress: Label = %AchievementsProgressLabel if achievements else %CollectiblesProgressLabel
	progress.text = "%d / %d\n%s" % [found.size(), ids.size(),tr("desbloqueadas") if achievements else tr("encontrados")]
	var panel: Control = %AchievementsModal if achievements else %CollectiblesModal
	collection_button = %BtnAchievements if achievements else %BtnCollectibles
	%RootControl.get_node("CenterPanel").hide()
	panel.show()
	panel.get_node("Margin/VBox/Scroll").scroll_vertical = 0
	STYLE.apply(panel)
	COLLECTION.finish_style(panel,achievements)
	STYLE.trap_focus(panel)
	panel.find_child("AchievementsTab" if achievements else "CollectiblesTab",true,false).grab_focus()
