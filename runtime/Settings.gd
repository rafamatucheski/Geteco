extends Node
## Preferências do jogador (user://settings.cfg): áudio, vídeo e interface.
## Aplica o que é global (barramentos, janela, viewport, sombras, FPS) e avisa por
## `applied` quem depende do mundo (brilho vai no WorldEnvironment do ProductionWorld).
signal applied

var master_volume := .8
## Barramentos "Música"/"SFX"/"Ambiente" trazidos de volta de `systems/SettingsManager.gd`
## (V1): antes só existia o bus 0 (Master), então os sliders de música/efeitos/ambiente
## do menu não tinham o que controlar e foram escondidos em `ui/SettingsMenu.gd`.
var music_volume := .8
var sfx_volume := 1.0
var ambient_volume := 1.0
## Silencia tudo quando a janela perde o foco (alt-tab).
var mute_unfocused := false

## 0 janela, 1 tela cheia, 2 tela cheia exclusiva.
var window_mode := 0
## Índice em RESOLUTIONS; só vale em janela (tela cheia usa a do monitor).
var resolution := 0
var vsync := true
var msaa := 1
## Escala da renderização 3D (a interface fica sempre nítida). Abaixo de 100% usa FSR.
var render_scale := 1.0
## Índice em FPS_LIMITS. O padrão é 60, o limite que o projeto sempre usou.
var fps_limit := 1
## 0 baixa, 1 média, 2 alta.
var shadow_quality := 1
## Ajuste de brilho do mundo: 1,0 é o original.
var brightness := 1.0
var show_fps := false
## 0 original, 1 diagonal exterior framing inspired by the compact HUD concept.
var camera_view := 0

const RESOLUTIONS := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080), Vector2i(2560,1440)]
const FPS_LIMITS := [30, 60, 120, 144, 0]
const SHADOW_ATLAS := [2048, 4096, 8192]
## "Média" é exatamente o padrão do renderer Mobile (atlas 4096, filtro duro): quem não
## mexe na opção vê o jogo como sempre foi.
const SHADOW_FILTER := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW]

## Compatibilidade: código e saves antigos falam em "fullscreen".
var fullscreen: bool:
	get: return window_mode != 0
	set(value): window_mode = 1 if value else 0

var _fps_layer: CanvasLayer
var _fps_label: Label
var _focus_muted := false
var _fps_previous_usec := 0
var _fps_clock := 0.0
var _fps_peak := 0.0

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
		mute_unfocused = bool(config.get_value("audio","mute_unfocused",false))
		# Arquivo antigo só tinha "fullscreen".
		var legacy_mode := 1 if bool(config.get_value("display","fullscreen",false)) else 0
		window_mode = clampi(int(config.get_value("display","window_mode",legacy_mode)),0,2)
		resolution = clampi(int(config.get_value("display","resolution",0)),0,RESOLUTIONS.size()-1)
		vsync = bool(config.get_value("display","vsync",true))
		msaa = clampi(int(config.get_value("display","msaa",1)),0,3)
		render_scale = clampf(float(config.get_value("display","render_scale",1.0)),.5,1.0)
		fps_limit = clampi(int(config.get_value("display","fps_limit",1)),0,FPS_LIMITS.size()-1)
		shadow_quality = clampi(int(config.get_value("display","shadow_quality",1)),0,2)
		brightness = clampf(float(config.get_value("display","brightness",1.0)),.6,1.6)
		show_fps = bool(config.get_value("display","show_fps",false))
		camera_view = clampi(int(config.get_value("display","camera_view",0)), 0, 1)
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
	var view := root_view()
	view.msaa_3d = msaa
	view.scaling_3d_scale = render_scale
	# FSR 1 reconstrói bordas melhor que o bilinear quando a escala cai.
	view.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < .999 else Viewport.SCALING_3D_MODE_BILINEAR
	Engine.max_fps = FPS_LIMITS[fps_limit]
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[shadow_quality], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTER[shadow_quality])
	RenderingServer.positional_soft_shadow_filter_set_quality(SHADOW_FILTER[shadow_quality])
	_update_fps_overlay()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		# Android owns the surface size, including fold/unfold transitions.
		if not OS.has_feature("android"):
			match window_mode:
				1: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				2: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
				_: _apply_windowed()
	applied.emit()

