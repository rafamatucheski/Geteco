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

const STYLE = preload("res://ui/GameStyle.gd")
var _snapshot: Dictionary = {}
var _remap_action := ""
var _control_hint: Label
var _comfort_panel: VBoxContainer
var _comfort_tab: Button
var _scale_option: OptionButton
var _motion_check: CheckBox
var _route_check: CheckBox
var _hints_check: CheckBox
var _video_confirmation: ConfirmationDialog
var _video_seconds := 0.0
var _video_previous: Dictionary = {}

const LOCALES: Array[String] = ["pt_BR", "en"]

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1440),
	Vector2i(2560, 1080),
	Vector2i(3440, 1440),
	Vector2i(3840, 2160)
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_snapshot = get_node("/root/SettingsManager").interface_snapshot()
	_setup_comfort()
	_setup_options()
	_load_values_from_manager()
	_populate_controls_list()
	_apply_static_text()
	_select_tab(0)
	STYLE.apply(self,get_node("/root/SettingsManager").text_scale)
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
	if lang_selected >= 0: opt_language.select(lang_selected)
	for i in 3: opt_window_mode.set_item_text(i,[_text("Janela","Windowed"),_text("Tela cheia","Fullscreen"),_text("Tela cheia exclusiva","Exclusive fullscreen")][i])
	check_vsync.text = _text("Ativado","Enabled")
	_comfort_tab.text = _text("CONFORTO","COMFORT")
	_motion_check.text = _text("Reduzir animações de interface","Reduce interface animation")
	_route_check.text = _text("Mostrar orientação no minimapa","Show minimap guidance")
	_hints_check.text = _text("Mostrar dicas contextuais","Show contextual hints")

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
	_scale_option.select(clampi(roundi((sm.text_scale-1.0)/0.125),0,2))
	_motion_check.set_pressed_no_signal(sm.reduce_motion)
	_route_check.set_pressed_no_signal(sm.route_visible)
	_hints_check.set_pressed_no_signal(sm.tutorial_hints)

func _populate_controls_list() -> void:
	for child in controls_list.get_children():
		controls_list.remove_child(child)
		child.queue_free()
	var controls := get_node("/root/GameInput")
	for action in controls.KEYS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",16)
		var label := Label.new()
		label.text = controls.label(action)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var key_button := Button.new()
		key_button.custom_minimum_size = Vector2(210,42)
		key_button.text = controls.hint(action,true)
		key_button.disabled = action == "pause_game"
		key_button.pressed.connect(func():
			_remap_action = action
			controls.remapping = true
			_control_hint.text = _text("Pressione uma tecla ou botão do mouse. Esc cancela.","Press a key or mouse button. Esc cancels."))
		row.add_child(key_button)
		controls_list.add_child(row)
	STYLE.apply(controls_list,get_node("/root/SettingsManager").text_scale)

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
	_comfort_panel.visible = (index == 3)
	_style_tab_button(_comfort_tab,index == 3)
	
	_style_tab_button(tab_audio_btn, index == 0)
	_style_tab_button(tab_video_btn, index == 1)
	_style_tab_button(tab_controls_btn, index == 2)
	STYLE.trap_focus.call_deferred(self,false)

func _style_tab_button(btn: Button, active: bool) -> void:
	if active:
		btn.add_theme_color_override("font_color", STYLE.ACCENT)
	else:
		btn.add_theme_color_override("font_color", Color("#808e9b"))

func _on_btn_defaults_pressed() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.master_volume = 1.0
		sm.music_volume = 0.8
		sm.sfx_volume = 1.0
		sm.language = "pt_BR"
		sm.text_scale = 1.0
		sm.reduce_motion = false
		sm.route_visible = true
		sm.tutorial_hints = true
		get_node("/root/GameInput").reset_bindings()
		_populate_controls_list()
		sm.apply_audio_settings()
		sm.apply_language_settings()
		_load_values_from_manager()
		opt_window_mode.select(0)
		opt_resolution.select(0)
		check_vsync.set_pressed_no_signal(true)

func _on_btn_save_pressed() -> void:
	var sm := get_node("/root/SettingsManager")
	_video_previous = {"window_mode":sm.window_mode,"resolution":sm.resolution,"vsync":sm.vsync}
	var changed: bool = sm.window_mode != opt_window_mode.selected or sm.resolution != RESOLUTIONS[opt_resolution.selected]
	sm.window_mode = opt_window_mode.selected
	sm.resolution = RESOLUTIONS[opt_resolution.selected]
	sm.vsync = check_vsync.button_pressed
	sm.apply_all_settings()
	if changed:
		_video_seconds = 15.0
		_video_confirmation.popup_centered(Vector2i(480,190))
	else: _commit_settings()

