extends Node
## Preferências do jogador (user://settings.cfg): áudio, vídeo e interface.
## Aplica o que é global (barramentos, janela, viewport, sombras, FPS) e avisa por
## `applied` quem depende do mundo (brilho vai no WorldEnvironment do ProductionWorld).
signal applied
signal voice_language_changed(language: String)
signal text_language_changed(language: String)

const VOICE_LANGUAGES := ["pt_BR", "en"]
const TEXT_LANGUAGES := ["pt_BR", "en"]
var text_language := "pt_BR":
	set(value):
		var language := "en" if value.to_lower().replace("-", "_").get_slice("_", 0) == "en" else "pt_BR"
		if text_language == language: return
		text_language = language
		TranslationServer.set_locale(language)
		text_language_changed.emit(language)
## Dublagem é independente do idioma dos textos e preserva o português de saves antigos.
var voice_language := "pt_BR":
	set(value):
		var language := "en" if value.to_lower().replace("-", "_").get_slice("_", 0) == "en" else "pt_BR"
		if voice_language == language: return
		voice_language = language
		voice_language_changed.emit(language)

var master_volume := .8
## Barramentos "Música"/"SFX"/"Ambiente" trazidos de volta de `systems/SettingsManager.gd`
## (V1): antes só existia o bus 0 (Master), então os sliders de música/efeitos/ambiente
## do menu não tinham o que controlar e foram escondidos em `ui/SettingsMenu.gd`.
var music_volume := .8
var sfx_volume := 1.0
var ambient_volume := 1.0
## Ganho da mixagem antes do slider: 100% precisa dar presença a motores e efeitos.
const SFX_GAIN_DB := 10.0
## Silencia tudo quando a janela perde o foco (alt-tab).
var mute_unfocused := false

## 0 janela, 1 tela cheia, 2 tela cheia exclusiva.
var window_mode := 0
## Índice em RESOLUTIONS; só vale em janela (tela cheia usa a do monitor).
var resolution := 0
var vsync := true
var msaa := 1
## 8x custava 12-23 ms de GPU com chama/explosão na tela (log de 2026-10-01, 1080p): teto de 4x.
const MAX_MSAA := 2
## Escala da renderização 3D (a interface fica sempre nítida). Abaixo de 100% usa FSR.
var render_scale := 1.0
## Índice em FPS_LIMITS. O padrão é 60, o limite que o projeto sempre usou.
var fps_limit := 1
## 0 baixa, 1 média, 2 alta.
var shadow_quality := 1
const GRAPHICS := preload("res://runtime/GraphicsOptions.gd")
## AA: MSAA, FXAA, SMAA. Upscale: bilinear, FSR 1.
var aa_mode := 0
var upscale_mode := 1
var shadow_distance := 1
var anisotropy := 3
var reflection_quality := 1
var detail_quality := 1
var ssao := false
var volumetric_fog := false
var glow := true
var glow_strength := .75
## Ajuste de brilho do mundo: 1,0 é o original.
var brightness := 1.0
var show_fps := false
## 0 original, 1 diagonal exterior framing inspired by the compact HUD concept.
var camera_view := 1

const RESOLUTIONS := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080), Vector2i(2560,1440),
	# Novas entradas ficam no fim: o config salva o índice, então reordenar mudaria a escolha de quem já jogou.
	Vector2i(1920,1200), Vector2i(2560,1080), Vector2i(3440,1440), Vector2i(3840,1600), Vector2i(5120,1440)]
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
	apply_pipeline_cache_policy()
	_setup_audio_buses()
	preload("res://runtime/Localization.gd").install()
	load_settings()
	TranslationServer.set_locale(text_language)
	apply_settings()
	get_tree().node_added.connect(_graphics_node_added)

func _graphics_node_added(node: Node) -> void:
	if node.is_in_group(GRAPHICS.DETAIL_GROUP):
		_apply_detail.call_deferred(weakref(node))

func _apply_detail(reference: WeakRef) -> void:
	var node: Node = reference.get_ref()
	if is_instance_valid(node): GRAPHICS.apply_detail(node,detail_quality)

func graphics_preset() -> int:
	for index in GRAPHICS.PRESETS.size():
		var matches := true
		for key in GRAPHICS.KEYS:
			if get(key) != GRAPHICS.PRESETS[index][key]:
				matches = false
				break
		if matches: return index + 1
	return 0

func set_graphics_preset(index: int) -> void:
	if index < 1 or index > GRAPHICS.PRESETS.size(): return
	for key in GRAPHICS.KEYS: set(key,GRAPHICS.PRESETS[index-1][key])
	apply_settings()

func shadow_distance_metres() -> float:
	return [40.0,55.0,80.0][clampi(shadow_distance,0,2)]

## Teste roda com --isolated-save-root=<pasta temporária> (tools/run_core_suite.sh,
## tests/run_suite.ps1): as preferências ficam lá. Antes o teste lia o settings.cfg do jogador e
## o idioma do texto dele mudava o resultado (comparação de frase em português falhava em inglês).
static func default_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--isolated-save-root="):
			return argument.trim_prefix("--isolated-save-root=").replace("\\", "/").path_join("settings.cfg")
	return "user://settings.cfg"

