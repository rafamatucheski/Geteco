extends Node
var master_volume := .8
## Barramentos "Música"/"SFX"/"Ambiente" trazidos de volta de `systems/SettingsManager.gd`
## (V1): antes só existia o bus 0 (Master), então os sliders de música/efeitos/ambiente
## do menu não tinham o que controlar e foram escondidos em `ui/SettingsMenu.gd`.
var music_volume := .8
var sfx_volume := 1.0
var ambient_volume := 1.0
var fullscreen := false
var vsync := true
var msaa := 1
func _enter_tree() -> void:
	_setup_audio_buses()
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_buses()
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		master_volume = clampf(float(config.get_value("audio","master_volume",.8)),0,1)
		music_volume = clampf(float(config.get_value("audio","music_volume",.8)),0,1)
		sfx_volume = clampf(float(config.get_value("audio","sfx_volume",1.0)),0,1)
		ambient_volume = clampf(float(config.get_value("audio","ambient_volume",1.0)),0,1)
		fullscreen = bool(config.get_value("display","fullscreen",false))
		vsync = bool(config.get_value("display","vsync",true))
		msaa = clampi(int(config.get_value("display","msaa",1)),0,3)
	apply_settings()
## Cria "Music", "SFX" e "Ambient" se ainda não existirem (idempotente: chamado tanto no
## `_enter_tree` do autoload, antes de qualquer outro nó tocar som, quanto no `_ready`).
func _setup_audio_buses() -> void:
	for bus_name in ["Music", "SFX", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var new_idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(new_idx, bus_name)
			AudioServer.set_bus_send(new_idx, "Master")
func apply_settings() -> void:
	_apply_bus_volume("Master", master_volume)
	_apply_bus_volume("Music", music_volume)
	_apply_bus_volume("SFX", sfx_volume)
	_apply_bus_volume("Ambient", ambient_volume)
	root_view().msaa_3d = msaa
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1: return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, .0001)))
func root_view() -> Window: return get_tree().root
func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("audio","master_volume",master_volume)
	config.set_value("audio","music_volume",music_volume)
	config.set_value("audio","sfx_volume",sfx_volume)
	config.set_value("audio","ambient_volume",ambient_volume)
	config.set_value("display","fullscreen",fullscreen)
	config.set_value("display","vsync",vsync)
	config.set_value("display","msaa",msaa)
	config.set_value("controls","bindings",get_node("/root/GameInput").export_bindings())
	return config.save("user://settings.cfg")
