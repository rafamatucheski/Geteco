class_name DayNightWeatherManager
extends CanvasModulate

signal time_changed(is_dark: bool)
signal biome_changed(biome_name: String)

enum BiomeType {
	CITY_METROPOLIS,  # 0: Cidade (Dia/Noite com Chuva e Trovões ocasionais)
	WINTER_SNOW,      # 1: Frio / Neve (Flocos caindo, vento gélido, modulação fria)
	DESERT_BADLANDS,  # 2: Deserto Árido (Sem chuva, tempestade de areia/poeira, calor intenso)
	FOREST_WOODS,     # 3: Floresta / Montanha (Folhas ao vento, névoa leve, brisa da floresta)
	BEACH_COASTAL     # 4: Praia / Costa Tropical (Sol radiante, maresia, ondas do mar)
}

@export var current_biome: BiomeType = BiomeType.CITY_METROPOLIS
@export var day_length_seconds: float = 180.0
@export var is_dynamic_time: bool = true

var time_of_day: float = 0.25
var is_dark: bool = false
var weather_state: int = 0
var weather_timer: float = 45.0
var lightning_timer: float = 14.0

# Emissores de Partículas Climáticas
var rain_particles: CPUParticles2D
var splash_particles: CPUParticles2D
var snow_particles: CPUParticles2D
var sand_particles: CPUParticles2D
var leaf_particles: CPUParticles2D
var spray_particles: CPUParticles2D

# Áudios de Ambiente
var rain_audio: AudioStreamPlayer
var thunder_audio: AudioStreamPlayer
var biome_audio: AudioStreamPlayer
const WEATHER_AUDIO := preload("res://audio/weather/WeatherAudioMixer.gd")
const RAIN_VISUALS := preload("res://audio/weather/RainVisualPalette.gd")
var weather_audio: Node
var rain_intensity := 0.55
var _flash_tween: Tween
var _thunder_tween: Tween

# Paleta de Cores
const COLOR_DAY = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_SUNSET = Color(1.0, 0.72, 0.50, 1.0)
const COLOR_NIGHT = Color(0.18, 0.22, 0.38, 1.0)
const COLOR_DAWN = Color(0.85, 0.75, 0.90, 1.0)
const COLOR_STORM = Color(0.32, 0.36, 0.44, 1.0)
const COLOR_WINTER = Color(0.80, 0.88, 1.05, 1.0)
const COLOR_DESERT = Color(1.08, 0.96, 0.82, 1.0)
const COLOR_FOREST = Color(0.90, 1.02, 0.92, 1.0)
const COLOR_BEACH = Color(1.04, 1.02, 0.94, 1.0)

func _ready() -> void:
	add_to_group("day_night_manager")
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_setup_weather_effects()
	set_biome(current_biome)
	_update_lighting()
	call_deferred("_notify_headlights", is_dark)

func _exit_tree() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	if _thunder_tween and _thunder_tween.is_valid():
		_thunder_tween.kill()
	if is_instance_valid(biome_audio):
		biome_audio.stop()
		biome_audio.stream = null

