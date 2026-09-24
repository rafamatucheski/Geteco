extends CanvasLayer

## Menu de Pausa In-Game
## Controla congelamento total da simulação (get_tree().paused = true) evitando gasto de CPU.
## Permite salvar em slots manuais, carregar, configurar e voltar ao menu inicial.

const SAVE_TEXT = preload("res://ui/SavePresentation.gd")
const STYLE = preload("res://ui/GameStyle.gd")

const SETTINGS_SCENE: PackedScene = preload("res://ui/SettingsMenu.tscn")
const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"
const SCENE_ROUTE = preload("res://world/harbor/HarborSceneRoute.gd")
const MenuAudio = preload("res://ui/MenuAudio.gd")
const ACHIEVEMENT_CATALOG := preload("res://economy/AchievementCatalog.gd")
const COLLECTIBLE_CATALOG := preload("res://economy/CollectibleCatalog.gd")

@onready var root_control: Control = %RootControl
@onready var btn_resume: Button = %BtnResume
@onready var btn_save_game: Button = %BtnSaveGame
@onready var btn_load_game: Button = %BtnLoadGame
@onready var btn_achievements: Button = %BtnAchievements
@onready var btn_collectibles: Button = %BtnCollectibles
@onready var btn_settings: Button = %BtnSettings
@onready var btn_main_menu: Button = %BtnMainMenu
@onready var btn_quit: Button = %BtnQuit

@onready var slots_modal: Control = %SlotsModal
@onready var slots_modal_title: Label = %SlotsModalTitle
@onready var slots_list: VBoxContainer = %SlotsList
@onready var slots_status_label: Label = %SlotsStatusLabel
@onready var pause_title: Label = %Title
@onready var btn_close_modal: Button = %BtnCloseModal

@onready var achievements_modal: Control = %AchievementsModal
@onready var achievements_modal_title: Label = %AchievementsModalTitle
@onready var achievements_progress_label: Label = %AchievementsProgressLabel
@onready var achievements_list: VBoxContainer = %AchievementsList
@onready var btn_close_achievements: Button = %BtnCloseAchievements

@onready var collectibles_modal: Control = %CollectiblesModal
@onready var collectibles_modal_title: Label = %CollectiblesModalTitle
@onready var collectibles_progress_label: Label = %CollectiblesProgressLabel
@onready var collectibles_list: VBoxContainer = %CollectiblesList
@onready var btn_close_collectibles: Button = %BtnCloseCollectibles

