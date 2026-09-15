extends Control

## Menu Principal do Jogo
## Entrypoint declarado em project.godot (run/main_scene="res://ui/MainMenu.tscn")
## Suporta: Novo Jogo, Carregar Jogo (com auditoria de slots), Configurações e Sair.

const MAIN_GAME_SCENE: String = "res://world/harbor/HarborGame.tscn"
const SCENE_ROUTE = preload("res://world/harbor/HarborSceneRoute.gd")
const SETTINGS_SCENE: PackedScene = preload("res://ui/SettingsMenu.tscn")
const MenuAudio = preload("res://ui/MenuAudio.gd")

@onready var btn_new_game: Button = %BtnNewGame
@onready var btn_load_game: Button = %BtnLoadGame
@onready var btn_settings: Button = %BtnSettings
@onready var btn_quit: Button = %BtnQuit

@onready var load_panel: Control = %LoadPanel
@onready var slot_list_container: VBoxContainer = %SlotListContainer
@onready var label_load_status: Label = %LabelLoadStatus
@onready var game_title: Label = %GameTitle
@onready var sub_title: Label = %SubTitle
@onready var load_panel_title: Label = %Title
@onready var btn_close_load: Button = %BtnCloseLoad

var _selected_slot_id: String = ""
var _settings_instance: Control = null
var _music_player: AudioStreamPlayer = null
var _starting_game := false
var btn_continue: Button
var _latest_slot := ""
var latest_save: Dictionary = {}
const SAVE_TEXT = preload("res://ui/SavePresentation.gd")
var _load_shade: ColorRect
const STYLE = preload("res://ui/GameStyle.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_panel.visible = false
	_setup_continue()
	_apply_static_text()
	var presentation := preload("res://ui/SunsetMenuPresentation.gd").new()
	add_child(presentation)
	move_child(presentation, get_node("LoadPanel").get_index())
	presentation.install(self)
	_load_shade = ColorRect.new()
	_load_shade.color = Color(0.02,0.03,0.04,0.75)
	_load_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_load_shade)
	move_child(_load_shade,load_panel.get_index())
	_load_shade.hide()
	STYLE.apply(load_panel)
	var loading := get_node("/root/GameLoading")
	loading.failed.connect(_on_loading_failed)
	# Harbor is both the new-game scene and the destination of current saves.
	# Start its resource I/O after the menu's first setup cycle so Continue can
	# reuse the in-flight result without touching or staging the player's save.
	loading.call_deferred("prefetch", MAIN_GAME_SCENE)

	# Conexões dos botões principais
	btn_new_game.pressed.connect(_on_btn_new_game_pressed)
	btn_load_game.pressed.connect(_on_btn_load_game_pressed)
	btn_settings.pressed.connect(_on_btn_settings_pressed)
	btn_quit.pressed.connect(_on_btn_quit_pressed)

	# Áudio de interface e música de fundo
	MenuAudio.hook_buttons(self)
	_start_bg_music()

	# Foco inicial para teclado / gamepad
	(btn_continue if not _latest_slot.is_empty() else btn_new_game).grab_focus()

	var sm = get_node_or_null("/root/SettingsManager")
	if sm and not sm.language_changed.is_connected(_on_language_changed):
		sm.language_changed.connect(_on_language_changed)

func _apply_static_text() -> void:
	sub_title.text = tr("MENU_SUBTITLE")
	btn_new_game.text = tr("MENU_NEW_GAME")
	btn_load_game.text = tr("MENU_LOAD_GAME")
	btn_settings.text = tr("MENU_SETTINGS")
	btn_quit.text = tr("MENU_QUIT")
	load_panel_title.text = tr("MENU_LOAD_TITLE")
	btn_close_load.text = tr("COMMON_CLOSE")
	if btn_continue != null: btn_continue.text = _text("CONTINUAR", "CONTINUE")

func _on_language_changed(_locale: String) -> void:
	_apply_static_text()
	if load_panel.visible:
		_refresh_load_panel()

func _start_bg_music() -> void:
	if not _music_player or not is_instance_valid(_music_player):
		_music_player = AudioStreamPlayer.new()
		_music_player.name = "MenuMusicPlayer"
		_music_player.bus = MenuAudio.get_music_bus_name()
		_music_player.stream = MenuAudio.get_music_stream()
		_music_player.volume_db = -10.0
		_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_music_player)
	if not _music_player.playing:
		_music_player.play()

func _stop_bg_music() -> void:
	if _music_player and is_instance_valid(_music_player) and _music_player.playing:
		_music_player.stop()

func _on_btn_new_game_pressed() -> void:
	if _starting_game: return
	_starting_game = true
	MenuAudio.play_start(self)
	var pres = get_node_or_null("SunsetPresentation")
	if pres and pres.has_method("play_start_transition") and DisplayServer.get_name() != "headless" and not get_node("/root/SettingsManager").reduce_motion:
		await pres.play_start_transition()
	get_node("/root/GameLoading").begin(MAIN_GAME_SCENE, true)

func _on_btn_load_game_pressed() -> void:
	if _starting_game: return
	_refresh_load_panel()
	load_panel.visible = true
	_load_shade.show()
	_set_main_buttons_disabled(true)
	STYLE.trap_focus.call_deferred(load_panel)

