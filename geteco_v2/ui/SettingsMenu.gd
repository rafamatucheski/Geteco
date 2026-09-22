extends Control

## V1 SettingsMenu layout. Barras de Música/SFX/Ambiente restauradas: V2Settings agora
## mantém os barramentos "Music"/"SFX"/"Ambient" (`runtime/Settings.gd`), como o V1 fazia
## em `systems/SettingsManager.gd`.
signal closed
const STYLE = preload("res://ui/GameStyle.gd")
var aa: OptionButton
var remap_action := ""
var snapshot: Dictionary = {}

func _ready() -> void:
	%AudioHint.hide()
	%PanelVideo.get_node("LanguageRow").hide()
	%PanelVideo.get_node("ResRow").hide()
	%OptWindowMode.clear()
	%OptWindowMode.add_item("Janela")
	%OptWindowMode.add_item("Tela cheia")
	aa = OptionButton.new()
	for label in ["Suavização: desligada", "Suavização: 2×", "Suavização: 4×", "Suavização: 8×"]: aa.add_item(label)
	%PanelVideo.add_child(aa)
	%TabAudioBtn.pressed.connect(func(): _tab(0))
	%TabVideoBtn.pressed.connect(func(): _tab(1))
	%TabControlsBtn.pressed.connect(func(): _tab(2))
	%SliderMaster.value_changed.connect(func(value):
		%LabelMasterVal.text = "%d%%" % roundi(value * 100)
		get_node("/root/V2Settings")._apply_bus_volume("Master", value))
	%SliderMusic.value_changed.connect(func(value):
		%LabelMusicVal.text = "%d%%" % roundi(value * 100)
		get_node("/root/V2Settings")._apply_bus_volume("Music", value))
	%SliderSFX.value_changed.connect(func(value):
		%LabelSFXVal.text = "%d%%" % roundi(value * 100)
		get_node("/root/V2Settings")._apply_bus_volume("SFX", value))
	%SliderAmbient.value_changed.connect(func(value):
		%LabelAmbientVal.text = "%d%%" % roundi(value * 100)
		get_node("/root/V2Settings")._apply_bus_volume("Ambient", value))
	%BtnBack.pressed.connect(close)
	%BtnSave.pressed.connect(_save)
	%BtnApply.hide()
	%BtnDefaults.text = "Restaurar controles"
	%BtnDefaults.pressed.connect(func():
		get_node("/root/GameInput").reset_bindings()
		_controls()
		%SettingsStatus.text = "Controles restaurados. Salve para manter.")
	STYLE.apply(self)

func open() -> void:
	var settings = get_node("/root/V2Settings")
	snapshot = _capture_snapshot()
	%SliderMaster.value = settings.master_volume
	%LabelMasterVal.text = "%d%%" % roundi(settings.master_volume * 100)
	%SliderMusic.value = settings.music_volume
	%LabelMusicVal.text = "%d%%" % roundi(settings.music_volume * 100)
	%SliderSFX.value = settings.sfx_volume
	%LabelSFXVal.text = "%d%%" % roundi(settings.sfx_volume * 100)
	%SliderAmbient.value = settings.ambient_volume
	%LabelAmbientVal.text = "%d%%" % roundi(settings.ambient_volume * 100)
	%OptWindowMode.select(1 if settings.fullscreen else 0)
	%CheckVSync.button_pressed = settings.vsync
	aa.select(settings.msaa)
	%SettingsStatus.text = ""
	_controls()
	_tab(0)

func _tab(index: int) -> void:
	%PanelAudio.visible = index == 0
	%PanelVideo.visible = index == 1
	%PanelControls.visible = index == 2
	STYLE.trap_focus(self)

func _controls() -> void:
	for child in %ControlsList.get_children():
		%ControlsList.remove_child(child)
		child.queue_free()
	var controls = get_node("/root/GameInput")
	for action in controls.KEYS:
		if action in ["pause_game", "inventory"]: continue
		var button := Button.new()
		button.text = controls.label(action) + " · " + controls.hint(action, true)
		button.pressed.connect(func():
			remap_action = action
			controls.remapping = true
			%SettingsStatus.text = "Pressione uma tecla · Esc cancela")
		%ControlsList.add_child(button)
	STYLE.apply(%ControlsList)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or remap_action.is_empty(): return
	if not event is InputEventKey or not event.pressed or event.echo: return
	get_viewport().set_input_as_handled()
	var controls = get_node("/root/GameInput")
	var canceled: bool = (event as InputEventKey).keycode == KEY_ESCAPE
	if not canceled:
		var error: String = controls.rebind(remap_action, event)
		if not error.is_empty():
			%SettingsStatus.text = error
			return
	remap_action = ""
	controls.remapping = false
	%SettingsStatus.text = "Remapeamento cancelado." if canceled else "Salve para manter as alterações."
	_controls()
	STYLE.trap_focus(self)

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed("ui_cancel") or event.is_echo(): return
	get_viewport().set_input_as_handled()
	if not remap_action.is_empty():
		remap_action = ""
		get_node("/root/GameInput").remapping = false
		%SettingsStatus.text = "Remapeamento cancelado."
		_controls()
		STYLE.trap_focus(self)
		return
	close()

func _save() -> void:
	var settings = get_node("/root/V2Settings")
	settings.master_volume = %SliderMaster.value
	settings.music_volume = %SliderMusic.value
	settings.sfx_volume = %SliderSFX.value
	settings.ambient_volume = %SliderAmbient.value
	settings.fullscreen = %OptWindowMode.selected == 1
	settings.vsync = %CheckVSync.button_pressed
	settings.msaa = aa.selected
	settings.apply_settings()
	var result: Error = settings.save_settings()
	if result != OK:
		%SettingsStatus.text = "Não foi possível salvar (%d)." % result
		return
	snapshot = _capture_snapshot()
	close()

func close() -> void:
	var controls = get_node("/root/GameInput")
	_restore_snapshot()
	controls.remapping = false
	remap_action = ""
	hide()
	closed.emit()

func _capture_snapshot() -> Dictionary:
	var settings = get_node("/root/V2Settings")
	return {
		"master_volume": settings.master_volume,
		"music_volume": settings.music_volume,
		"sfx_volume": settings.sfx_volume,
		"ambient_volume": settings.ambient_volume,
		"fullscreen": settings.fullscreen,
		"vsync": settings.vsync,
		"msaa": settings.msaa,
		"bindings": get_node("/root/GameInput").export_bindings().duplicate(true),
	}

func _restore_snapshot() -> void:
	if snapshot.is_empty(): return
	var settings = get_node("/root/V2Settings")
	settings.master_volume = clampf(float(snapshot.get("master_volume",settings.master_volume)),0.0,1.0)
	settings.music_volume = clampf(float(snapshot.get("music_volume",settings.music_volume)),0.0,1.0)
	settings.sfx_volume = clampf(float(snapshot.get("sfx_volume",settings.sfx_volume)),0.0,1.0)
	settings.ambient_volume = clampf(float(snapshot.get("ambient_volume",settings.ambient_volume)),0.0,1.0)
	settings.fullscreen = bool(snapshot.get("fullscreen",settings.fullscreen))
	settings.vsync = bool(snapshot.get("vsync",settings.vsync))
	settings.msaa = clampi(int(snapshot.get("msaa",settings.msaa)),0,3)
	settings.apply_settings()
	get_node("/root/GameInput").import_bindings(snapshot.get("bindings",{}))