func load_settings(path := "") -> Error:
	if path.is_empty(): path = default_path()
	var config := ConfigFile.new()
	var result := config.load(path)
	if result == OK:
		master_volume = clampf(float(config.get_value("audio","master_volume",.8)),0,1)
		music_volume = clampf(float(config.get_value("audio","music_volume",.8)),0,1)
		sfx_volume = clampf(float(config.get_value("audio","sfx_volume",1.0)),0,1)
		ambient_volume = clampf(float(config.get_value("audio","ambient_volume",1.0)),0,1)
		mute_unfocused = bool(config.get_value("audio","mute_unfocused",false))
		voice_language = str(config.get_value("audio","voice_language","pt_BR"))
		text_language = str(config.get_value("interface","text_language","pt_BR"))
		# Arquivo antigo só tinha "fullscreen".
		var legacy_mode := 1 if bool(config.get_value("display","fullscreen",false)) else 0
		window_mode = clampi(int(config.get_value("display","window_mode",legacy_mode)),0,2)
		resolution = clampi(int(config.get_value("display","resolution",0)),0,RESOLUTIONS.size()-1)
		vsync = bool(config.get_value("display","vsync",true))
		msaa = clampi(int(config.get_value("display","msaa",1)),0,MAX_MSAA)
		render_scale = clampf(float(config.get_value("display","render_scale",1.0)),.5,1.0)
		fps_limit = clampi(int(config.get_value("display","fps_limit",1)),0,FPS_LIMITS.size()-1)
		shadow_quality = clampi(int(config.get_value("display","shadow_quality",1)),0,2)
		brightness = clampf(float(config.get_value("display","brightness",1.0)),.6,1.6)
		show_fps = bool(config.get_value("display","show_fps",false))
		camera_view = clampi(int(config.get_value("display","camera_view",1)), 0, 1)
		for key in ["aa_mode","upscale_mode","shadow_distance","anisotropy","reflection_quality","detail_quality"]:
			var maximum := 4 if key == "anisotropy" else (1 if key == "upscale_mode" else 2)
			set(key,clampi(int(config.get_value("graphics",key,GRAPHICS.PRESETS[1][key])),0,maximum))
		# Legacy TAA (3) maps to SMAA (2), FSR2 (2) to FSR1 (1); SSR is no longer loaded.
		for key in ["ssao","volumetric_fog","glow"]:
			set(key,bool(config.get_value("graphics",key,GRAPHICS.PRESETS[1][key])))
		glow_strength = clampf(float(config.get_value("graphics","glow_strength",.75)),0.0,1.5)
	return result

func _exit_tree() -> void:
	# Scripted translations must leave the server before script runtime teardown.
	if name == "V2Settings": preload("res://runtime/Localization.gd").uninstall()