func _refresh_load_panel() -> void:
	for child in slot_list_container.get_children():
		child.queue_free()
	
	_selected_slot_id = ""
	label_load_status.text = tr("MENU_LOAD_SELECT_SLOT")
	label_load_status.add_theme_color_override("font_color", Color("#d2dae2"))

	var sm = get_node_or_null("/root/SaveManager")
	if not sm:
		label_load_status.text = tr("MENU_ERROR_NO_SAVEMANAGER")
		return
	
	var slots: Array[Dictionary] = sm.list_slots()
	var any_valid := false
	
	for info in slots:
		var slot_id: String = info.get("slot_id", "")
		var exists: bool = info.get("exists", false)
		var valid: bool = info.get("valid", false)
		var err_text: String = info.get("error", "")
		var date_str: String = info.get("date_string", "")
		var summary: Dictionary = info.get("summary", {})
		
		var panel_btn := Button.new()
		panel_btn.set_meta("save_slot",slot_id)
		panel_btn.custom_minimum_size = Vector2(0, 52)
		panel_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		var text_content := ""
		if not exists:
			text_content = tr("MENU_SLOT_EMPTY") % SAVE_TEXT.slot_name(slot_id)
			panel_btn.disabled = true
		elif not valid:
			text_content = tr("MENU_SLOT_INCOMPATIBLE") % [SAVE_TEXT.slot_name(slot_id), err_text]
			panel_btn.disabled = true
			panel_btn.add_theme_color_override("font_disabled_color", Color("#e74c3c"))
		else:
			any_valid = true
			var money: int = int(summary.get("money", 0))
			var stage: String = SAVE_TEXT.stage_name(String(summary.get("current_stage", "")),get_node("/root/CampaignState"))
			var stars: int = int(summary.get("current_stars", 0))
			var stars_str := ""
			for s in range(stars): stars_str += "★"
			
			text_content = "%s · %s · $%d\n%s  %s" % [
				SAVE_TEXT.slot_name(slot_id), date_str, money, stage, stars_str
			]
			panel_btn.add_theme_color_override("font_color", Color("#f1c40f"))
			panel_btn.pressed.connect(func(): _select_and_load_slot(slot_id))
		
		panel_btn.text = text_content
		STYLE.apply(panel_btn)
		MenuAudio.hook_button(panel_btn, self)
		slot_list_container.add_child(panel_btn)
	
	if not any_valid:
		label_load_status.text = tr("MENU_NO_VALID_SAVES")

func _select_and_load_slot(slot_id: String) -> void:
	if _starting_game: return
	var sm = get_node_or_null("/root/SaveManager")
	if not sm:
		label_load_status.text = tr("MENU_ERROR_NO_SAVEMANAGER")
		return

	var res: Dictionary = sm.load_game(slot_id)
	if res.get("success", false):
		_starting_game = true
		MenuAudio.play_start(self)
		_stop_bg_music()
		label_load_status.text = tr("MENU_LOADING") % slot_id
		var pres = get_node_or_null("SunsetPresentation")
		if pres and pres.has_method("play_start_transition") and DisplayServer.get_name() != "headless" and not get_node("/root/SettingsManager").reduce_motion:
			await pres.play_start_transition()
		get_node("/root/GameLoading").begin(SCENE_ROUTE.for_save(res.get("data", {})))
	else:
		label_load_status.text = tr("MENU_LOAD_FAILED") % res.get("error", tr("COMMON_UNKNOWN_ERROR"))
		label_load_status.add_theme_color_override("font_color", Color("#e74c3c"))

func _on_close_load_panel_pressed() -> void:
	load_panel.visible = false
	_load_shade.hide()
	_set_main_buttons_disabled(false)
	btn_load_game.grab_focus()

func _on_btn_settings_pressed() -> void:
	if not _settings_instance or not is_instance_valid(_settings_instance):
		_settings_instance = SETTINGS_SCENE.instantiate()
		_settings_instance.closed.connect(_on_settings_closed)
		add_child(_settings_instance)
	_settings_instance.visible = true
	_set_main_buttons_disabled(true)

func _on_settings_closed() -> void:
	_set_main_buttons_disabled(false)
	btn_settings.grab_focus()

func _on_btn_quit_pressed() -> void:
	btn_quit.disabled = true
	await get_tree().create_timer(0.18).timeout
	get_tree().quit()

func _setup_continue() -> void:
	var latest := 0
	for slot in get_node("/root/SaveManager").list_slots():
		if slot.valid and int(slot.timestamp) >= latest:
			latest = int(slot.timestamp)
			_latest_slot = slot.slot_id
			latest_save = slot
	btn_continue = Button.new()
	btn_continue.name = "BtnContinue"
	btn_continue.visible = not _latest_slot.is_empty()
	add_child(btn_continue)
	btn_continue.pressed.connect(func(): _select_and_load_slot(_latest_slot))
	MenuAudio.hook_button(btn_continue,self)

func _set_main_buttons_disabled(value: bool) -> void:
	for button in [btn_continue,btn_new_game,btn_load_game,btn_settings,btn_quit]:
		button.disabled = value

func _unhandled_input(event: InputEvent) -> void:
	if load_panel.visible and event.is_action_pressed("ui_cancel"):
		_on_close_load_panel_pressed()
		get_viewport().set_input_as_handled()

func _on_loading_failed(_message: String) -> void:
	_starting_game = false
	_set_main_buttons_disabled(load_panel.visible)
	if load_panel.visible: STYLE.trap_focus(load_panel)
	_start_bg_music()

func _text(pt: String,en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt
