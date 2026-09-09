extends Control

## Tela de Configurações
## Controla barramentos reais do AudioServer e parâmetros de vídeo através do SettingsManager.
## Persiste em user://settings.cfg via SettingsManager.

signal closed()

const MenuAudio = preload("res://ui/MenuAudio.gd")

@onready var slider_master: HSlider = %SliderMaster
@onready var label_master: Label = %LabelMasterVal
@onready var slider_music: HSlider = %SliderMusic
@onready var label_music: Label = %LabelMusicVal
@onready var slider_sfx: HSlider = %SliderSFX
@onready var label_sfx: Label = %LabelSFXVal

@onready var opt_window_mode: OptionButton = %OptWindowMode
@onready var opt_resolution: OptionButton = %OptResolution
@onready var check_vsync: CheckBox = %CheckVSync
@onready var opt_language: OptionButton = %OptLanguage
@onready var label_language: Label = %LabelLanguage
@onready var controls_list: VBoxContainer = %ControlsList

@onready var tab_audio_btn: Button = %TabAudioBtn
@onready var tab_video_btn: Button = %TabVideoBtn
@onready var tab_controls_btn: Button = %TabControlsBtn

@onready var panel_audio: Control = %PanelAudio
@onready var panel_video: Control = %PanelVideo
@onready var panel_controls: Control = %PanelControls

@onready var title_label: Label = %Title
@onready var label_master_row: Label = %LabelMasterRow
@onready var label_music_row: Label = %LabelMusicRow
@onready var label_sfx_row: Label = %LabelSFXRow
@onready var audio_hint: Label = %AudioHint
@onready var label_mode_row: Label = %LabelModeRow
@onready var label_res_row: Label = %LabelResRow
@onready var label_vsync_row: Label = %LabelVsyncRow
@onready var btn_defaults: Button = %BtnDefaults
@onready var btn_back: Button = %BtnBack
@onready var btn_save: Button = %BtnSave

const LOCALES: Array[String] = ["pt_BR", "en"]

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080)
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_options()
	_load_values_from_manager()
	_populate_controls_list()
	_apply_static_text()
	_select_tab(0)
	MenuAudio.hook_buttons(self)
	visibility_changed.connect(_on_visibility_changed)
	tab_audio_btn.grab_focus.call_deferred()
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and not sm.language_changed.is_connected(_on_language_changed):
		sm.language_changed.connect(_on_language_changed)

func _apply_static_text() -> void:
	title_label.text = tr("SETTINGS_TITLE")
	tab_audio_btn.text = tr("SETTINGS_TAB_AUDIO")
	tab_video_btn.text = tr("SETTINGS_TAB_VIDEO")
	tab_controls_btn.text = tr("SETTINGS_TAB_CONTROLS")
	label_language.text = tr("SETTINGS_LANGUAGE_LABEL")
	label_master_row.text = tr("SETTINGS_MASTER_VOLUME")
	label_music_row.text = tr("SETTINGS_MUSIC_VOLUME")
	label_sfx_row.text = tr("SETTINGS_SFX_VOLUME")
	audio_hint.text = tr("SETTINGS_AUDIO_HINT")
	label_mode_row.text = tr("SETTINGS_WINDOW_MODE")
	label_res_row.text = tr("SETTINGS_RESOLUTION")
	label_vsync_row.text = tr("SETTINGS_VSYNC")
	btn_defaults.text = tr("SETTINGS_BTN_DEFAULTS")
	btn_back.text = tr("SETTINGS_BTN_BACK")
	btn_save.text = tr("SETTINGS_BTN_SAVE")
	var lang_selected := opt_language.selected
	opt_language.clear()
	opt_language.add_item(tr("SETTINGS_LANGUAGE_PT_BR"), 0)
	opt_language.add_item(tr("SETTINGS_LANGUAGE_EN"), 1)
	if lang_selected >= 0:
		opt_language.select(lang_selected)

func _on_language_changed(_locale: String) -> void:
	_apply_static_text()
	_populate_controls_list()

func _setup_options() -> void:
	# Modos de janela
	opt_window_mode.clear()
	opt_window_mode.add_item("Janela", 0)
	opt_window_mode.add_item("Tela Cheia", 1)
	opt_window_mode.add_item("Tela Cheia Exclusiva", 2)

	# Resoluções
	opt_resolution.clear()
	for i in range(RESOLUTIONS.size()):
		var r := RESOLUTIONS[i]
		opt_resolution.add_item("%d x %d" % [r.x, r.y], i)

	# Idioma
	opt_language.clear()
	opt_language.add_item(tr("SETTINGS_LANGUAGE_PT_BR"), 0)
	opt_language.add_item(tr("SETTINGS_LANGUAGE_EN"), 1)

