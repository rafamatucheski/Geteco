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
	
	var err := config.save(_settings_path)
	if err == OK:
		settings_saved.emit()
		return true
	push_error("Falha ao salvar configurações em %s: código %d" % [_settings_path, err])
	return false

func apply_all_settings() -> void:
	apply_audio_settings()
	apply_display_settings()

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
		{"action": &"ui_up", "label": "Mover para Cima / Acelerar"},
		{"action": &"ui_down", "label": "Mover para Baixo / Ré"},
		{"action": &"ui_left", "label": "Mover para Esquerda / Virar"},
		{"action": &"ui_right", "label": "Mover para Direita / Virar"},
		{"action": &"sprint", "label": "Correr (Sprint)"},
		{"action": &"interact", "label": "Interagir / Entrar no Veículo"},
		{"action": &"radio_next", "label": "Próxima Estação de Rádio"},
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
					if btn == MOUSE_BUTTON_LEFT: btn_str = "Clique Esquerdo"
					elif btn == MOUSE_BUTTON_RIGHT: btn_str = "Clique Direito"
					elif btn == MOUSE_BUTTON_MIDDLE: btn_str = "Clique do Meio"
					if not keys.has(btn_str):
						keys.append(btn_str)
		result.append({
			"action": act,
			"label": entry["label"],
			"keys": " / ".join(keys) if not keys.is_empty() else "Nenhuma"
		})
	
	# Adicionar ações globais fixas documentadas
	result.append({"action": &"fire", "label": "Atirar / Disparar Arma", "keys": "Clique Esquerdo"})
	result.append({"action": &"weapon_wheel", "label": "Roda de Armas", "keys": "Q / Roda do Mouse"})
	result.append({"action": &"pause", "label": "Menu de Pausa", "keys": "ESC"})
	
	return result