var _settings_instance: Control = null
var _modal_mode: String = "save" # "save" ou "load"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	slots_modal.visible = false
	achievements_modal.visible = false
	collectibles_modal.visible = false
	_apply_static_text()
	btn_resume.set_meta("primary_action",true)
	STYLE.apply(root_control)

	btn_resume.pressed.connect(resume_game)
	btn_save_game.pressed.connect(_on_save_game_pressed)
	btn_load_game.pressed.connect(_on_load_game_pressed)
	btn_achievements.pressed.connect(_on_achievements_pressed)
	btn_collectibles.pressed.connect(_on_collectibles_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_main_menu.pressed.connect(_on_main_menu_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)

	# Efeitos sonoros de botões
	MenuAudio.hook_buttons(self)

	var sm = get_node_or_null("/root/SettingsManager")
	if sm and not sm.language_changed.is_connected(_on_language_changed):
		sm.language_changed.connect(_on_language_changed)

func _apply_static_text() -> void:
	pause_title.text = tr("PAUSE_TITLE")
	btn_resume.text = tr("PAUSE_RESUME")
	btn_save_game.text = tr("PAUSE_SAVE")
	btn_load_game.text = tr("MENU_LOAD_GAME")
	btn_achievements.text = tr("MENU_ACHIEVEMENTS")
	btn_settings.text = tr("MENU_SETTINGS")
	btn_main_menu.text = tr("PAUSE_MAIN_MENU")
	btn_quit.text = tr("MENU_QUIT")
	btn_close_modal.text = tr("COMMON_BACK")
	achievements_modal_title.text = tr("PAUSE_ACHIEVEMENTS_TITLE")
	btn_close_achievements.text = tr("COMMON_BACK")
	# Collection labels follow the active locale without changing saved IDs.
	btn_collectibles.text = tr("COLLECTION_TITLE")
	collectibles_modal_title.text = tr("COLLECTION_TITLE")
	btn_close_collectibles.text = tr("COMMON_BACK")

func _on_language_changed(_locale: String) -> void:
	_apply_static_text()
	if slots_modal.visible:
		_refresh_slots_list()
		slots_modal_title.text = tr("PAUSE_SAVE_MODAL_TITLE") if _modal_mode == "save" else tr("MENU_LOAD_GAME")
	if achievements_modal.visible:
		_refresh_achievements_list()
	if collectibles_modal.visible:
		_refresh_collectibles_list()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo():
		var pause_pressed := event.is_action_pressed("pause_game")
		var back_pressed := event.is_action_pressed("ui_cancel")
		# Options abre a pausa. Círculo só volta/fecha quando o menu já está aberto.
		if pause_pressed or (visible and back_pressed):
			# In-world modal dialogue owns Escape first (NPC, mission board,
			# phone). Pausing here would freeze its gesture/close animation.
			var player := get_tree().get_first_node_in_group("player")
			if not visible and player != null and player.get("is_in_dialogue") == true:
				return
			# Se sub-janelas estiverem abertas, fechar primeiro a sub-janela
			if _settings_instance and is_instance_valid(_settings_instance) and _settings_instance.visible:
				_settings_instance._on_btn_back_pressed()
				get_viewport().set_input_as_handled()
				return
			
			if slots_modal.visible:
				_on_close_modal_pressed()
				get_viewport().set_input_as_handled()
				return

			if achievements_modal.visible:
				_on_close_achievements_pressed()
				get_viewport().set_input_as_handled()
				return

			if collectibles_modal.visible:
				_on_close_collectibles_pressed()
				get_viewport().set_input_as_handled()
				return

			# Alternar pausa
			if visible:
				resume_game()
			else:
				pause_game()
			get_viewport().set_input_as_handled()

func pause_game() -> void:
	_set_actions_disabled(false)
	visible = true
	get_tree().paused = true
	slots_modal.visible = false
	achievements_modal.visible = false
	collectibles_modal.visible = false
	btn_resume.grab_focus()

func resume_game() -> void:
	_set_actions_disabled(false)
	visible = false
	slots_modal.visible = false
	achievements_modal.visible = false
	collectibles_modal.visible = false
	if _settings_instance and is_instance_valid(_settings_instance):
		_settings_instance.visible = false
	get_tree().paused = false

func _on_save_game_pressed() -> void:
	_set_actions_disabled(true)
	_modal_mode = "save"
	slots_modal_title.text = tr("PAUSE_SAVE_MODAL_TITLE")
	_refresh_slots_list()
	slots_modal.visible = true
	STYLE.trap_focus.call_deferred(slots_modal)

func _on_load_game_pressed() -> void:
	_set_actions_disabled(true)
	_modal_mode = "load"
	slots_modal_title.text = tr("MENU_LOAD_GAME")
	_refresh_slots_list()
	slots_modal.visible = true
	STYLE.trap_focus.call_deferred(slots_modal)

func _refresh_slots_list() -> void:
	for child in slots_list.get_children():
		child.queue_free()

	slots_status_label.text = tr("PAUSE_SELECT_SLOT")
	slots_status_label.add_theme_color_override("font_color", Color("#d2dae2"))

	var sm = get_node_or_null("/root/SaveManager")
	if not sm:
		slots_status_label.text = tr("MENU_ERROR_NO_SAVEMANAGER")
		return
	
	var slots: Array[Dictionary] = sm.list_slots()
	
	for info in slots:
		var slot_id: String = info.get("slot_id", "")
		# Não permitir salvar manualmente por cima do autosave direto
		if _modal_mode == "save" and slot_id == "autosave":
			continue
		
		var exists: bool = info.get("exists", false)
		var valid: bool = info.get("valid", false)
		var err_text: String = info.get("error", "")
		var date_str: String = info.get("date_string", "")
		var summary: Dictionary = info.get("summary", {})
		
		var btn := Button.new()
		btn.set_meta("save_slot",slot_id)
		btn.custom_minimum_size = Vector2(0, 48)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		var display_text := ""
		if not exists:
			display_text = tr("MENU_SLOT_EMPTY") % SAVE_TEXT.slot_name(slot_id)
			if _modal_mode == "load":
				btn.disabled = true
			else:
				btn.add_theme_color_override("font_color", Color("#a4b0be"))
				btn.pressed.connect(func(): _execute_slot_action(slot_id))
		elif not valid:
			display_text = tr("PAUSE_SLOT_INCOMPATIBLE") % [SAVE_TEXT.slot_name(slot_id), err_text]
			if _modal_mode == "load":
				btn.disabled = true
				btn.add_theme_color_override("font_disabled_color", Color("#e74c3c"))
			else:
				# Permitir sobrescrever slot inválido ao salvar
				btn.add_theme_color_override("font_color", Color("#e67e22"))
				btn.pressed.connect(func(): _execute_slot_action(slot_id))
		else:
			var money: int = int(summary.get("money", 0))
			var stage: String = SAVE_TEXT.stage_name(String(summary.get("current_stage", "")),get_node("/root/CampaignState"))
			var stars: int = int(summary.get("current_stars", 0))
			var stars_str := ""
			for s in range(stars): stars_str += "★"
			
			display_text = "%s · %s · $%d\n%s  %s" % [
				SAVE_TEXT.slot_name(slot_id), date_str, money, stage, stars_str
			]
			btn.add_theme_color_override("font_color", Color("#f1c40f"))
			btn.pressed.connect(func(): _execute_slot_action(slot_id))
		
		btn.text = display_text
		STYLE.apply(btn)
		MenuAudio.hook_button(btn, self)
		preload("res://ui/SaveSlotRow.gd").install(self, slots_list, btn, info, _refresh_slots_list, slots_status_label)

func _execute_slot_action(slot_id: String) -> void:
	if get_node("/root/GameLoading").active: return
	var sm = get_node_or_null("/root/SaveManager")
	if not sm: return

	if _modal_mode == "save":
		var res: Dictionary = sm.save_game(slot_id, "Save Manual")
		if res.get("success", false):
			_refresh_slots_list()
			slots_status_label.text = tr("PAUSE_SAVED_OK") % SAVE_TEXT.slot_name(slot_id)
			slots_status_label.add_theme_color_override("font_color", Color("#2ecc71"))
		else:
			slots_status_label.text = tr("PAUSE_SAVE_ERROR") % res.get("error", "")
			slots_status_label.add_theme_color_override("font_color", Color("#e74c3c"))
	elif _modal_mode == "load":
		var res: Dictionary = sm.load_game(slot_id)
		if res.get("success", false):
			slots_status_label.text = tr("PAUSE_LOADING")
			get_node("/root/GameLoading").begin(SCENE_ROUTE.for_save(res.get("data", {})))
		else:
			slots_status_label.text = tr("PAUSE_LOAD_ERROR") % res.get("error", "")
			slots_status_label.add_theme_color_override("font_color", Color("#e74c3c"))

func _on_close_modal_pressed() -> void:
	_set_actions_disabled(false)
	slots_modal.visible = false
	(btn_save_game if _modal_mode == "save" else btn_load_game).grab_focus()

func _on_achievements_pressed() -> void:
	_set_actions_disabled(true)
	_refresh_achievements_list()
	achievements_modal.visible = true
	STYLE.apply(achievements_modal,get_node("/root/SettingsManager").text_scale)
	STYLE.trap_focus(achievements_modal)

func _on_close_achievements_pressed() -> void:
	_set_actions_disabled(false)
	achievements_modal.visible = false
	btn_achievements.grab_focus()

func _refresh_achievements_list() -> void:
	for child in achievements_list.get_children():
		child.queue_free()

	var player := get_tree().get_first_node_in_group("player")
	var unlocked: Array = []
	if player and player.get("unlocked_achievements") is Array:
		unlocked = player.get("unlocked_achievements")

	var ids: Array = ACHIEVEMENT_CATALOG.ACHIEVEMENTS.keys()
	achievements_progress_label.text = tr("PAUSE_ACHIEVEMENTS_PROGRESS") % [unlocked.size(), ids.size()]

	for achievement_id in ids:
		var entry: Dictionary = ACHIEVEMENT_CATALOG.ACHIEVEMENTS[achievement_id]
		var is_unlocked: bool = unlocked.has(achievement_id)

		var row := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.14, 0.04, 0.55) if is_unlocked else Color(0.10, 0.10, 0.12, 0.55)
		style.border_color = Color("#f6c445") if is_unlocked else Color(0.30, 0.30, 0.32)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		row.add_theme_stylebox_override("panel", style)
		achievements_list.add_child(row)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		row.add_child(hbox)

		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(vbox)

		var title_label := Label.new()
		title_label.text = String(entry.get("name", achievement_id))
		title_label.add_theme_font_size_override("font_size", 15)
		title_label.add_theme_color_override("font_color", Color("#f6c445") if is_unlocked else Color(0.82, 0.84, 0.86))
		vbox.add_child(title_label)

		var desc_label := Label.new()
		desc_label.text = String(entry.get("desc", "")) + " · $%d" % ACHIEVEMENT_CATALOG.cash_reward(achievement_id)
		desc_label.add_theme_font_size_override("font_size", 11)
		desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_label)

		var status_label := Label.new()
		status_label.text = tr("PAUSE_ACHIEVEMENTS_UNLOCKED") if is_unlocked else tr("PAUSE_ACHIEVEMENTS_LOCKED")
		status_label.custom_minimum_size = Vector2(96, 0)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_label.add_theme_font_size_override("font_size", 10)
		status_label.add_theme_color_override("font_color", Color("#2ed573") if is_unlocked else Color(0.5, 0.5, 0.5))
		hbox.add_child(status_label)