func _load_values_from_manager() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if not sm:
		return
	
	# Áudio
	slider_master.value = sm.master_volume
	_update_slider_label(label_master, sm.master_volume)
	
	slider_music.value = sm.music_volume
	_update_slider_label(label_music, sm.music_volume)
	
	slider_sfx.value = sm.sfx_volume
	_update_slider_label(label_sfx, sm.sfx_volume)
	
	# Vídeo
	opt_window_mode.select(clampi(sm.window_mode, 0, 2))
	
	var res_idx := 0
	for i in range(RESOLUTIONS.size()):
		if RESOLUTIONS[i] == sm.resolution:
			res_idx = i
			break
	opt_resolution.select(res_idx)
	
	check_vsync.button_pressed = sm.vsync

	var lang_idx := LOCALES.find(sm.language)
	opt_language.select(maxi(lang_idx, 0))

func _populate_controls_list() -> void:
	for child in controls_list.get_children():
		child.queue_free()
	
	var sm = get_node_or_null("/root/SettingsManager")
	var mappings: Array[Dictionary] = sm.get_controls_mapping() if sm else []
	
	for entry in mappings:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 28)
		
		var lbl_name := Label.new()
		lbl_name.text = entry.get("label", "")
		lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_name.add_theme_color_override("font_color", Color("#d2dae2"))
		lbl_name.add_theme_font_size_override("font_size", 14)
		row.add_child(lbl_name)
		
		var lbl_key := Label.new()
		lbl_key.text = entry.get("keys", "")
		lbl_key.size_flags_horizontal = Control.SIZE_SHRINK_END
		lbl_key.add_theme_color_override("font_color", Color("#f1c40f"))
		lbl_key.add_theme_font_size_override("font_size", 14)
		row.add_child(lbl_key)
		
		controls_list.add_child(row)

func _update_slider_label(label: Label, val: float) -> void:
	if label:
		label.text = "%d%%" % int(round(val * 100.0))

func _on_slider_master_value_changed(value: float) -> void:
	_update_slider_label(label_master, value)
	var sm = get_node_or_null("/root/SettingsManager")
	if sm: sm.set_master_volume(value)

func _on_slider_music_value_changed(value: float) -> void:
	_update_slider_label(label_music, value)
	var sm = get_node_or_null("/root/SettingsManager")
	if sm: sm.set_music_volume(value)

func _on_slider_sfx_value_changed(value: float) -> void:
	_update_slider_label(label_sfx, value)
	var sm = get_node_or_null("/root/SettingsManager")
	if sm: sm.set_sfx_volume(value)

func _on_opt_window_mode_item_selected(index: int) -> void:
	pass # Applied together with resolution and VSync.

func _on_opt_resolution_item_selected(index: int) -> void:
	pass # OptionButton audio is handled by MenuAudio.

func _on_check_vsync_toggled(toggled_on: bool) -> void:
	pass # Video changes are committed together by Apply.

func _on_opt_language_item_selected(index: int) -> void:
	if index < 0 or index >= LOCALES.size():
		return
	var sm = get_node_or_null("/root/SettingsManager")
	if sm: sm.set_language(LOCALES[index])

func _on_tab_audio_btn_pressed() -> void:
	_select_tab(0)

func _on_tab_video_btn_pressed() -> void:
	_select_tab(1)

func _on_tab_controls_btn_pressed() -> void:
	_select_tab(2)

func _select_tab(index: int) -> void:
	panel_audio.visible = (index == 0)
	panel_video.visible = (index == 1)
	panel_controls.visible = (index == 2)
	
	_style_tab_button(tab_audio_btn, index == 0)
	_style_tab_button(tab_video_btn, index == 1)
	_style_tab_button(tab_controls_btn, index == 2)

func _style_tab_button(btn: Button, active: bool) -> void:
	if active:
		btn.add_theme_color_override("font_color", Color("#f1c40f"))
	else:
		btn.add_theme_color_override("font_color", Color("#808e9b"))

func _on_btn_defaults_pressed() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.master_volume = 1.0
		sm.music_volume = 0.8
		sm.sfx_volume = 1.0
		sm.window_mode = 0
		sm.resolution = Vector2i(1280, 720)
		sm.vsync = true
		sm.language = "pt_BR"
		sm.apply_all_settings()
		_load_values_from_manager()

func _on_btn_save_pressed() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.window_mode = opt_window_mode.selected
		sm.resolution = RESOLUTIONS[opt_resolution.selected]
		sm.vsync = check_vsync.button_pressed
		sm.apply_all_settings()
		sm.save_settings()
	closed.emit()
	if get_parent() and get_parent() != get_tree().root:
		visible = false

func _on_btn_back_pressed() -> void:
	# Recarrega configurações anteriores para descartar mudanças não salvas
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.load_settings()
		sm.apply_all_settings()
	closed.emit()
	if get_parent() and get_parent() != get_tree().root:
		visible = false

func _on_visibility_changed() -> void:
	if is_visible_in_tree() and is_node_ready():
		_load_values_from_manager()
		tab_audio_btn.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		MenuAudio.play_click(self)
		_on_btn_back_pressed()
