extends Control
## V1 menu/presentation, with V2-only save routing and no legacy world autoloads.
const STYLE = preload("res://ui/GameStyle.gd")
const AUDIO = preload("res://ui/MenuAudio.gd")
const V1_IMPORT = preload("res://migration/v1/V1SaveImport.gd")
const CURTAIN = preload("res://runtime/StartupCurtain.gd")
@onready var btn_new_game: Button = %BtnNewGame
@onready var btn_load_game: Button = %BtnLoadGame
@onready var btn_settings: Button = %BtnSettings
@onready var btn_quit: Button = %BtnQuit
@onready var game_title: Label = %GameTitle
@onready var sub_title: Label = %SubTitle
var btn_continue: Button
var btn_import: Button
var latest_save: Dictionary = {}
var settings: Control
var presentation: Control
var shade: ColorRect
var starting := false
var selecting_new := false
var direct_start_requested := false
var pending_import: Dictionary = {}
var selecting_import := false
var import_dialog: FileDialog

func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var launch = get_node("/root/V2Launch")
	if not launch.direct_start_consumed:
		launch.direct_start_consumed = true
		for flag in ["--sandbox", "--slice", "--no-save", "--skip-arrival"]:
			if flag in OS.get_cmdline_user_args():
				direct_start_requested = true
				break
	%LoadPanel.hide()
	latest_save = get_node("/root/V2Launch").latest_slot()
	btn_continue = Button.new()
	btn_continue.text = "CONTINUAR"
	btn_new_game.get_parent().add_child(btn_continue)
	btn_continue.visible = not latest_save.is_empty()
	btn_import = Button.new()
	btn_import.text = "IMPORTAR SAVE DA V1"
	btn_import.custom_minimum_size = btn_new_game.custom_minimum_size
	btn_import.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_new_game.get_parent().add_child(btn_import)
	btn_new_game.get_parent().move_child(btn_import,btn_load_game.get_index()+1)
	btn_continue.pressed.connect(func(): _start(str(latest_save.id), false))
	btn_new_game.pressed.connect(func(): _show_slots(true))
	btn_load_game.pressed.connect(func(): _show_slots(false))
	btn_import.pressed.connect(_choose_v1_save)
	btn_settings.pressed.connect(_open_settings)
	btn_quit.pressed.connect(func(): get_tree().quit())
	%BtnCloseLoad.pressed.connect(_close_slots)
	import_dialog = FileDialog.new()
	import_dialog.title = "Escolha um save produtivo da V1"
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.filters = PackedStringArray(["*.json ; Save Geteco V1"])
	import_dialog.file_selected.connect(_inspect_v1_save)
	import_dialog.canceled.connect(func():
		_main_enabled(true)
		btn_import.grab_focus())
	add_child(import_dialog)
	presentation = preload("res://ui/SunsetMenuPresentation.gd").new()
	add_child(presentation)
	move_child(presentation, get_node("LoadPanel").get_index())
	presentation.install(self)
	shade = ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.04, 0.75)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	move_child(shade, %LoadPanel.get_index())
	shade.hide()
	settings = preload("res://ui/SettingsMenu.tscn").instantiate()
	add_child(settings)
	settings.hide()
	settings.closed.connect(func():
		_main_enabled(true)
		btn_settings.grab_focus())
	STYLE.apply(%LoadPanel)
	AUDIO.hook_buttons(self)
	var music := AudioStreamPlayer.new()
	music.bus = AUDIO.get_music_bus_name()
	music.stream = AUDIO.get_music_stream()
	music.name = "MenuMusic"
	music.volume_db = -40
	add_child(music)
	if music.stream != null:
		music.play()
		# Entra aos poucos com o fade da apresentação, em vez de começar no volume cheio.
		create_tween().tween_property(music, "volume_db", -10.0, 2.4).set_trans(Tween.TRANS_SINE)
	STYLE.trap_focus(self, false)
	if direct_start_requested:
		starting = true
		_main_enabled(false)
		shade.show()
		sub_title.text = "ABRINDO O JOGO..."
		_start_direct.call_deferred()
	else:
		(btn_continue if btn_continue.visible else btn_new_game).grab_focus()

func _main_enabled(enabled: bool) -> void:
	for button in [btn_continue, btn_new_game, btn_load_game, btn_import, btn_settings, btn_quit]: button.disabled = not enabled

func _show_slots(new_game: bool) -> void:
	if starting: return
	selecting_new = new_game
	selecting_import = false
	_main_enabled(false)
	for child in %SlotListContainer.get_children():
		%SlotListContainer.remove_child(child)
		child.queue_free()
	%Title.text = "NOVO JOGO" if new_game else "CARREGAR JOGO"
	%LabelLoadStatus.text = "Escolha um slot vazio. Os jogos existentes serão preservados." if new_game else "Escolha o progresso para continuar."
	var enabled_options := 0
	for row in get_node("/root/V2Launch").list_slots():
		if new_game and row.id == "progress": continue
		if not new_game and not row.exists: continue
		var button := Button.new()
		button.text = row.label
		button.custom_minimum_size.y = 58
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = row.exists if new_game else not row.valid
		if not button.disabled: enabled_options += 1
		button.pressed.connect(func(): _start(str(row.id), new_game))
		%SlotListContainer.add_child(button)
		AUDIO.hook_button(button, self)
	if enabled_options == 0:
		%LabelLoadStatus.text = "Não há slot vazio disponível. Feche esta tela para preservar os jogos existentes." if new_game else "Não há progresso válido disponível para carregar."
	shade.show()
	%LoadPanel.show()
	STYLE.apply(%LoadPanel)
	STYLE.trap_focus(%LoadPanel)

