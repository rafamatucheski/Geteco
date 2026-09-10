class_name IceStormManager
extends Node2D

## Gerenciador de Clima Severo da Montanha:
## Controla chuva de gelo (granizo cortante), nevasca, rajadas de vento polar e névoa de altitude.

enum StormState {
	CLEAR_CHILLY,  # Céu limpo porém frio (sopé da serra)
	LIGHT_SNOW,    # Flocos suaves caindo
	HEAVY_BLIZZARD,# Nevasca densa com vento polar
	ICE_RAIN_HAIL  # Chuva de granizo e gelo cortante
}

@export var current_state: StormState = StormState.ICE_RAIN_HAIL
@export var storm_intensity: float = 1.0 # 0.0 a 1.5
@export var follow_target: Node2D = null

# Nós de Partículas
var hail_particles: CPUParticles2D
var ice_shard_particles: CPUParticles2D
var snow_blizzard_particles: CPUParticles2D
var frost_mist_particles: CPUParticles2D

# Texturas Procedurais de Gelo
static var _hail_tex: Texture2D
static var _shard_tex: Texture2D
static var _snow_tex: Texture2D
static var _mist_tex: Texture2D

# Áudio de Vento Polar & Granizo
var wind_player: AudioStreamPlayer
var sheltered := false
@export var dynamic_weather := true
var weather_clock := 0.0
const WEATHER_CYCLE := 240.0

func advance_weather(delta: float) -> void:
	weather_clock = fposmod(weather_clock + delta, WEATHER_CYCLE)
	# A quiet interval precedes the front. Smooth ramps avoid sudden flashes.
	var phase := weather_clock / WEATHER_CYCLE
	var front := smoothstep(0.16, 0.40, phase) * (1.0 - smoothstep(0.67, 0.92, phase))
	var gust := 0.86 + 0.14 * sin(weather_clock * 0.19)
	storm_intensity = front * gust
	var next_state := StormState.CLEAR_CHILLY
	if front > 0.08: next_state = StormState.LIGHT_SNOW
	if front > 0.65: next_state = StormState.HEAVY_BLIZZARD
	if front > 0.92 and phase < 0.60: next_state = StormState.ICE_RAIN_HAIL
	if next_state != current_state:
		set_storm_state(next_state)
	if snow_blizzard_particles:
		snow_blizzard_particles.modulate.a = front
		snow_blizzard_particles.speed_scale = lerpf(0.45, 1.15, front)
		hail_particles.modulate.a = smoothstep(0.85, 1.0, front)
		ice_shard_particles.modulate.a = hail_particles.modulate.a
		frost_mist_particles.modulate.a = lerpf(0.15, 0.8, front)


func _ready() -> void:
	z_index = 25 # Acima da maioria dos cenários, sob HUD
	_setup_textures()
	_setup_particles()
	_setup_audio()
	set_storm_state(current_state)
	if dynamic_weather:
		advance_weather(0.0)

func _process(_delta: float) -> void:
	if follow_target and is_instance_valid(follow_target):
		global_position = follow_target.global_position

	if dynamic_weather:
		advance_weather(_delta)

static func get_hail_texture() -> Texture2D:
	if _hail_tex == null:
		var img := Image.create(4, 10, false, Image.FORMAT_RGBA8)
		for y in 10:
			var alpha: float = sin(PI * float(y) / 9.0)
			for x in 4:
				var dist: float = absf(float(x) - 1.5) / 1.5
				var c := Color(0.85, 0.95, 1.0, alpha * (1.0 - dist * 0.6))
				img.set_pixel(x, y, c)
		_hail_tex = ImageTexture.create_from_image(img)
	return _hail_tex

static func get_shard_texture() -> Texture2D:
	if _shard_tex == null:
		var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
		for y in 6:
			for x in 6:
				var d: float = Vector2(x - 2.5, y - 2.5).length()
				if d <= 2.2:
					img.set_pixel(x, y, Color(0.9, 0.98, 1.0, 1.0 - d / 2.2))
				else:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
		_shard_tex = ImageTexture.create_from_image(img)
	return _shard_tex

