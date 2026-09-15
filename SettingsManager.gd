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
# Ambiente (chuva, mar, cidade, pássaros) tem canal próprio: antes ele dividia o
# controle com a música ou com os efeitos, e baixar a trilha calava a cidade.
var ambient_volume: float = 1.0

var window_mode: int = 0  # 0: Janela, 1: Tela Cheia, 2: Tela Cheia Exclusiva
var resolution: Vector2i = Vector2i(1280, 720)
var vsync: bool = true
var msaa_3d: int = Viewport.MSAA_2X

var text_scale := 1.0
var reduce_motion := false
var route_visible := true
var tutorial_hints := true
signal interface_changed

var language: String = "pt_BR"
signal language_changed(locale: String)

func _enter_tree() -> void:
	_setup_audio_buses()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(preload("res://RenderQuality.gd").new())
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
	# Garante que os barramentos 'Music', 'SFX' e 'Ambient' existam no AudioServer.
	# Criados aqui, no _enter_tree do autoload, ficam antes dos barramentos privados
	# de chuva e vento, que precisam enviar para um barramento anterior na mixagem.
	for bus_name in ["Music", "SFX", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var new_idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(new_idx, bus_name)
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
	ambient_volume = clampf(config.get_value("audio", "ambient_volume", 1.0), 0.0, 1.0)

	window_mode = clampi(int(config.get_value("display", "window_mode", 0)), 0, 2)
	var res_w: int = int(config.get_value("display", "resolution_width", 1280))
	var res_h: int = int(config.get_value("display", "resolution_height", 720))
	resolution = Vector2i(maxi(640, res_w), maxi(480, res_h))
	vsync = bool(config.get_value("display", "vsync", true))
	msaa_3d = clampi(int(config.get_value("display", "msaa_3d", Viewport.MSAA_2X)), 0, 3)

	var loaded_language := String(config.get_value("locale", "language", "pt_BR"))
	language = loaded_language if Localization.is_supported(loaded_language) else "pt_BR"

	text_scale = clampf(float(config.get_value("interface","text_scale",1.0)),1.0,1.25)
	reduce_motion = bool(config.get_value("interface","reduce_motion",false))
	route_visible = bool(config.get_value("interface","route_visible",true))
	tutorial_hints = bool(config.get_value("interface","tutorial_hints",true))
	var controls := get_node_or_null("/root/GameInput")
	# Na inicialização o GameInput ainda não registrou suas ações. Ele importa
	# as teclas no próprio _ready; recarregamentos posteriores podem aplicar aqui.
	if controls != null and controls.is_node_ready(): controls.import_bindings(config.get_value("controls","bindings",{}))

	return true

func save_settings() -> bool:
	var config := ConfigFile.new()
	
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "ambient_volume", ambient_volume)

	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "resolution_width", resolution.x)
	config.set_value("display", "resolution_height", resolution.y)
	config.set_value("display", "vsync", vsync)
	config.set_value("display", "msaa_3d", msaa_3d)

	config.set_value("locale", "language", language)

	config.set_value("interface","text_scale",text_scale)
	config.set_value("interface","reduce_motion",reduce_motion)
	config.set_value("interface","route_visible",route_visible)
	config.set_value("interface","tutorial_hints",tutorial_hints)
	var controls := get_node_or_null("/root/GameInput")
	if controls != null: config.set_value("controls","bindings",controls.export_bindings())
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
	interface_changed.emit()

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
	_apply_bus_volume("Ambient", ambient_volume)
	_apply_bus_volume("Dialogue", sfx_volume)
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
	# Resolution is the remembered window size. Fullscreen uses native output;
	# keep the same logical canvas so switching modes cannot change UI/game zoom.
	var window := get_tree().root
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	# Não aplicar modos gráficos agressivos se estiver em ambiente headless
	if DisplayServer.get_name() == "headless":
		Engine.max_fps = Engine.physics_ticks_per_second
		display_settings_changed.emit()
		return
	
	var screen := DisplayServer.window_get_current_screen()
	match window_mode:
		0: # Janela
			resolution = fit_window_resolution(resolution)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(resolution)
			# Respect the current monitor's origin and taskbar, including monitors
			# positioned to the left of the primary display.
			var usable := DisplayServer.screen_get_usable_rect(screen)
			var win_pos := usable.position + (usable.size - resolution) / 2
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

func fit_window_resolution(requested: Vector2i) -> Vector2i:
	var valid := Vector2i(maxi(640, requested.x), maxi(480, requested.y))
	if DisplayServer.get_name() == "headless":
		return valid
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	# Leave room for window decorations; a monitor-sized window can be promoted
	# back to fullscreen by Windows when leaving exclusive fullscreen.
	var available := Vector2i(maxi(1, usable.size.x - 32), maxi(1, usable.size.y - 64))
	var scale := minf(1.0, minf(float(available.x) / valid.x, float(available.y) / valid.y))
	return Vector2i(Vector2(valid) * scale)

func set_master_volume(val: float) -> void:
	master_volume = clampf(val, 0.0, 1.0)
	_apply_bus_volume("Master", master_volume)

func set_music_volume(val: float) -> void:
	music_volume = clampf(val, 0.0, 1.0)
	_apply_bus_volume("Music", music_volume)

func set_sfx_volume(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)
	_apply_bus_volume("SFX", sfx_volume)
	_apply_bus_volume("Dialogue", sfx_volume)

func set_ambient_volume(val: float) -> void:
	ambient_volume = clampf(val, 0.0, 1.0)
	_apply_bus_volume("Ambient", ambient_volume)

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
	var controls := get_node_or_null("/root/GameInput")
	var result: Array[Dictionary] = []
	if controls != null:
		for action in controls.KEYS:
			result.append({"action":action,"label":controls.label(action),"keys":controls.hint(action,true)})
	return result

func interface_snapshot() -> Dictionary:
	var data := {}
	for key in ["master_volume","music_volume","sfx_volume","ambient_volume","window_mode","resolution","vsync","msaa_3d","language","text_scale","reduce_motion","route_visible","tutorial_hints"]:
		data[key] = get(key)
	data["bindings"] = get_node("/root/GameInput").export_bindings()
	return data

func restore_snapshot(data: Dictionary) -> void:
	for key in data:
		if key != "bindings": set(key,data[key])
	get_node("/root/GameInput").import_bindings(data.get("bindings",{}))
	apply_all_settings()