func _on_collectibles_pressed() -> void:
	_set_actions_disabled(true)
	_refresh_collectibles_list()
	collectibles_modal.visible = true
	STYLE.apply(collectibles_modal,get_node("/root/SettingsManager").text_scale)
	STYLE.trap_focus(collectibles_modal,false)
	btn_close_collectibles.grab_focus()

func _on_close_collectibles_pressed() -> void:
	_set_actions_disabled(false)
	collectibles_modal.visible = false
	btn_collectibles.grab_focus()

## Player.collectibles_found é a única fonte de verdade de progresso.
## CollectibleCatalog só decora com nome/região; um ID achado que não está no
## catálogo (save de uma versão antiga do mapa, por exemplo) não é descartado
## — vira uma linha "achado registrado" separada, preservando o registro.
func _refresh_collectibles_list() -> void:
	for child in collectibles_list.get_children():
		child.queue_free()

	var player := get_tree().get_first_node_in_group("player")
	var found: Array = []
	if player and player.get("collectibles_found") is Array:
		found = player.get("collectibles_found")

	var known_ids: Array = COLLECTIBLE_CATALOG.get_all_ids()
	var known_found_count := 0
	for collectible_id in known_ids:
		if found.has(collectible_id):
			known_found_count += 1

	collectibles_progress_label.text = tr("COLLECTION_PROGRESS") % [known_found_count, known_ids.size()]
	collectibles_progress_label.text += "\n" + COLLECTIBLE_CATALOG.reward_summary(found)

	for collectible_id in known_ids:
		var entry: Dictionary = COLLECTIBLE_CATALOG.get_entry(collectible_id)
		var is_found: bool = found.has(collectible_id)
		var title := tr(String(entry.get("name", collectible_id))) if is_found else "???"
		var region := tr(String(entry.get("region", ""))) if is_found else "???"
		_add_collectible_row(title, region, is_found)

	var unknown_ids: Array = []
	for collectible_id in found:
		if not known_ids.has(collectible_id) and not unknown_ids.has(collectible_id):
			unknown_ids.append(collectible_id)

	if not unknown_ids.is_empty():
		var legacy_header := Label.new()
		legacy_header.text = tr("COLLECTION_LEGACY") % unknown_ids.size()
		legacy_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		legacy_header.add_theme_font_size_override("font_size", 10)
		legacy_header.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
		collectibles_list.add_child(legacy_header)
		for collectible_id in unknown_ids:
			_add_collectible_row(tr("COLLECTION_RECORDED"), "ID: %s" % collectible_id, true)