func _close_slots() -> void:
	if starting: return
	%LoadPanel.hide()
	shade.hide()
	_main_enabled(true)
	STYLE.trap_focus(self, false)
	(btn_import if selecting_import else (btn_new_game if selecting_new else btn_load_game)).grab_focus()

func _choose_v1_save() -> void:
	if starting: return
	_main_enabled(false)
	import_dialog.popup_centered_ratio(.72)

func _inspect_v1_save(path: String) -> void:
	pending_import = V1_IMPORT.inspect(path)
	selecting_import = true
	selecting_new = false
	for child in %SlotListContainer.get_children():
		%SlotListContainer.remove_child(child)
		child.queue_free()
	shade.show()
	%LoadPanel.show()
	%Title.text = "IMPORTAR SAVE DA V1"
	if int(pending_import.get("read_error",OK)) != OK:
		%LabelLoadStatus.text = "O arquivo não pôde ser lido ou não contém um save V1 válido. Nenhum arquivo foi alterado."
		STYLE.trap_focus(%LoadPanel)
		return
	if pending_import.get("ready_for_publication",false) != true:
		%LabelLoadStatus.text = "Importação bloqueada com segurança: %d incompatibilidade(s), %d decisão(ões) e %d campo(s) sem conversão. O original foi preservado." % [pending_import.incompatibilities.size(),pending_import.decisions_required.size(),pending_import.unconverted_fields.size()]
		STYLE.trap_focus(%LoadPanel)
		return
	%LabelLoadStatus.text = "Conversão validada. Escolha um slot vazio para criar uma cópia V2; o save V1 continuará intacto."
	for row in get_node("/root/V2Launch").list_slots():
		if row.id == "progress" or row.exists: continue
		var button := Button.new()
		button.text = "IMPORTAR PARA " + row.label.to_upper()
		button.custom_minimum_size.y = 58
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func(): _publish_v1_import(str(row.id)))
		%SlotListContainer.add_child(button)
		AUDIO.hook_button(button,self)
	if %SlotListContainer.get_child_count()==0:
		%LabelLoadStatus.text = "Não há slot vazio. Nenhum save existente será sobrescrito."
	STYLE.apply(%LoadPanel)
	STYLE.trap_focus(%LoadPanel)

func _publish_v1_import(slot_id: String) -> void:
	var error := V1_IMPORT.publish(pending_import,slot_id,get_node("/root/V2Launch"))
	for child in %SlotListContainer.get_children(): child.queue_free()
	if error == OK:
		latest_save = get_node("/root/V2Launch").latest_slot()
		btn_continue.visible = not latest_save.is_empty()
		%Title.text = "IMPORTAÇÃO CONCLUÍDA"
		%LabelLoadStatus.text = "A cópia V2 foi criada no slot escolhido. O arquivo V1 original não foi modificado."
		pending_import = {}
	else:
		%Title.text = "IMPORTAÇÃO NÃO REALIZADA"
		%LabelLoadStatus.text = "O slot deixou de estar vazio ou a publicação falhou (%d). Nenhum save existente foi sobrescrito." % error
	STYLE.trap_focus(%LoadPanel)

func _open_settings() -> void:
	_main_enabled(false)
	settings.show()
	settings.open()

func _unhandled_input(event: InputEvent) -> void:
	if starting or not event.is_action_pressed("ui_cancel"): return
	if settings != null and settings.visible: settings.close()
	elif %LoadPanel.visible: _close_slots()
	else: return
	get_viewport().set_input_as_handled()

func _start_direct() -> void:
	var error := get_tree().change_scene_to_file("res://Main.tscn")
	if error == OK: return
	starting = false
	shade.hide()
	_main_enabled(true)
	sub_title.text = "NÃO FOI POSSÍVEL ABRIR O JOGO (%d)" % error
	STYLE.trap_focus(self,false)
	(btn_continue if btn_continue.visible else btn_new_game).grab_focus()

## Abre a tela de carregamento na raiz (sobrevive à troca de cena) e deixa ela
## desenhar antes do carregamento bloqueante da cena Main; a música sai em fade.
func _show_loading(id: String, new_game: bool) -> void:
	var region := "harbor"
	if not new_game:
		for row in get_node("/root/V2Launch").list_slots():
			if row.id == id: region = str(row.get("region", "harbor"))
	var curtain = CURTAIN.new()
	curtain.variant = CURTAIN.variant_for(region)
	get_tree().root.add_child(curtain)
	curtain.set_stage(.04, "Abrindo o save…" if not new_game else "Começando uma nova história…")
	var music := get_node_or_null("MenuMusic")
	if music != null: create_tween().tween_property(music, "volume_db", -40.0, .35)
	await get_tree().create_timer(.4).timeout
	curtain.set_stage(.08, "Carregando o mundo…")
	await get_tree().process_frame
	await get_tree().process_frame

func _start(id: String, new_game: bool) -> void:
	if starting: return
	var error: Error = get_node("/root/V2Launch").prepare(id, new_game)
	if error != OK:
		_show_slots(new_game)
		%LabelLoadStatus.text = "Este slot mudou ou não pode ser aberto. Escolha outro; nenhum save foi alterado."
		return
	starting = true
	_main_enabled(false)
	%LoadPanel.hide()
	shade.show()
	AUDIO.play_start(self)
	await _show_loading(id, new_game)
	error = get_tree().change_scene_to_file("res://Main.tscn")
	if error != OK:
		var stale = CURTAIN.existing(get_tree())
		if stale != null: stale.queue_free()
		starting = false
		_show_slots(new_game)
		%LabelLoadStatus.text = "Não foi possível abrir o jogo (%d)." % error