func _commit_settings() -> void:
	_video_seconds = 0
	var sm := get_node("/root/SettingsManager")
	if not sm.save_settings():
		_control_hint.text = _text("Não foi possível salvar as configurações.","Settings could not be saved.")
		return
	_snapshot = sm.interface_snapshot()
	closed.emit()
	hide()

func _revert_video() -> void:
	_video_seconds = 0
	_video_confirmation.hide()
	var sm := get_node("/root/SettingsManager")
	for key in _video_previous: sm.set(key,_video_previous[key])
	sm.apply_display_settings()
	_load_values_from_manager()
	btn_save.grab_focus()

func _on_btn_back_pressed() -> void:
	_remap_action = ""
	get_node("/root/GameInput").remapping = false
	_video_seconds = 0
	_video_confirmation.hide()
	get_node("/root/SettingsManager").restore_snapshot(_snapshot)
	closed.emit()
	hide()

func _on_visibility_changed() -> void:
	if is_visible_in_tree() and is_node_ready():
		_snapshot = get_node("/root/SettingsManager").interface_snapshot()
		_load_values_from_manager()
		_populate_controls_list()
		STYLE.apply(self,get_node("/root/SettingsManager").text_scale)
		STYLE.trap_focus.call_deferred(self,false)
		tab_audio_btn.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		MenuAudio.play_click(self)
		_on_btn_back_pressed()

func _setup_comfort() -> void:
	_comfort_tab = Button.new()
	tab_controls_btn.get_parent().add_child(_comfort_tab)
	_comfort_tab.pressed.connect(func(): _select_tab(3))
	_comfort_panel = VBoxContainer.new()
	_comfort_panel.add_theme_constant_override("separation",22)
	panel_controls.get_parent().add_child(_comfort_panel)
	_comfort_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scale_option = OptionButton.new()
	for percent in [100,112,125]: _scale_option.add_item(_text("Texto: ","Text: ")+str(percent)+"%")
	_comfort_panel.add_child(_scale_option)
	_scale_option.item_selected.connect(func(index):
		var sm := get_node("/root/SettingsManager")
		sm.text_scale = [1.0,1.125,1.25][index]
		sm.interface_changed.emit()
		STYLE.apply(self,sm.text_scale))
	_motion_check = CheckBox.new()
	_route_check = CheckBox.new()
	_hints_check = CheckBox.new()
	for check in [_motion_check,_route_check,_hints_check]: _comfort_panel.add_child(check)
	_motion_check.toggled.connect(func(value): get_node("/root/SettingsManager").reduce_motion = value)
	_route_check.toggled.connect(func(value): get_node("/root/SettingsManager").route_visible = value)
	_hints_check.toggled.connect(func(value): get_node("/root/SettingsManager").tutorial_hints = value)
	_control_hint = Label.new()
	_control_hint.text = _text("Selecione um atalho para alterar. Controle: analógicos para mover e mirar; A interage, RT dispara.","Select a binding to change. Gamepad: sticks move and aim; A interacts, RT fires.")
	_control_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_controls.add_child(_control_hint)
	panel_controls.move_child(_control_hint,0)
	_video_confirmation = ConfirmationDialog.new()
	_video_confirmation.title = _text("Manter estas configurações?","Keep these settings?")
	_video_confirmation.ok_button_text = _text("Manter","Keep")
	_video_confirmation.cancel_button_text = _text("Reverter","Revert")
	add_child(_video_confirmation)
	_video_confirmation.confirmed.connect(_commit_settings)
	_video_confirmation.canceled.connect(_revert_video)

func _input(event: InputEvent) -> void:
	if _remap_action.is_empty() or not is_visible_in_tree(): return
	if not event.is_pressed() or event.is_echo(): return
	if not (event is InputEventKey or event is InputEventMouseButton): return
	get_viewport().set_input_as_handled()
	var controls := get_node("/root/GameInput")
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		_control_hint.text = _text("Alteração cancelada.","Change canceled.")
	else:
		var error: String = controls.rebind(_remap_action,event)
		_control_hint.text = error if not error.is_empty() else _text("Atalho atualizado. Salve para manter.","Binding updated. Save to keep it.")
	var selected := _remap_action
	_remap_action = ""
	controls.remapping = false
	_populate_controls_list()
	var row_index: int = controls.KEYS.keys().find(selected)
	if row_index >= 0: controls_list.get_child(row_index).get_child(1).grab_focus.call_deferred()
	STYLE.trap_focus.call_deferred(self,false)

func _process(delta: float) -> void:
	if _video_seconds <= 0: return
	_video_seconds -= delta
	_video_confirmation.dialog_text = _text("Revertendo automaticamente em %d s.","Reverting automatically in %d s.") % ceili(_video_seconds)
	if _video_seconds <= 0: _revert_video()

func _text(pt: String,en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt
