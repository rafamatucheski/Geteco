class_name DayNightWeatherManager
extends CanvasModulate

signal time_changed(is_dark: bool)
signal biome_changed(biome_name: String)

enum BiomeType {
	CITY_METROPOLIS,  # 0: Cidade (Dia/Noite, nublado e garoa ocasional)
	WINTER_SNOW,      # 1: Frio / Neve (Flocos caindo, vento gélido, modulação fria)
	DESERT_BADLANDS,  # 2: Deserto Árido (Sem chuva, tempestade de areia/poeira, calor intenso)
	FOREST_WOODS,     # 3: Floresta / Montanha (Folhas ao vento, névoa leve, brisa da floresta)
	BEACH_COASTAL     # 4: Praia / Costa Tropical (Sol radiante, maresia, ondas do mar)
}

# Os IDs antigos permanecem estáveis: saves, missões e testes ainda podem
# pedir STORM explicitamente. O ciclo natural da cidade usa apenas os estados
# mais leves CLEAR, CLOUDY e DRIZZLE.
enum WeatherState {
	CLEAR = 0,
	DRIZZLE = 1,
	STORM = 2,
	CLOUDY = 3,
}

@export var current_biome: BiomeType = BiomeType.CITY_METROPOLIS
@export var day_length_seconds: float = 180.0
@export var is_dynamic_time: bool = true

var time_of_day: float = 0.25
var is_dark: bool = false
var weather_state: int = WeatherState.CLEAR
var weather_timer: float = 120.0
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
var rain_intensity := 0.22
var _flash_tween: Tween
var _thunder_tween: Tween
var atmosphere: CanvasLayer
var regional_rain_exposure := 1.0

func enable_regional_atmosphere() -> void:
	if is_instance_valid(atmosphere): return
	atmosphere = preload("res://systems/atmosphere/RegionalAtmosphere.gd").new()
	add_child(atmosphere)

func set_regional_rain_exposure(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(value, regional_rain_exposure): return
	regional_rain_exposure = value
	if value <= 0.001:
		if _flash_tween and _flash_tween.is_running(): _flash_tween.kill()
		if _thunder_tween and _thunder_tween.is_running(): _thunder_tween.kill()
	_sync_rain_audio()
	_update_rain_particles()
	_update_lighting()

# Paleta de Cores
const COLOR_DAY = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_GOLDEN_HOUR = Color(1.0, 0.88, 0.70, 1.0)
const COLOR_SUNSET = Color(1.0, 0.62, 0.38, 1.0)
const COLOR_TWILIGHT = Color(0.52, 0.44, 0.58, 1.0)
const COLOR_NIGHT = Color(0.25, 0.29, 0.40, 1.0)
const COLOR_DAWN_GRAY = Color(0.61, 0.67, 0.73, 1.0)
const COLOR_FIRST_LIGHT = Color(0.91, 0.82, 0.74, 1.0)
const COLOR_OVERCAST = Color(0.66, 0.71, 0.74, 1.0)
const COLOR_DRIZZLE = Color(0.57, 0.64, 0.69, 1.0)
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
	biome_audio.bus = &"Ambient"
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
			if get_rain_intensity() > 0.0:
				rain_particles.emitting = true
				splash_particles.emitting = true
			if biome_audio.playing: biome_audio.stop()
			biome_changed.emit("Metrópole Central")
			
		BiomeType.WINTER_SNOW:
			snow_particles.emitting = true
			biome_audio.stream = ProceduralAudio.get_snow_wind_stream()
			biome_audio.play()
			weather_state = WeatherState.CLEAR # Sem chuva comum
			_fade_rain(false)
			biome_changed.emit("Distrito Ártico")
			
		BiomeType.DESERT_BADLANDS:
			sand_particles.emitting = true
			biome_audio.stream = ProceduralAudio.get_desert_wind_stream()
			biome_audio.play()
			weather_state = WeatherState.CLEAR # NO DESERTO NUNCA CHOVE!
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
			weather_state = WeatherState.CLEAR
			_fade_rain(false)
			biome_changed.emit("Sunset Coast")
			
	_sync_rain_audio()
	_update_rain_particles()
	if is_inside_interior:
		set_interior_mode(true)
	_update_lighting()
	_refresh_weather_reactive_visuals()

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
	if is_dynamic_time:
		time_of_day = fmod(time_of_day + (delta / day_length_seconds), 1.0)
		_update_lighting()
	if is_inside_interior:
		color = Color.WHITE
		return
		
	# Apenas a cidade tem transições de chuva/trovão dinâmicas
	if current_biome == BiomeType.CITY_METROPOLIS:
		weather_timer -= delta
		if weather_timer <= 0.0:
			weather_timer = randf_range(90.0, 180.0)
			_roll_next_city_weather()
				
		if weather_state == WeatherState.STORM:
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
		view_size.x = minf(view_size.x, 2400.0)
		view_size.y = minf(view_size.y, 1600.0)
		rain_particles.emission_rect_extents = view_size * 0.5 + Vector2(160, 200)
		splash_particles.emission_rect_extents = view_size * 0.5 + Vector2(30, 30)
		if rain_particles: rain_particles.global_position = pos
		if splash_particles: splash_particles.global_position = pos
		if snow_particles: snow_particles.global_position = pos
		if sand_particles: sand_particles.global_position = pos
		if leaf_particles: leaf_particles.global_position = pos
		if spray_particles: spray_particles.global_position = pos

func _update_lighting() -> void:
	var target_color = COLOR_DAY
	
	if time_of_day < 0.19:
		target_color = COLOR_NIGHT
	elif time_of_day < 0.24:
		var factor = (time_of_day - 0.19) / 0.05
		target_color = COLOR_NIGHT.lerp(COLOR_DAWN_GRAY, factor)
	elif time_of_day < 0.30:
		var factor = (time_of_day - 0.24) / 0.06
		target_color = COLOR_DAWN_GRAY.lerp(COLOR_FIRST_LIGHT, factor)
	elif time_of_day < 0.36:
		var factor = (time_of_day - 0.30) / 0.06
		target_color = COLOR_FIRST_LIGHT.lerp(COLOR_DAY, factor)
	elif time_of_day < 0.68:
		target_color = COLOR_DAY
	elif time_of_day < 0.74:
		var factor = (time_of_day - 0.68) / 0.06
		target_color = COLOR_DAY.lerp(COLOR_GOLDEN_HOUR, factor)
	elif time_of_day < 0.79:
		var factor = (time_of_day - 0.74) / 0.05
		target_color = COLOR_GOLDEN_HOUR.lerp(COLOR_SUNSET, factor)
	elif time_of_day < 0.84:
		var factor = (time_of_day - 0.79) / 0.05
		target_color = COLOR_SUNSET.lerp(COLOR_TWILIGHT, factor)
	elif time_of_day < 0.88:
		var factor = (time_of_day - 0.84) / 0.04
		target_color = COLOR_TWILIGHT.lerp(COLOR_NIGHT, factor)
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
			if weather_state == WeatherState.STORM:
				target_color = target_color.lerp(COLOR_STORM, 0.75 * regional_rain_exposure)
			elif weather_state == WeatherState.DRIZZLE:
				target_color = target_color.lerp(COLOR_DRIZZLE, 0.52 * regional_rain_exposure)
			elif weather_state == WeatherState.CLOUDY:
				target_color = target_color.lerp(COLOR_OVERCAST, 0.46 * regional_rain_exposure)
			
	if is_instance_valid(atmosphere):
		# The compositor colors highlights and shadows separately. Keep the shared
		# sunset's brightness here without tinting every snowy shadow orange.
		var luminance := target_color.get_luminance()
		var twilight := smoothstep(0.67, 0.76, time_of_day) * (1.0 - smoothstep(0.78, 0.88, time_of_day))
		target_color = target_color.lerp(Color(luminance, luminance, luminance), twilight * 0.70)
	if not (_flash_tween and _flash_tween.is_running()):
		color = Color.WHITE if is_inside_interior else target_color
	
	var new_is_dark = (time_of_day > 0.79 or time_of_day < 0.30 or (weather_state == WeatherState.STORM and regional_rain_exposure > 0.5))
	if new_is_dark != is_dark:
		is_dark = new_is_dark
		time_changed.emit(is_dark)
		_notify_headlights(is_dark)
		_refresh_weather_reactive_visuals()

func _notify_headlights(dark: bool) -> void:
	for vehicle in get_tree().get_nodes_in_group("traffic_vehicles"):
		if is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion() and vehicle.has_method("set_headlights"):
			vehicle.set_headlights(dark)
	for car in get_tree().get_nodes_in_group("player_car"):
		if is_instance_valid(car) and not car.is_queued_for_deletion() and car.has_method("set_headlights"):
			car.set_headlights(dark)

func set_weather(state: int) -> void:
	if current_biome == BiomeType.DESERT_BADLANDS:
		state = WeatherState.CLEAR # No deserto não há chuva
	var previous := weather_state
	weather_state = clampi(state, WeatherState.CLEAR, WeatherState.CLOUDY)
	_sync_rain_audio()
	_update_rain_particles()
	if weather_state != WeatherState.STORM:
		if _flash_tween and _flash_tween.is_valid():
			_flash_tween.kill()
		if _thunder_tween and _thunder_tween.is_valid():
			_thunder_tween.kill()
	elif previous != WeatherState.STORM:
		_trigger_lightning()
		
	_update_lighting()
	if previous != weather_state:
		_refresh_weather_reactive_visuals()

func _refresh_weather_reactive_visuals() -> void:
	if is_inside_tree():
		get_tree().call_group(&"weather_reactive_visuals", &"queue_redraw")

func _roll_next_city_weather() -> void:
	# Porto variado, mas legível: tempestade forte nunca aparece por sorteio.
	# Um estado STORM ainda pode ser dirigido explicitamente por narrativa.
	var roll := randf()
	if roll < 0.42:
		set_weather(WeatherState.CLEAR)
	elif roll < 0.78:
		set_weather(WeatherState.CLOUDY)
	else:
		set_rain_intensity(randf_range(0.14, 0.30))
		set_weather(WeatherState.DRIZZLE)

func _fade_rain(enable: bool, target_db: float = -12.0) -> void:
	# Legacy biome callers retain this API; no competing fade/stop callbacks.
	if weather_audio:
		weather_audio.set_conditions((1.0 if target_db >= -6.0 else rain_intensity) if enable else 0.0, is_inside_interior)

func get_rain_intensity() -> float:
	if current_biome not in [BiomeType.CITY_METROPOLIS, BiomeType.FOREST_WOODS]:
		return 0.0
	var local_rain := 1.0 if weather_state == WeatherState.STORM else (rain_intensity if weather_state == WeatherState.DRIZZLE else 0.0)
	return local_rain * regional_rain_exposure

func set_rain_intensity(amount: float) -> void:
	# Preserve serialized weather IDs: 0 clear, 1 drizzle/rain, 2 storm, 3 cloudy.
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
		var drop_count := int(lerpf(34.0, 120.0, strength))
		if rain_particles.amount != drop_count:
			rain_particles.amount = drop_count
		rain_particles.initial_velocity_min = lerpf(300.0, 680.0, strength)
		rain_particles.initial_velocity_max = lerpf(430.0, 880.0, strength)
		rain_particles.scale_amount_min = lerpf(0.28, 0.58, strength)
		rain_particles.scale_amount_max = lerpf(0.42, 1.05, strength)
		rain_particles.color.a = lerpf(0.14, 0.58, strength)
	if splash_particles:
		splash_particles.emitting = outside
		var splash_count := int(lerpf(8.0, 36.0, strength))
		if splash_particles.amount != splash_count:
			splash_particles.amount = splash_count
		splash_particles.color.a = lerpf(0.08, 0.36, strength)

func _trigger_lightning() -> void:
	if weather_state != WeatherState.STORM or is_inside_interior or get_rain_intensity() <= 0.0: return
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
		if weather_audio and weather_state == WeatherState.STORM and get_rain_intensity() > 0.0:
			weather_audio.play_thunder()
	)
