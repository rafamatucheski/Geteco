extends Control

## Menu Principal do Jogo
## Entrypoint declarado em project.godot (run/main_scene="res://ui/MainMenu.tscn")
## Suporta: Novo Jogo, Carregar Jogo (com auditoria de slots), Configurações e Sair.

const MAIN_GAME_SCENE: String = "res://Main.tscn"
const SETTINGS_SCENE: PackedScene = preload("res://ui/SettingsMenu.tscn")

@onready var btn_new_game: Button = %BtnNewGame
@onready var btn_load_game: Button = %BtnLoadGame
@onready var btn_settings: Button = %BtnSettings
@onready var btn_quit: Button = %BtnQuit

@onready var load_panel: Control = %LoadPanel
@onready var slot_list_container: VBoxContainer = %SlotListContainer
@onready var label_load_status: Label = %LabelLoadStatus

var _selected_slot_id: String = ""
var _settings_instance: Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_panel.visible = false
	
	# Conexões dos botões principais
	btn_new_game.pressed.connect(_on_btn_new_game_pressed)
	btn_load_game.pressed.connect(_on_btn_load_game_pressed)
	btn_settings.pressed.connect(_on_btn_settings_pressed)
	btn_quit.pressed.connect(_on_btn_quit_pressed)
	
	# Foco inicial para teclado / gamepad
	btn_new_game.grab_focus()

func _on_btn_new_game_pressed() -> void:
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
	label_load_status.text = "Selecione um slot de save salvo para carregar:"
	label_load_status.add_theme_color_override("font_color", Color("#d2dae2"))
	
	var sm = get_node_or_null("/root/SaveManager")
	if not sm:
		label_load_status.text = "Erro: SaveManager não está ativo."
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
			text_content = "  [%s] --- VAZIO ---" % slot_id.to_upper()
			panel_btn.disabled = true
		elif not valid:
			text_content = "  [%s] ✖ INCOMPATÍVEL / CORROMPIDO: %s" % [slot_id.to_upper(), err_text]
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
		slot_list_container.add_child(panel_btn)
	
	if not any_valid:
		label_load_status.text = "Nenhum save válido encontrado em user://saves/."

func _select_and_load_slot(slot_id: String) -> void:
	var sm = get_node_or_null("/root/SaveManager")
	if not sm:
		label_load_status.text = "Erro: SaveManager indisponível."
		return
	
	var res: Dictionary = sm.load_game(slot_id)
	if res.get("success", false):
		label_load_status.text = "Carregando %s..." % slot_id
		get_tree().change_scene_to_file(MAIN_GAME_SCENE)
	else:
		label_load_status.text = "Falha ao carregar: %s" % res.get("error", "Erro desconhecido")
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
	get_tree().quit()
