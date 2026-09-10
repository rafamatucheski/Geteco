extends Node

## Gerenciador Central de Configurações
## Persiste dados em user://settings.cfg via ConfigFile, separado do save do jogo.
## Aplica barramentos de áudio reais no AudioServer e opções de tela no DisplayServer.

const SETTINGS_PATH := "user://settings.cfg"

var _settings_path := SETTINGS_PATH

# Sinais para sincronizar UI se necessário
signal settings_saved()
signal audio_settings_changed()
signal display_settings_changed()

# Valores em memória
var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0

var window_mode: int = 0  # 0: Janela, 1: Tela Cheia, 2: Tela Cheia Exclusiva
var resolution: Vector2i = Vector2i(1280, 720)
var vsync: bool = true

var language: String = "pt_BR"
signal language_changed(locale: String)

func _enter_tree() -> void:
	_setup_audio_buses()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_buses()
	_resolve_settings_path()
	load_settings()
	apply_all_settings()

func _resolve_settings_path() -> void:
	var preferred_directory := ProjectSettings.globalize_path("user://")
	if _directory_is_writable(preferred_directory):
		return
	if DisplayServer.get_name() != "headless":
		return
	var fallback_directory := OS.get_temp_dir().path_join("gta_topdown_clone_headless")
	if DirAccess.make_dir_recursive_absolute(fallback_directory) == OK and _directory_is_writable(fallback_directory):
		_settings_path = fallback_directory.path_join("settings.cfg")

func _directory_is_writable(absolute_directory: String) -> bool:
	var probe_path := absolute_directory.path_join(".settings_write_probe.tmp")
	var probe := FileAccess.open(probe_path, FileAccess.WRITE)
	if probe == null:
		return false
	probe.close()
	DirAccess.remove_absolute(probe_path)
	return true

func _setup_audio_buses() -> void:
	# Garante que os barramentos 'Music' e 'SFX' existam no AudioServer
	var bus_music_idx := AudioServer.get_bus_index("Music")
	if bus_music_idx == -1:
		AudioServer.add_bus()
		var new_idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(new_idx, "Music")
		AudioServer.set_bus_send(new_idx, "Master")
	
	var bus_sfx_idx := AudioServer.get_bus_index("SFX")
	if bus_sfx_idx == -1:
		AudioServer.add_bus()
		var new_idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(new_idx, "SFX")
		AudioServer.set_bus_send(new_idx, "Master")

func load_settings() -> bool:
	var config := ConfigFile.new()
	var err := config.load(_settings_path)
	if err != OK:
		# Arquivo ainda não existe, manter padrões
		return false
	
	master_volume = clampf(config.get_value("audio", "master_volume", 1.0), 0.0, 1.0)
	music_volume = clampf(config.get_value("audio", "music_volume", 0.8), 0.0, 1.0)
	sfx_volume = clampf(config.get_value("audio", "sfx_volume", 1.0), 0.0, 1.0)
	
	window_mode = clampi(int(config.get_value("display", "window_mode", 0)), 0, 2)
	var res_w: int = int(config.get_value("display", "resolution_width", 1280))
	var res_h: int = int(config.get_value("display", "resolution_height", 720))
	resolution = Vector2i(maxi(640, res_w), maxi(480, res_h))
	vsync = bool(config.get_value("display", "vsync", true))

	var loaded_language := String(config.get_value("locale", "language", "pt_BR"))
	language = loaded_language if Localization.is_supported(loaded_language) else "pt_BR"

	return true

func save_settings() -> bool:
	var config := ConfigFile.new()
	
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	
	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "resolution_width", resolution.x)
	config.set_value("display", "resolution_height", resolution.y)
	config.set_value("display", "vsync", vsync)

	config.set_value("locale", "language", language)

	var err := config.save(_settings_path)
	if err == OK:
		settings_saved.emit()
		return true
	push_error("Falha ao salvar configurações em %s: código %d" % [_settings_path, err])
	return false

func apply_all_settings() -> void:
	apply_audio_settings()
	apply_display_settings()
	apply_language_settings()

func apply_language_settings() -> void:
	TranslationServer.set_locale(language)
	language_changed.emit(language)

func set_language(locale: String) -> void:
	if not Localization.is_supported(locale):
		return
	language = locale
	apply_language_settings()

func apply_audio_settings() -> void:
	_apply_bus_volume("Master", master_volume)
	_apply_bus_volume("Music", music_volume)
	_apply_bus_volume("SFX", sfx_volume)
	audio_settings_changed.emit()

func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	if linear <= 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))