func _setup_weather_effects() -> void:
	# 1. Chuva Slanted
	rain_particles = CPUParticles2D.new()
	rain_particles.texture = RAIN_VISUALS.streak()
	rain_particles.particle_flag_align_y = true
	rain_particles.gravity = Vector2.ZERO
	rain_particles.emitting = false
	rain_particles.amount = 180
	rain_particles.lifetime = 0.65
	rain_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain_particles.emission_rect_extents = Vector2(900, 550)
	rain_particles.direction = Vector2(-0.35, 1.0).normalized()
	rain_particles.spread = 4.0
	rain_particles.initial_velocity_min = 600.0
	rain_particles.initial_velocity_max = 800.0
	rain_particles.scale_amount_min = 0.45
	rain_particles.scale_amount_max = 0.85
	rain_particles.color = Color(0.80, 0.90, 1.0, 0.55)
	rain_particles.z_index = 30
	add_child(rain_particles)
	
	# 2. Respingos no Asfalto
	splash_particles = CPUParticles2D.new()
	splash_particles.texture = RAIN_VISUALS.splash()
	splash_particles.gravity = Vector2.ZERO
	splash_particles.scale_amount_min = 0.3
	splash_particles.scale_amount_max = 0.65
	var splash_fade := Gradient.new()
	splash_fade.set_color(0, Color.WHITE)
	splash_fade.set_color(1, Color(1, 1, 1, 0))
	splash_particles.color_ramp = splash_fade
	splash_particles.emitting = false
	splash_particles.amount = 70
	splash_particles.lifetime = 0.25
	splash_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	splash_particles.emission_rect_extents = Vector2(850, 500)
	splash_particles.direction = Vector2(0.0, -1.0)
	splash_particles.spread = 60.0
	splash_particles.initial_velocity_min = 25.0
	splash_particles.initial_velocity_max = 55.0
	splash_particles.color = Color(0.85, 0.92, 1.0, 0.45)
	splash_particles.z_index = 28
	add_child(splash_particles)
	
	# 3. Neve Suave Flutuante (Inverno)
	snow_particles = CPUParticles2D.new()
	snow_particles.emitting = false
	snow_particles.amount = 220
	snow_particles.lifetime = 2.8
	snow_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow_particles.emission_rect_extents = Vector2(950, 600)
	snow_particles.direction = Vector2(-0.25, 1.0).normalized()
	snow_particles.spread = 15.0
	snow_particles.initial_velocity_min = 65.0
	snow_particles.initial_velocity_max = 140.0
	snow_particles.scale_amount_min = 2.0
	snow_particles.scale_amount_max = 4.5
	snow_particles.color = Color(0.96, 0.98, 1.0, 0.85)
	snow_particles.z_index = 30
	add_child(snow_particles)
	
	# 4. Tempestade de Areia / Poeira Quente (Deserto)
	sand_particles = CPUParticles2D.new()
	sand_particles.emitting = false
	sand_particles.amount = 140
	sand_particles.lifetime = 1.4
	sand_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sand_particles.emission_rect_extents = Vector2(950, 600)
	sand_particles.direction = Vector2(1.0, 0.15).normalized()
	sand_particles.spread = 8.0
	sand_particles.initial_velocity_min = 220.0
	sand_particles.initial_velocity_max = 380.0
	sand_particles.scale_amount_min = 1.8
	sand_particles.scale_amount_max = 3.8
	sand_particles.color = Color(0.88, 0.76, 0.52, 0.50)
	sand_particles.z_index = 30
	add_child(sand_particles)
	
	# 5. Folhas Caídas ao Vento (Floresta)
	leaf_particles = CPUParticles2D.new()
	leaf_particles.emitting = false
	leaf_particles.amount = 60
	leaf_particles.lifetime = 3.2
	leaf_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	leaf_particles.emission_rect_extents = Vector2(900, 550)
	leaf_particles.direction = Vector2(0.6, 0.8).normalized()
	leaf_particles.spread = 25.0
	leaf_particles.initial_velocity_min = 40.0
	leaf_particles.initial_velocity_max = 95.0
	leaf_particles.scale_amount_min = 2.5
	leaf_particles.scale_amount_max = 5.0
	leaf_particles.color = Color(0.85, 0.45, 0.15, 0.85) # Tons outonais
	leaf_particles.z_index = 30
	add_child(leaf_particles)

	# 6. Maresia / Brisa Tropical (Praia)
	spray_particles = CPUParticles2D.new()
	spray_particles.emitting = false
	spray_particles.amount = 80
	spray_particles.lifetime = 2.0
	spray_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	spray_particles.emission_rect_extents = Vector2(900, 550)
	spray_particles.direction = Vector2(-0.8, -0.2).normalized()
	spray_particles.spread = 30.0
	spray_particles.initial_velocity_min = 35.0
	spray_particles.initial_velocity_max = 75.0
	spray_particles.scale_amount_min = 1.5
	spray_particles.scale_amount_max = 3.5
	spray_particles.color = Color(0.90, 0.96, 1.0, 0.35)
	spray_particles.z_index = 30
	add_child(spray_particles)
	
	# Áudio Players
	weather_audio = WEATHER_AUDIO.new()
	weather_audio.name = "WeatherAudio"
	add_child(weather_audio)
	# Keep the public player references used by scene diagnostics.
	rain_audio = weather_audio.layers[0]
	thunder_audio = weather_audio.thunder
	
	biome_audio = AudioStreamPlayer.new()
	biome_audio.bus = &"SFX"
	biome_audio.volume_db = -12.0
	add_child(biome_audio)