func _apply_windowed() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var target: Vector2i = RESOLUTIONS[resolution]
	# Janela maior que a área útil do monitor ficaria cortada.
	var usable := DisplayServer.screen_get_usable_rect()
	if usable.size.x > 0: target = Vector2i(mini(target.x, usable.size.x), mini(target.y, usable.size.y))
	if DisplayServer.window_get_size() != target:
		DisplayServer.window_set_size(target)
		DisplayServer.window_set_position(usable.position + (usable.size - target) / 2)

## Brilho do mundo: chamado pelo ProductionWorld no ambiente que ele cria.
func apply_environment(environment: Environment) -> void:
	if environment == null: return
	environment.adjustment_enabled = not is_equal_approx(brightness, 1.0)
	environment.adjustment_brightness = brightness

func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1: return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, .0001)))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mute_unfocused:
		_focus_muted = true
		AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _focus_muted:
		_focus_muted = false
		AudioServer.set_bus_mute(0, false)

func _update_fps_overlay() -> void:
	_fps_previous_usec = 0
	_fps_clock = 0.0
	_fps_peak = 0.0
	if show_fps and _fps_layer == null:
		_fps_layer = CanvasLayer.new()
		_fps_layer.layer = 127
		_fps_label = Label.new()
		_fps_label.add_theme_font_size_override("font_size", 14)
		_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, .8))
		_fps_label.add_theme_constant_override("outline_size", 4)
		_fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_fps_label.position = Vector2(-260, 8)
		_fps_label.size = Vector2(250, 20)
		_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fps_layer.add_child(_fps_label)
		add_child(_fps_layer)
	elif not show_fps and _fps_layer != null:
		_fps_layer.queue_free()
		_fps_layer = null
		_fps_label = null
	set_process(show_fps)

func _process(_delta: float) -> void:
	if _fps_label == null: return
	var now := Time.get_ticks_usec()
	if _fps_previous_usec > 0: _fps_peak = maxf(_fps_peak, (now - _fps_previous_usec) / 1000.0)
	_fps_previous_usec = now
	_fps_clock += _delta
	if _fps_clock < 1.0: return
	var fps := Engine.get_frames_per_second()
	_fps_label.text = "%d FPS · pico %.1f ms" % [fps, _fps_peak]
	_fps_clock = 0.0
	_fps_peak = 0.0

func root_view() -> Window: return get_tree().root

func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("audio","master_volume",master_volume)
	config.set_value("audio","music_volume",music_volume)
	config.set_value("audio","sfx_volume",sfx_volume)
	config.set_value("audio","ambient_volume",ambient_volume)
	config.set_value("audio","mute_unfocused",mute_unfocused)
	config.set_value("display","window_mode",window_mode)
	config.set_value("display","fullscreen",fullscreen)
	config.set_value("display","resolution",resolution)
	config.set_value("display","vsync",vsync)
	config.set_value("display","msaa",msaa)
	config.set_value("display","render_scale",render_scale)
	config.set_value("display","fps_limit",fps_limit)
	config.set_value("display","shadow_quality",shadow_quality)
	config.set_value("display","brightness",brightness)
	config.set_value("display","show_fps",show_fps)
	config.set_value("display","camera_view",camera_view)
	config.set_value("controls","bindings",get_node("/root/GameInput").export_bindings())
	config.set_value("controls","gamepad_bindings",get_node("/root/GameInput").export_gamepad_bindings())
	config.set_value("controls","controller_layout",get_node("/root/GameInput").controller_layout)
	return config.save("user://settings.cfg")
