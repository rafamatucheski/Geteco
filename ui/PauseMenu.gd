extends CanvasLayer

## Menu de Pausa In-Game
## Controla congelamento total da simulação (get_tree().paused = true) evitando gasto de CPU.
## Permite salvar em slots manuais, carregar, configurar e voltar ao menu inicial.

const SETTINGS_SCENE: PackedScene = preload("res://ui/SettingsMenu.tscn")
const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"
const MenuAudio = preload("res://ui/MenuAudio.gd")

@onready var root_control: Control = %RootControl
@onready var btn_resume: Button = %BtnResume
@onready var btn_save_game: Button = %BtnSaveGame
@onready var btn_load_game: Button = %BtnLoadGame
@onready var btn_settings: Button = %BtnSettings
@onready var btn_main_menu: Button = %BtnMainMenu
@onready var btn_quit: Button = %BtnQuit

@onready var slots_modal: Control = %SlotsModal
@onready var slots_modal_title: Label = %SlotsModalTitle
@onready var slots_list: VBoxContainer = %SlotsList
@onready var slots_status_label: Label = %SlotsStatusLabel

var _settings_instance: Control = null
var _modal_mode: String = "save" # "save" ou "load"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	slots_modal.visible = false
	
	btn_resume.pressed.connect(resume_game)
	btn_save_game.pressed.connect(_on_save_game_pressed)
	btn_load_game.pressed.connect(_on_load_game_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_main_menu.pressed.connect(_on_main_menu_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)
	
	# Efeitos sonoros de botões
	MenuAudio.hook_buttons(self)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# Se sub-janelas estiverem abertas, fechar primeiro a sub-janela
			if _settings_instance and is_instance_valid(_settings_instance) and _settings_instance.visible:
				_settings_instance.visible = false
				get_viewport().set_input_as_handled()
				return
			
			if slots_modal.visible:
				slots_modal.visible = false
				btn_save_game.grab_focus()
				get_viewport().set_input_as_handled()
				return
			
			# Alternar pausa
			if visible:
				resume_game()
			else:
				pause_game()
			get_viewport().set_input_as_handled()

func pause_game() -> void:
	visible = true
	get_tree().paused = true
	slots_modal.visible = false
	btn_resume.grab_focus()

func resume_game() -> void:
	visible = false
	slots_modal.visible = false
	if _settings_instance and is_instance_valid(_settings_instance):
		_settings_instance.visible = false
	get_tree().paused = false

func _on_save_game_pressed() -> void:
	_modal_mode = "save"
	slots_modal_title.text = "SALVAR JOGO (ESCOLHA UM SLOT)"
	_refresh_slots_list()
	slots_modal.visible = true

func _on_load_game_pressed() -> void:
	_modal_mode = "load"
	slots_modal_title.text = "CARREGAR JOGO"
	_refresh_slots_list()
	slots_modal.visible = true

func _refresh_slots_list() -> void:
	for child in slots_list.get_children():
		child.queue_free()
	
	slots_status_label.text = "Selecione um slot:"
	slots_status_label.add_theme_color_override("font_color", Color("#d2dae2"))
	
	var sm = get_node_or_null("/root/SaveManager")
	if not sm:
		slots_status_label.text = "Erro: SaveManager indisponível."
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
		btn.custom_minimum_size = Vector2(0, 48)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		var display_text := ""
		if not exists:
			display_text = "  [%s] --- VAZIO ---" % slot_id.to_upper()
			if _modal_mode == "load":
				btn.disabled = true
			else:
				btn.add_theme_color_override("font_color", Color("#a4b0be"))
				btn.pressed.connect(func(): _execute_slot_action(slot_id))
		elif not valid:
			display_text = "  [%s] ✖ INCOMPATÍVEL: %s" % [slot_id.to_upper(), err_text]
			if _modal_mode == "load":
				btn.disabled = true
				btn.add_theme_color_override("font_disabled_color", Color("#e74c3c"))
			else:
				# Permitir sobrescrever slot inválido ao salvar
				btn.add_theme_color_override("font_color", Color("#e67e22"))
				btn.pressed.connect(func(): _execute_slot_action(slot_id))
		else:
			var money: int = int(summary.get("money", 0))
			var stage: String = String(summary.get("current_stage", "início"))
			var stars: int = int(summary.get("current_stars", 0))
			var stars_str := ""
			for s in range(stars): stars_str += "★"
			
			display_text = "  [%s]  %s  |  $%07d  |  %s  %s" % [
				slot_id.to_upper(), date_str, money, stage, stars_str
			]
			btn.add_theme_color_override("font_color", Color("#f1c40f"))
			btn.pressed.connect(func(): _execute_slot_action(slot_id))
		
		btn.text = display_text
		MenuAudio.hook_button(btn, self)
		slots_list.add_child(btn)

func _execute_slot_action(slot_id: String) -> void:
	var sm = get_node_or_null("/root/SaveManager")
	if not sm: return
	
	if _modal_mode == "save":
		var res: Dictionary = sm.save_game(slot_id, "Save Manual")
		if res.get("success", false):
			slots_status_label.text = "✓ Jogo salvo com sucesso no %s!" % slot_id.to_upper()
			slots_status_label.add_theme_color_override("font_color", Color("#2ecc71"))
			_refresh_slots_list()
		else:
			slots_status_label.text = "Erro ao salvar: %s" % res.get("error", "")
			slots_status_label.add_theme_color_override("font_color", Color("#e74c3c"))
	elif _modal_mode == "load":
		var res: Dictionary = sm.load_game(slot_id)
		if res.get("success", false):
			slots_status_label.text = "Carregando save..."
			resume_game()
			sm.apply_pending_save(get_tree())
		else:
			slots_status_label.text = "Erro ao carregar: %s" % res.get("error", "")
			slots_status_label.add_theme_color_override("font_color", Color("#e74c3c"))

func _on_close_modal_pressed() -> void:
	slots_modal.visible = false
	btn_save_game.grab_focus()

func _on_settings_pressed() -> void:
	if not _settings_instance or not is_instance_valid(_settings_instance):
		_settings_instance = SETTINGS_SCENE.instantiate()
		_settings_instance.closed.connect(_on_settings_closed)
		add_child(_settings_instance)
	_settings_instance.visible = true

func _on_settings_closed() -> void:
	btn_settings.grab_focus()

func _on_main_menu_pressed() -> void:
	resume_game()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_quit_pressed() -> void:
	resume_game()
	get_tree().quit()