func set_biome(type: BiomeType) -> void:
	current_biome = type
	
	# Desativa todas as partículas primeiro
	if rain_particles: rain_particles.emitting = false
	if splash_particles: splash_particles.emitting = false
	if snow_particles: snow_particles.emitting = false
	if sand_particles: sand_particles.emitting = false
	if leaf_particles: leaf_particles.emitting = false
	if spray_particles: spray_particles.emitting = false
	
	match current_biome:
		BiomeType.CITY_METROPOLIS:
			if weather_state > 0:
				rain_particles.emitting = true
				splash_particles.emitting = true
			if biome_audio.playing: biome_audio.stop()
			biome_changed.emit("Metrópole Central")
			
		BiomeType.WINTER_SNOW:
			snow_particles.emitting = true
			biome_audio.stream = ProceduralAudio.get_snow_wind_stream()
			biome_audio.play()
			weather_state = 0 # Sem chuva comum
			_fade_rain(false)
			biome_changed.emit("Distrito Ártico")
			
		BiomeType.DESERT_BADLANDS:
			sand_particles.emitting = true
			biome_audio.stream = ProceduralAudio.get_desert_wind_stream()
			biome_audio.play()
			weather_state = 0 # NO DESERTO NUNCA CHOVE!
			_fade_rain(false)
			biome_changed.emit("Badlands Áridas")
			
		BiomeType.FOREST_WOODS:
			leaf_particles.emitting = true
			biome_audio.stream = ProceduralAudio.get_forest_ambience_stream()
			biome_audio.play()
			_fade_rain(false)
			biome_changed.emit("Reserva Florestal")
			
		BiomeType.BEACH_COASTAL:
			spray_particles.emitting = true
			biome_audio.stream = ProceduralAudio.get_beach_waves_stream()
			biome_audio.play()
			weather_state = 0
			_fade_rain(false)
			biome_changed.emit("Sunset Coast")
			
	_sync_rain_audio()
	_update_rain_particles()
	if is_inside_interior:
		set_interior_mode(true)
	_update_lighting()

var is_inside_interior: bool = false

func set_interior_mode(inside: bool) -> void:
	is_inside_interior = inside
	if inside:
		if _flash_tween and _flash_tween.is_valid():
			_flash_tween.kill()
		color = Color(1.0, 1.0, 1.0, 1.0) # Iluminação neutra e clara de interior fechado
		if rain_particles: rain_particles.emitting = false
		if splash_particles: splash_particles.emitting = false
		if snow_particles: snow_particles.emitting = false
		if sand_particles: sand_particles.emitting = false
		if leaf_particles: leaf_particles.emitting = false
		if spray_particles: spray_particles.emitting = false
		_sync_rain_audio()
		if biome_audio and biome_audio.playing:
			biome_audio.volume_db = -35.0
	else:
		if biome_audio: biome_audio.volume_db = -10.0
		_update_lighting()
		# Restore the existing state without manufacturing another lightning strike.
		_sync_rain_audio()
		_update_rain_particles()

func is_raining() -> bool:
	return not is_inside_interior and get_rain_intensity() > 0.0