## Cria "Music", "SFX" e "Ambient" se ainda não existirem (idempotente: chamado tanto no
## `_enter_tree` do autoload, antes de qualquer outro nó tocar som, quanto no `_ready`).
func _setup_audio_buses() -> void:
	for bus_name in ["Music", "SFX", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var new_idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(new_idx, bus_name)
			AudioServer.set_bus_send(new_idx, "Master")
	_setup_audio_limiter("SFX", "SFXPresence", SFX_GAIN_DB, -3.0)
	_setup_audio_limiter("Master", "OutputProtection", 0.0, -1.0)

func _setup_audio_limiter(bus_name: String, effect_name: String, gain_db: float, ceiling_db: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	# _enter_tree e _ready chamam o setup; não empilhar o ganho a cada chamada.
	for effect_index in AudioServer.get_bus_effect_count(idx):
		var existing := AudioServer.get_bus_effect(idx, effect_index)
		if existing is AudioEffectHardLimiter and existing.resource_name == effect_name:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.resource_name = effect_name
	limiter.pre_gain_db = gain_db
	limiter.ceiling_db = ceiling_db
	AudioServer.add_bus_effect(idx, limiter)

func apply_settings() -> void:
	_apply_bus_volume("Master", master_volume)
	_apply_bus_volume("Music", music_volume)
	_apply_bus_volume("SFX", sfx_volume)
	_apply_bus_volume("Ambient", ambient_volume)
	var view := root_view()
	GRAPHICS.apply_viewport(view,self)
	sync_pipeline_msaa(view.msaa_3d)
	Engine.max_fps = FPS_LIMITS[fps_limit]
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[shadow_quality], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTER[shadow_quality])
	RenderingServer.positional_soft_shadow_filter_set_quality(SHADOW_FILTER[shadow_quality])
	for node in get_tree().get_nodes_in_group(GRAPHICS.DETAIL_GROUP): GRAPHICS.apply_detail(node,detail_quality)
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
		# Window coordinates are integer pixels; preserve centering truncation.
		@warning_ignore("integer_division")
		DisplayServer.window_set_position(usable.position + (usable.size - target) / 2)

## Brilho do mundo: chamado pelo ProductionWorld no ambiente que ele cria.
func apply_environment(environment: Environment) -> void:
	if environment == null: return
	environment.adjustment_enabled = not is_equal_approx(brightness, 1.0)
	environment.adjustment_brightness = brightness
	var advanced := GRAPHICS.forward_plus()
	environment.ssao_enabled = ssao and advanced
	environment.ssr_enabled = false
	environment.volumetric_fog_enabled = volumetric_fog and advanced
	if environment.volumetric_fog_enabled:
		environment.volumetric_fog_density = .005
		environment.volumetric_fog_length = 100.0

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
	_fps_label.text = tr("%d FPS · pico %.1f ms") % [fps, _fps_peak]
	_fps_clock = 0.0
	_fps_peak = 0.0

func root_view() -> Window: return get_tree().root

## O Forward Mobile pré-compila em segundo plano, ao criar cada superfície, o pipeline "ubershader" de cor
## com o número de amostras de rendering/anti_aliasing/quality/msaa_3d (RenderForwardMobile::
## _update_global_pipeline_data_requirements_from_project, relido a cada quadro) — não com o MSAA do viewport.
## O projeto diz 2x e o jogador pode escolher 4x (ou nada): aí nenhum pipeline pré-compilado servia, e cada
## material novo na tela compilava síncrono no primeiro desenho (fonte "draw"). Fase 2 de 16/10, release com
## MSAA 4x: render_bracket de 106–586 ms sem span na chuva, noite, serra e travessia. Acompanhar o MSAA real
## devolve a compilação ao segundo plano; trocar no menu recompila tudo uma vez, também em segundo plano.
## Só vale enquanto nenhum material vivo ler hint_depth_texture: com MSAA isso põe resolução de depth no
## framebuffer e nenhum pipeline pré-compilado serve mais (ver occluded_silhouette.gdshader). Medido no
## editor, chuva no circuito oeste: compilações "draw" 183 sob a cortina + ~100 em jogo -> 0 + 0.
## A/B: HARBOR_PIPELINE_MSAA_SYNC=0 volta ao comportamento antigo (aqui e nas capturas de reflexo).
## Cache de pipelines do Vulkan gravado só ao sair (22/10, 3ª rodada). O motor regrava o arquivo inteiro a
## cada 3 MB de pipelines novas (rendering/rendering_device/pipeline_cache/save_chunk_size_mb, lido a cada
## gravação). Numa sessão com cache frio o arquivo vai de 0 a ~75 MB e cada regravação travava a thread
## principal: no estresse do oeste (export C, cache frio, mesma build) houve quadros de 1,2 s, 1,5 s e 18 s
## sem nenhuma pipeline nem shader novo no quadro, e o jogo ficou jogável em 94,8 s; com a gravação só na
## saída, máximo 1,33 s e jogável em 74,8 s. Com cache quente o arquivo (216 MB aqui) também é regravado
## inteiro quando a sessão junta 3 MB novos. Se o jogo cair, as pipelines da sessão se perdem (o cache de
## shader em disco continua, então refazê-las é barato). GETECO_PIPELINE_SAVE_ON_EXIT=0 volta aos 3 MB.
static func apply_pipeline_cache_policy() -> void:
	const KEY := "rendering/rendering_device/pipeline_cache/save_chunk_size_mb"
	if OS.get_environment("GETECO_PIPELINE_SAVE_ON_EXIT") == "0": return
	if float(ProjectSettings.get_setting(KEY, 3.0)) < 4096.0: ProjectSettings.set_setting(KEY, 4096.0)

static func sync_pipeline_msaa(samples: int) -> void:
	const KEY := "rendering/anti_aliasing/quality/msaa_3d"
	if OS.get_environment("HARBOR_PIPELINE_MSAA_SYNC") == "0": return
	if int(ProjectSettings.get_setting(KEY, 0)) != samples: ProjectSettings.set_setting(KEY, samples)

func save_settings(path := "") -> Error:
	if path.is_empty(): path = default_path()
	var config := ConfigFile.new()
	config.set_value("audio","master_volume",master_volume)
	config.set_value("audio","music_volume",music_volume)
	config.set_value("audio","sfx_volume",sfx_volume)
	config.set_value("audio","ambient_volume",ambient_volume)
	config.set_value("audio","mute_unfocused",mute_unfocused)
	config.set_value("audio","voice_language",voice_language)
	config.set_value("interface","text_language",text_language)
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
	for key in GRAPHICS.KEYS:
		if key not in ["msaa","render_scale","shadow_quality"]: config.set_value("graphics",key,get(key))
	config.set_value("controls","bindings",get_node("/root/GameInput").export_bindings())
	config.set_value("controls","gamepad_bindings",get_node("/root/GameInput").export_gamepad_bindings())
	config.set_value("controls","gamepad_bindings_version",get_node("/root/GameInput").GAMEPAD_BINDINGS_VERSION)
	config.set_value("controls","controller_layout",get_node("/root/GameInput").controller_layout)
	return config.save(path)
