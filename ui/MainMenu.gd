extends Control

## Menu Principal do Jogo
## Entrypoint declarado em project.godot (run/main_scene="res://ui/MainMenu.tscn")
## Suporta: Novo Jogo, Carregar Jogo (com auditoria de slots), Configurações e Sair.

const MAIN_GAME_SCENE: String = "res://district/harbor_preview/HarborGame.tscn"
const SCENE_ROUTE = preload("res://district/harbor_preview/HarborSceneRoute.gd")
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_panel.visible = false
	_apply_static_text()
	var presentation := preload("res://ui/SunsetMenuPresentation.gd").new()
	add_child(presentation)
	move_child(presentation, get_node("LoadPanel").get_index())
	presentation.install(self)

	# Conexões dos botões principais
	btn_new_game.pressed.connect(_on_btn_new_game_pressed)
	btn_load_game.pressed.connect(_on_btn_load_game_pressed)
	btn_settings.pressed.connect(_on_btn_settings_pressed)
	btn_quit.pressed.connect(_on_btn_quit_pressed)

	# Áudio de interface e música de fundo
	MenuAudio.hook_buttons(self)
	_start_bg_music()

	# Foco inicial para teclado / gamepad
	btn_new_game.grab_focus()

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
	if _starting_game:
		return
	_starting_game = true
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 120
	add_child(fade_layer)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(black)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(black, "color:a", 1.0, 0.45)
	if is_instance_valid(_music_player):
		tween.tween_property(_music_player, "volume_db", -60.0, 0.45)
	await tween.finished
	_stop_bg_music()
	# 1. Resetar CampaignState
	var campaign = get_node_or_null("/root/CampaignState")
	if campaign and campaign.has_method("reset_campaign"):
		campaign.reset_campaign()
	
	# 2. Resetar WantedManager
	var wanted = get_node_or_null("/root/WantedManager")
	if wanted and wanted.has_method("reset"):
		wanted.reset()
	
	# 3. Limpar qualquer save pendente
	var sm = get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("clear_pending_save"):
		sm.clear_pending_save()
	
	# 4. Carregar cena principal
	get_tree().change_scene_to_file(MAIN_GAME_SCENE)

func _on_btn_load_game_pressed() -> void:
	_refresh_load_panel()
	load_panel.visible = true

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
		panel_btn.custom_minimum_size = Vector2(0, 52)
		panel_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		var text_content := ""
		if not exists:
			text_content = tr("MENU_SLOT_EMPTY") % slot_id.to_upper()
			panel_btn.disabled = true
		elif not valid:
			text_content = tr("MENU_SLOT_INCOMPATIBLE") % [slot_id.to_upper(), err_text]
			panel_btn.disabled = true
			panel_btn.add_theme_color_override("font_disabled_color", Color("#e74c3c"))
		else:
			any_valid = true
			var money: int = int(summary.get("money", 0))
			var stage: String = String(summary.get("current_stage", "início"))
			var stars: int = int(summary.get("current_stars", 0))
			var stars_str := ""
			for s in range(stars): stars_str += "★"
			
			text_content = "  [%s]  %s  |  $%07d  |  %s  %s" % [
				slot_id.to_upper(), date_str, money, stage, stars_str
			]
			panel_btn.add_theme_color_override("font_color", Color("#f1c40f"))
			panel_btn.pressed.connect(func(): _select_and_load_slot(slot_id))
		
		panel_btn.text = text_content
		MenuAudio.hook_button(panel_btn, self)
		slot_list_container.add_child(panel_btn)
	
	if not any_valid:
		label_load_status.text = tr("MENU_NO_VALID_SAVES")

func _select_and_load_slot(slot_id: String) -> void:
	var sm = get_node_or_null("/root/SaveManager")
	if not sm:
		label_load_status.text = tr("MENU_ERROR_NO_SAVEMANAGER")
		return

	var res: Dictionary = sm.load_game(slot_id)
	if res.get("success", false):
		_stop_bg_music()
		label_load_status.text = tr("MENU_LOADING") % slot_id
		get_tree().change_scene_to_file(SCENE_ROUTE.for_save(res.get("data", {})))
	else:
		label_load_status.text = tr("MENU_LOAD_FAILED") % res.get("error", tr("COMMON_UNKNOWN_ERROR"))
		label_load_status.add_theme_color_override("font_color", Color("#e74c3c"))

func _on_close_load_panel_pressed() -> void:
	load_panel.visible = false
	btn_load_game.grab_focus()

func _on_btn_settings_pressed() -> void:
	if not _settings_instance or not is_instance_valid(_settings_instance):
		_settings_instance = SETTINGS_SCENE.instantiate()
		_settings_instance.closed.connect(_on_settings_closed)
		add_child(_settings_instance)
	_settings_instance.visible = true

func _on_settings_closed() -> void:
	btn_settings.grab_focus()

func _on_btn_quit_pressed() -> void:
	btn_quit.disabled = true
	await get_tree().create_timer(0.18).timeout
	get_tree().quit()