func _process(delta: float) -> void:
	if is_inside_interior:
		color = Color(1.0, 1.0, 1.0, 1.0)
		return

	if is_dynamic_time:
		time_of_day = fmod(time_of_day + (delta / day_length_seconds), 1.0)
		_update_lighting()
		
	# Apenas a cidade tem transições de chuva/trovão dinâmicas
	if current_biome == BiomeType.CITY_METROPOLIS:
		weather_timer -= delta
		if weather_timer <= 0.0:
			weather_timer = randf_range(45.0, 100.0)
			var r = randf()
			if r < 0.55:
				set_weather(0)
			elif r < 0.85:
				rain_intensity = randf_range(0.22, 0.65)
				set_weather(1)
			else:
				set_weather(2)
				
		if weather_state == 2:
			lightning_timer -= delta
			if lightning_timer <= 0.0:
				lightning_timer = randf_range(14.0, 26.0)
				_trigger_lightning()
				
	# Segue a câmera do jogador
	var cam = get_viewport().get_camera_2d()
	if cam:
		var pos = cam.global_position
		# Keep the bounded particle budget around the visible play area at any zoom.
		var view_size: Vector2 = get_viewport().get_visible_rect().size / cam.zoom.abs().max(Vector2(0.05, 0.05))
		rain_particles.emission_rect_extents = view_size * 0.5 + Vector2(220, 260)
		splash_particles.emission_rect_extents = view_size * 0.5 + Vector2(30, 30)
		if rain_particles: rain_particles.global_position = pos
		if splash_particles: splash_particles.global_position = pos
		if snow_particles: snow_particles.global_position = pos
		if sand_particles: sand_particles.global_position = pos
		if leaf_particles: leaf_particles.global_position = pos
		if spray_particles: spray_particles.global_position = pos

func _update_lighting() -> void:
	if is_inside_interior:
		color = Color.WHITE
		return
	var target_color = COLOR_DAY
	
	if time_of_day < 0.20:
		target_color = COLOR_NIGHT
	elif time_of_day < 0.28:
		var factor = (time_of_day - 0.20) / 0.08
		target_color = COLOR_NIGHT.lerp(COLOR_DAWN, factor)
	elif time_of_day < 0.35:
		var factor = (time_of_day - 0.28) / 0.07
		target_color = COLOR_DAWN.lerp(COLOR_DAY, factor)
	elif time_of_day < 0.70:
		target_color = COLOR_DAY
	elif time_of_day < 0.78:
		var factor = (time_of_day - 0.70) / 0.08
		target_color = COLOR_DAY.lerp(COLOR_SUNSET, factor)
	elif time_of_day < 0.85:
		var factor = (time_of_day - 0.78) / 0.07
		target_color = COLOR_SUNSET.lerp(COLOR_NIGHT, factor)
	else:
		target_color = COLOR_NIGHT
		
	# Modulação de Bioma
	match current_biome:
		BiomeType.WINTER_SNOW:
			target_color = target_color * COLOR_WINTER
		BiomeType.DESERT_BADLANDS:
			target_color = target_color * COLOR_DESERT
		BiomeType.FOREST_WOODS:
			target_color = target_color * COLOR_FOREST
		BiomeType.BEACH_COASTAL:
			target_color = target_color * COLOR_BEACH
		_:
			if weather_state == 2:
				target_color = target_color.lerp(COLOR_STORM, 0.75)
			elif weather_state == 1:
				target_color = target_color.lerp(COLOR_STORM, 0.40)
			
	if not (_flash_tween and _flash_tween.is_running()):
		color = target_color
	
	var new_is_dark = (time_of_day > 0.78 or time_of_day < 0.28 or weather_state == 2)
	if new_is_dark != is_dark:
		is_dark = new_is_dark
		time_changed.emit(is_dark)
		_notify_headlights(is_dark)