static func get_snow_texture() -> Texture2D:
	if _snow_tex == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		for y in 8:
			for x in 8:
				var d: float = Vector2(x - 3.5, y - 3.5).length()
				var a: float = clampf(1.0 - d / 3.5, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_snow_tex = ImageTexture.create_from_image(img)
	return _snow_tex

static func get_mist_texture() -> Texture2D:
	if _mist_tex == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d: float = Vector2(x - 15.5, y - 15.5).length()
				var a: float = clampf(1.0 - d / 15.5, 0.0, 1.0)
				img.set_pixel(x, y, Color(0.88, 0.92, 1.0, a * a * 0.35))
		_mist_tex = ImageTexture.create_from_image(img)
	return _mist_tex

func _setup_textures() -> void:
	get_hail_texture()
	get_shard_texture()
	get_snow_texture()
	get_mist_texture()

func _setup_particles() -> void:
	# 1. Granizo / Chuva de Gelo (Projéteis rápidos em ângulo com o vento)
	hail_particles = CPUParticles2D.new()
	hail_particles.name = "HailParticles"
	hail_particles.texture = _hail_tex
	hail_particles.particle_flag_align_y = true
	hail_particles.gravity = Vector2.ZERO
	hail_particles.amount = 300
	hail_particles.lifetime = 0.55
	hail_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	hail_particles.emission_rect_extents = Vector2(1100, 700)
	hail_particles.direction = Vector2(-0.65, 1.0).normalized()
	hail_particles.spread = 5.0
	hail_particles.initial_velocity_min = 900.0
	hail_particles.initial_velocity_max = 1300.0
	hail_particles.scale_amount_min = 0.8
	hail_particles.scale_amount_max = 1.4
	hail_particles.color = Color(0.85, 0.96, 1.0, 0.9)
	add_child(hail_particles)

	# 2. Estilhaços de Gelo no Solo (Rebatimento / Shatter)
	ice_shard_particles = CPUParticles2D.new()
	ice_shard_particles.name = "IceShardParticles"
	ice_shard_particles.texture = _shard_tex
	ice_shard_particles.gravity = Vector2(0, 400)
	ice_shard_particles.amount = 120
	ice_shard_particles.lifetime = 0.28
	ice_shard_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ice_shard_particles.emission_rect_extents = Vector2(1000, 600)
	ice_shard_particles.direction = Vector2(0, -1.0)
	ice_shard_particles.spread = 65.0
	ice_shard_particles.initial_velocity_min = 60.0
	ice_shard_particles.initial_velocity_max = 160.0
	ice_shard_particles.scale_amount_min = 0.4
	ice_shard_particles.scale_amount_max = 1.1
	ice_shard_particles.color = Color(0.9, 0.98, 1.0, 0.75)
	add_child(ice_shard_particles)

	# 3. Nevasca (Flocos Densos flutuando ao vento)
	snow_blizzard_particles = CPUParticles2D.new()
	snow_blizzard_particles.name = "SnowBlizzardParticles"
	snow_blizzard_particles.texture = _snow_tex
	snow_blizzard_particles.gravity = Vector2(-200, 150)
	snow_blizzard_particles.amount = 400
	snow_blizzard_particles.lifetime = 2.2
	snow_blizzard_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow_blizzard_particles.emission_rect_extents = Vector2(1200, 750)
	snow_blizzard_particles.direction = Vector2(-0.8, 0.6).normalized()
	snow_blizzard_particles.spread = 20.0
	snow_blizzard_particles.initial_velocity_min = 180.0
	snow_blizzard_particles.initial_velocity_max = 380.0
	snow_blizzard_particles.scale_amount_min = 0.6
	snow_blizzard_particles.scale_amount_max = 2.2
	snow_blizzard_particles.color = Color(1.0, 1.0, 1.0, 0.9)
	add_child(snow_blizzard_particles)

	# 4. Névoa Gelada Volumétrica (Mist)
	frost_mist_particles = CPUParticles2D.new()
	frost_mist_particles.name = "FrostMistParticles"
	frost_mist_particles.texture = _mist_tex
	frost_mist_particles.gravity = Vector2.ZERO
	frost_mist_particles.amount = 35
	frost_mist_particles.lifetime = 4.0
	frost_mist_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	frost_mist_particles.emission_rect_extents = Vector2(1100, 650)
	frost_mist_particles.direction = Vector2(-1.0, 0.2).normalized()
	frost_mist_particles.spread = 15.0
	frost_mist_particles.initial_velocity_min = 50.0
	frost_mist_particles.initial_velocity_max = 110.0
	frost_mist_particles.scale_amount_min = 4.0
	frost_mist_particles.scale_amount_max = 8.5
	frost_mist_particles.color = Color(0.88, 0.94, 1.0, 0.35)
	add_child(frost_mist_particles)

## Brisa, nevasca e rajadas com abafamento próprio e suspensão fora da serra.
func _setup_audio() -> void:
	var mixer := preload("res://audio/regional/SnowWindAudio.gd").new()
	mixer.name = "SnowWindAudio"
	add_child(mixer)
	wind_player = mixer.bed

func set_storm_state(state: StormState) -> void:
	current_state = state
	if hail_particles == null:
		return
	match state:
		StormState.CLEAR_CHILLY:
			hail_particles.emitting = false
			ice_shard_particles.emitting = false
			snow_blizzard_particles.emitting = false
			frost_mist_particles.emitting = true
			frost_mist_particles.amount = 15
		StormState.LIGHT_SNOW:
			hail_particles.emitting = false
			ice_shard_particles.emitting = false
			snow_blizzard_particles.emitting = true
			snow_blizzard_particles.amount = 150
			frost_mist_particles.emitting = true
		StormState.HEAVY_BLIZZARD:
			hail_particles.emitting = false
			ice_shard_particles.emitting = false
			snow_blizzard_particles.emitting = true
			snow_blizzard_particles.amount = 400
			frost_mist_particles.emitting = true
			frost_mist_particles.amount = 45
		StormState.ICE_RAIN_HAIL:
			hail_particles.emitting = true
			ice_shard_particles.emitting = true
			snow_blizzard_particles.emitting = true
			snow_blizzard_particles.amount = 260
			frost_mist_particles.emitting = true
			frost_mist_particles.amount = 40

	if sheltered:
		for particles in [hail_particles, ice_shard_particles, snow_blizzard_particles, frost_mist_particles]:
			particles.emitting = false

func set_sheltered(value: bool) -> void:
	if sheltered == value:
		return
	sheltered = value
	visible = not sheltered
	if sheltered:
		for particles in [hail_particles, ice_shard_particles, snow_blizzard_particles, frost_mist_particles]:
			particles.emitting = false
	else:
		set_storm_state(current_state)