func _add_collectible_row(title: String, subtitle: String, is_found: bool) -> void:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.14, 0.16, 0.55) if is_found else Color(0.10, 0.10, 0.12, 0.55)
	style.border_color = Color("#63e6d4") if is_found else Color(0.30, 0.30, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", style)
	collectibles_list.add_child(row)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", Color("#63e6d4") if is_found else Color(0.55, 0.55, 0.58))
	vbox.add_child(title_label)

	var region_label := Label.new()
	region_label.text = subtitle
	region_label.add_theme_font_size_override("font_size", 11)
	region_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8) if is_found else Color(0.45, 0.45, 0.48))
	region_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(region_label)

	var status_label := Label.new()
	status_label.text = tr("COLLECTION_FOUND") if is_found else tr("COLLECTION_MISSING")
	status_label.custom_minimum_size = Vector2(120, 0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", Color("#2ed573") if is_found else Color(0.5, 0.5, 0.5))
	hbox.add_child(status_label)

func _on_settings_pressed() -> void:
	_set_actions_disabled(true)
	if not _settings_instance or not is_instance_valid(_settings_instance):
		_settings_instance = SETTINGS_SCENE.instantiate()
		_settings_instance.closed.connect(_on_settings_closed)
		add_child(_settings_instance)
	_settings_instance.visible = true

func _on_settings_closed() -> void:
	_set_actions_disabled(false)
	btn_settings.grab_focus()

func _on_main_menu_pressed() -> void:
	resume_game()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_quit_pressed() -> void:
	resume_game()
	get_tree().quit()

func _set_actions_disabled(value: bool) -> void:
	for button in [btn_resume,btn_save_game,btn_load_game,btn_achievements,btn_collectibles,btn_settings,btn_main_menu,btn_quit]: button.disabled = value