func apply_display_settings() -> void:
	# Fullscreen keeps the monitor's native mode, but renders at the chosen
	# resolution. Windowed mode retains the existing responsive canvas scaling.
	var window := get_tree().root
	window.content_scale_size = resolution if window_mode != 0 else Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if window_mode != 0 else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	# Não aplicar modos gráficos agressivos se estiver em ambiente headless
	if DisplayServer.get_name() == "headless":
		return
	
	match window_mode:
		0: # Janela
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
			# Centralizar janela na tela principal se possível
			var screen_size := DisplayServer.screen_get_size()
			var win_pos := (screen_size - resolution) / 2
			DisplayServer.window_set_position(win_pos)
		1: # Tela Cheia (Janela sem bordas / borderless)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2: # Tela Cheia Exclusiva
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# Mantém o teto de FPS casado com o tick de física, inclusive depois de o
	# jogador trocar de modo de janela ou de resolução. Render mais rápido que a
	# física não deixa o movimento mais suave: os frames que não pegam tick nenhum
	# redesenham o mundo na mesma posição e o seguinte anda o dobro, o que se vê
	# como o carro vibrando para frente e para trás. Derivado de
	# physics_ticks_per_second em vez de escrito 60 na mão, para não descolar se o
	# tick rate mudar.
	#
	# Esta é a metade em runtime de um par de ajustes; a outra metade vive em
	# project.godot (`run/max_fps`, `physics/common/physics_interpolation=true` e
	# `physics/common/physics_jitter_fix=0.0`). O porquê está registrado AQUI e no
	# histórico do git porque o Godot reescreve project.godot a cada --import e
	# descarta os comentários daquele arquivo.
	#
	# Medido em tests/measure_motion_judder_isolated.gd (jerk relativo do avanço
	# aparente na tela; 0 é uniforme, ~2 é alternar parado/dobro):
	#   FPS livre (160Hz), sem interpolação ... jerk 2.007  (62% dos frames sem tick)
	#   64 FPS, sem interpolação ............. jerk 0.132
	#   60 FPS, sem interpolação ............. jerk 0.000
	#   64 FPS, com interpolação ............. jerk 0.004
	# O teto sozinho basta enquanto o jogo sustenta 60; a interpolação é o que
	# cobre as quedas de FPS, que nesta base existem (ver
	# tests/diagnose_frame_hitches.gd).
	Engine.max_fps = Engine.physics_ticks_per_second
	
	display_settings_changed.emit()

func set_master_volume(val: float) -> void:
	master_volume = clampf(val, 0.0, 1.0)
	_apply_bus_volume("Master", master_volume)

func set_music_volume(val: float) -> void:
	music_volume = clampf(val, 0.0, 1.0)
	_apply_bus_volume("Music", music_volume)

func set_sfx_volume(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)
	_apply_bus_volume("SFX", sfx_volume)

func set_window_mode(mode: int) -> void:
	window_mode = clampi(mode, 0, 2)
	apply_display_settings()

func set_resolution(res: Vector2i) -> void:
	resolution = res
	apply_display_settings()

func set_vsync(enabled: bool) -> void:
	vsync = enabled
	apply_display_settings()

func get_controls_mapping() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actions: Array[Dictionary] = [
		{"action": &"ui_up", "label": tr("CONTROL_MOVE_UP")},
		{"action": &"ui_down", "label": tr("CONTROL_MOVE_DOWN")},
		{"action": &"ui_left", "label": tr("CONTROL_MOVE_LEFT")},
		{"action": &"ui_right", "label": tr("CONTROL_MOVE_RIGHT")},
		{"action": &"sprint", "label": tr("CONTROL_SPRINT")},
		{"action": &"interact", "label": tr("CONTROL_INTERACT")},
		{"action": &"radio_next", "label": tr("CONTROL_RADIO_NEXT")},
	]
	
	for entry in actions:
		var act: StringName = entry["action"]
		var keys: Array[String] = []
		if InputMap.has_action(act):
			for event in InputMap.action_get_events(act):
				if event is InputEventKey:
					var key_str := OS.get_keycode_string((event as InputEventKey).physical_keycode)
					if key_str.is_empty():
						key_str = OS.get_keycode_string((event as InputEventKey).keycode)
					if not key_str.is_empty() and not keys.has(key_str):
						keys.append(key_str)
				elif event is InputEventMouseButton:
					var btn := (event as InputEventMouseButton).button_index
					var btn_str := "Mouse %d" % btn
					if btn == MOUSE_BUTTON_LEFT: btn_str = tr("CONTROL_KEY_LEFT_CLICK")
					elif btn == MOUSE_BUTTON_RIGHT: btn_str = tr("CONTROL_KEY_RIGHT_CLICK")
					elif btn == MOUSE_BUTTON_MIDDLE: btn_str = tr("CONTROL_KEY_MIDDLE_CLICK")
					if not keys.has(btn_str):
						keys.append(btn_str)
		result.append({
			"action": act,
			"label": entry["label"],
			"keys": " / ".join(keys) if not keys.is_empty() else tr("CONTROL_KEY_NONE")
		})
	
	# Adicionar ações globais fixas documentadas
	result.append({"action": &"fire", "label": tr("CONTROL_FIRE"), "keys": tr("CONTROL_KEY_LEFT_CLICK")})
	result.append({"action": &"reload", "label": tr("CONTROL_RELOAD"), "keys": "R"})
	result.append({"action": &"weapon_wheel", "label": tr("CONTROL_WEAPON_WHEEL"), "keys": "Q / " + tr("CONTROL_KEY_MOUSE_WHEEL")})
	result.append({"action": &"pause", "label": tr("CONTROL_PAUSE"), "keys": "ESC"})
	
	return result