func _notify_headlights(dark: bool) -> void:
	for vehicle in get_tree().get_nodes_in_group("traffic_vehicles"):
		if vehicle.has_method("set_headlights"):
			vehicle.set_headlights(dark)
	for car in get_tree().get_nodes_in_group("player_car"):
		if car.has_method("set_headlights"):
			car.set_headlights(dark)

func set_weather(state: int) -> void:
	if current_biome == BiomeType.DESERT_BADLANDS:
		state = 0 # No deserto não há chuva
	var previous := weather_state
	weather_state = clampi(state, 0, 2)
	_sync_rain_audio()
	_update_rain_particles()
	if weather_state != 2:
		if _flash_tween and _flash_tween.is_valid():
			_flash_tween.kill()
		if _thunder_tween and _thunder_tween.is_valid():
			_thunder_tween.kill()
	elif previous != 2:
		_trigger_lightning()
		
	_update_lighting()

func _fade_rain(enable: bool, target_db: float = -12.0) -> void:
	# Legacy biome callers retain this API; no competing fade/stop callbacks.
	if weather_audio:
		weather_audio.set_conditions((1.0 if target_db >= -6.0 else rain_intensity) if enable else 0.0, is_inside_interior)

func get_rain_intensity() -> float:
	if current_biome not in [BiomeType.CITY_METROPOLIS, BiomeType.FOREST_WOODS]:
		return 0.0
	return 1.0 if weather_state == 2 else (rain_intensity if weather_state == 1 else 0.0)

func set_rain_intensity(amount: float) -> void:
	# Preserve serialized weather IDs: 0 clear, 1 rain (light/moderate), 2 storm.
	rain_intensity = clampf(amount, 0.0, 1.0)
	_sync_rain_audio()
	_update_rain_particles()

func _sync_rain_audio() -> void:
	if weather_audio:
		weather_audio.set_conditions(get_rain_intensity(), is_inside_interior)

func _update_rain_particles() -> void:
	var strength := get_rain_intensity()
	var outside := strength > 0.0 and not is_inside_interior
	if rain_particles:
		rain_particles.emitting = outside
		var drop_count := int(lerpf(100.0, 620.0, strength))
		if rain_particles.amount != drop_count:
			rain_particles.amount = drop_count
		rain_particles.initial_velocity_min = lerpf(400.0, 740.0, strength)
		rain_particles.initial_velocity_max = lerpf(560.0, 980.0, strength)
		rain_particles.scale_amount_min = lerpf(0.35, 0.65, strength)
		rain_particles.scale_amount_max = lerpf(0.5, 1.3, strength)
		rain_particles.color.a = lerpf(0.18, 0.70, strength)
	if splash_particles:
		splash_particles.emitting = outside
		var splash_count := int(lerpf(25.0, 180.0, strength))
		if splash_particles.amount != splash_count:
			splash_particles.amount = splash_count
		splash_particles.color.a = lerpf(0.12, 0.45, strength)

func _trigger_lightning() -> void:
	if weather_state != 2 or is_inside_interior or get_rain_intensity() <= 0.0: return
	if _thunder_tween and _thunder_tween.is_running(): return
	_flash_tween = create_tween()
	var flash_t := _flash_tween
	flash_t.tween_property(self, "color", Color(2.0, 2.0, 2.2), 0.05)
	flash_t.tween_property(self, "color", Color(0.2, 0.22, 0.3), 0.08)
	flash_t.tween_property(self, "color", Color(1.8, 1.8, 2.0), 0.04)
	flash_t.tween_property(self, "color", COLOR_STORM, 0.4)
	flash_t.finished.connect(_update_lighting)
	
	_thunder_tween = create_tween()
	var thunder_t := _thunder_tween
	thunder_t.tween_interval(randf_range(0.8, 3.2))
	thunder_t.tween_callback(func():
		if weather_audio and weather_state == 2 and get_rain_intensity() > 0.0:
			weather_audio.play_thunder()
	)
