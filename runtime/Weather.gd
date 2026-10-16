extends Node
## V1 time/weather IDs, rendered by shared native 3D lights and local particles.
const REGIONAL_ATMOSPHERE := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
const DESERT_MOON := preload("res://runtime/atmosphere/DesertMoonlight.gd")
const PARTICLE_TEXTURES := preload("res://runtime/atmosphere/WeatherParticleTextures.gd")
const COVERAGE := preload("res://runtime/atmosphere/PrecipitationCoverage.gd")
const COASTAL_LOOK := preload("res://runtime/atmosphere/CoastalWeatherLook.gd")
const COASTAL_RAIN := preload("res://runtime/atmosphere/CoastalRainPresentation.gd")
# Productive V1 HarborGame and MountainPass both override the manager to 24 min.
const DAY_LENGTH_SECONDS := 1440.0
var controller
var time_of_day := .32
var weather_state := 0
## Ferramentas do painel de desenvolvedor: velocidade do relógio (0 congela) e clima fixo.
var time_scale := 1.0
var weather_locked := false
var weather_timer := 120.0
var clock := 0.0
var precipitation: GPUParticles3D
var rain_audio: AudioStreamPlayer
var wind_audio: AudioStreamPlayer
var hail: GPUParticles3D
var snow: GPUParticles3D
var mountain_weather: Dictionary = {}
var atmosphere = preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd").new()
var drag_sky = preload("res://runtime/atmosphere/DragStripSky.gd").new()
var drag_rain = preload("res://runtime/atmosphere/DragRaceRain.gd").new()
var atmosphere_step := .2
var weather_audio: Node
var storm: Node
var surface_effects: Node3D
var rain_ground: Node3D
var rain_intensity := .22
var coastal_look := COASTAL_LOOK.new()
var coastal_wetness := 0.0
var _visual_clouds := -1.0
var _covered := false
var _weather_rng := RandomNumberGenerator.new()
# Chuva apresentada (0..1). O ciclo natural muda `weather_state` e a chuva
# engrossa/afina até o alvo; troca feita de fora (teste, chegada, save) é
# instantânea, porque quem força um clima espera vê-lo no mesmo quadro.
var rain_level := 0.0
var _known_state := -1
const RAIN_RISE_SECONDS := 22.0
const RAIN_FALL_SECONDS := 14.0
# Nuvens fecham em ~1 min no ciclo natural; antes eram 4 s e o céu "piscava".
const CLOUD_NATURAL_SECONDS := 30.0
# Troca forçada mantém a transição curta de antes (o céu não corta seco).
const CLOUD_FORCED_SECONDS := 4.0
var _cloud_seconds := CLOUD_FORCED_SECONDS
# Duração (s) de cada estado no ciclo natural: 0 limpo, 1 garoa, 2 tempestade,
# 3 nublado. Com dia de 24 min isso dá ~4–7 trocas por dia em vez de 8–16.
const STATE_SECONDS := {0: Vector2(300, 540), 1: Vector2(180, 300), 2: Vector2(120, 210), 3: Vector2(150, 300)}

# Harbor V1 grades clear daylight almost neutrally and keeps blue shadow fill
# (`profiles/harbor.tres`: sunlight 1.025/1.015/.985, shadow .91/.98/1.065).
# These normalized 3D light colours preserve that authored relationship rather
# than turning every pale urban material amber. Weather strength remains in the
# shared light/environment; model materials are not rewritten here.
const HARBOR_SUN_DAY := Color("fffdf5")
const HARBOR_SUN_NIGHT := Color("afc0e8")
const HARBOR_AMBIENT_DAY := Color("c0d0e2")
const HARBOR_AMBIENT_NIGHT := Color("9baac6")
const HARBOR_OVERCAST_LIGHT := Color("aebfca")
const HARBOR_SKY_DAY := Color("829da6")
const HARBOR_SKY_NIGHT := Color("111d30")
const HARBOR_SKY_OVERCAST := Color("647985")
# Fases da lua. Na vida real o ciclo leva 29,5 dias; com um dia de jogo de
# 24 min isso daria ~12 h por ciclo. Oito dias de jogo (~192 min) preservam
# o ciclo lunar curto da V2 sem acelerar o dia autorado na V1.
const MOON_CYCLE_DAYS := 8.0
# Lua nova quase não ilumina; lua cheia deixa a rua legível sem virar dia.
const MOON_LIGHT_NEW := .05
const MOON_LIGHT_FULL := .34
const MOON_AMBIENT_NEW := .26
const MOON_AMBIENT_FULL := .42
const HARBOR_SKY_FULL_MOON := Color("1d2c47")
func _exit_tree() -> void:
	if controller != null and is_instance_valid(controller.environment):
		coastal_look.release(controller.environment.environment)
	for channel in [wind_audio]:
		if is_instance_valid(channel):
			channel.stop()
			channel.stream = null
	for emitter in [precipitation,hail,snow]:
		if is_instance_valid(emitter): emitter.queue_free()
	if is_instance_valid(surface_effects): surface_effects.queue_free()
	if is_instance_valid(rain_ground): rain_ground.queue_free()
	PARTICLE_TEXTURES.release_cache()
func _ready() -> void:
	# Follow after the gameplay camera has applied its lead, zoom and orbit.
	process_priority = 100
	_weather_rng.randomize()
	time_of_day = float(controller.state.world_state.get("time",.32))
	weather_state = int(controller.state.world_state.get("weather",0))
	rain_intensity = clampf(float(controller.state.world_state.get("rain_intensity",.22)),.14,.30)
	coastal_wetness = clampf(float(controller.state.world_state.get("coastal_wetness",1.0 if weather_state in [1,2] else 0.0)),0.0,1.0)
	# Save antigo não tem o timer: começava sempre em 120 s depois de carregar.
	var saved_timer: Variant = controller.state.world_state.get("weather_timer",weather_timer)
	if typeof(saved_timer) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(saved_timer)):
		weather_timer = clampf(float(saved_timer),1.0,600.0)
	_sync_external_state()
	precipitation = GPUParticles3D.new()
	precipitation.amount = 600
	precipitation.lifetime = 1.6
	COVERAGE.configure(precipitation)
	precipitation.visibility_aabb = AABB(Vector3(-18,-20,-18),Vector3(36,40,36))
	var quad := QuadMesh.new()
	quad.size = Vector2(.07,.45)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.6,.76,.85,.6)
	material.albedo_texture = PARTICLE_TEXTURES.texture("rain")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = material
	precipitation.draw_pass_1 = quad
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(16,1,16)
	process.direction = Vector3(.1,-1,.05)
	process.spread = 1
	process.initial_velocity_min = 12
	process.initial_velocity_max = 18
	process.gravity = Vector3(0,-5,0)
	precipitation.process_material = process
	controller.world.add_child(precipitation)
	# Carros molham e secam por conta própria (umidade por veículo, abrigo por raio).
	var vehicle_rain := preload("res://gameplay/vehicle_effects/VehicleRain.gd").new()
	vehicle_rain.name = "VehicleRain"
	vehicle_rain.weather = self
	add_child(vehicle_rain)
	# Separate hail keeps the original snow layer visible during the icy front.
	hail = GPUParticles3D.new()
	hail.amount = 300
	hail.lifetime = .55
	hail.visibility_aabb = precipitation.visibility_aabb
	hail.draw_pass_1 = quad.duplicate(true)
	hail.draw_pass_1.size = Vector2(.035,.16)
	hail.draw_pass_1.material.albedo_color = Color(.85,.96,1,.9)
	hail.draw_pass_1.material.albedo_texture = PARTICLE_TEXTURES.texture("hail")
	var hail_process := process.duplicate() as ParticleProcessMaterial
	hail_process.direction = Vector3(-.65,-1,0).normalized()
	hail_process.initial_velocity_min = 900.0/16.0
	hail_process.initial_velocity_max = 1300.0/16.0
	hail_process.spread = 5
	hail_process.gravity = Vector3.ZERO
	hail.process_material = hail_process
	hail.emitting = false
	controller.world.add_child(hail)
	# Independent rain/snow emitters crossfade geographically. Reusing one mesh
	# used to turn all living raindrops into snow at the logical region seam.
	snow = GPUParticles3D.new()
	snow.amount = 400
	snow.lifetime = 2.2
	snow.visibility_aabb = precipitation.visibility_aabb
	snow.draw_pass_1 = quad.duplicate(true)
	snow.draw_pass_1.size = Vector2(.09,.09)
	snow.draw_pass_1.material.albedo_texture = PARTICLE_TEXTURES.texture("snow")
	var snow_process := process.duplicate() as ParticleProcessMaterial
	snow_process.direction = Vector3(-.8,-.6,0).normalized()
	snow_process.initial_velocity_min = 180.0/16.0
	snow_process.initial_velocity_max = 380.0/16.0
	snow_process.spread = 20
	snow_process.gravity = Vector3(-200.0/16.0,-150.0/16.0,0)
	snow.process_material = snow_process
	snow.emitting = false
	controller.world.add_child(snow)
	# Configure rain only after snow/hail have their independent meshes.
	COASTAL_RAIN.configure(precipitation)
	weather_audio = preload("res://audio/weather/WeatherAudioMixer.gd").new()
	add_child(weather_audio)
	rain_audio = weather_audio.layers[0]
	storm = preload("res://runtime/atmosphere/StormPresentation.gd").new()
	storm.weather = self
	storm.mixer = weather_audio
	add_child(storm)
	surface_effects = preload("res://runtime/atmosphere/WeatherSurfaceEffects.gd").new()
	controller.world.add_child(surface_effects)
	rain_ground = preload("res://runtime/atmosphere/RainGroundPresentation.gd").new()
	controller.world.add_child(rain_ground)
	wind_audio = AudioStreamPlayer.new()
	wind_audio.stream = preload("res://audio/regional/wind_0.ogg")
	if AudioServer.get_bus_index("Ambient")>=0: wind_audio.bus = &"Ambient"
	add_child(wind_audio)
	wind_audio.finished.connect(func(): if atmosphere.weights.get("mountain",0.0)>0.001: wind_audio.play())
	_update()
func _process(delta: float) -> void:
	# Harbor moisture continues while visiting shelters/other regions; snow does
	# not fill the coastal streets and entering a room cannot dry them instantly.
	_sync_external_state()
	var rain_target := _rain_target()
	var rain_seconds := RAIN_RISE_SECONDS if rain_target > rain_level else RAIN_FALL_SECONDS
	rain_level = lerpf(rain_level,rain_target,1.0-exp(-maxf(delta,0.0)/rain_seconds))
	coastal_wetness = COASTAL_LOOK.advance_wetness(coastal_wetness,rain_level>.08,delta)
	if "--benchmark" not in OS.get_cmdline_user_args():
		var next_time := fposmod(time_of_day+delta*time_scale/DAY_LENGTH_SECONDS,1.0)
		# Virada da meia-noite conta um dia para a fase da lua (salvo no mundo).
		if next_time < time_of_day: controller.state.world_state.moon_day = moon_day()+1
		time_of_day = next_time
	# Harbor keeps its own weather. Mountain reads the persisted thermal clock.
	if controller.state.region_id != "mountain":
		if not weather_locked: weather_timer -= delta
		if weather_timer <= 0 and not weather_locked:
			_advance_natural_weather()
	var focus: Vector3 = REGIONAL_ATMOSPHERE.focus_position(controller)
	COVERAGE.follow(precipitation,get_viewport().get_camera_3d(),focus)
	hail.global_position = focus+Vector3.UP*10
	snow.global_position = hail.global_position
	drag_rain.apply(precipitation,get_viewport().get_camera_3d(),delta,weather_state==2)
	drag_sky.update_lightning(storm.envelope(storm.flash_age) if weather_state==2 and not _covered else 0.0,storm.flashes)
	clock += delta
	var covered: bool = _inside_shelter() or atmosphere.SHELTER.sheltered(focus) or controller.world.player.get_meta("mountain_shelter",false) or controller.world.player.get_meta("port_container_shelter",false)
	if clock >= .2 or covered!=_covered:
		atmosphere_step = clock
		clock = 0
		_update()
	surface_effects.follow_focus(focus)
	controller.state.world_state.time = time_of_day
	controller.state.world_state.weather = weather_state
	controller.state.world_state.rain_intensity = rain_intensity
	controller.state.world_state.coastal_wetness = coastal_wetness
	controller.state.world_state.weather_timer = weather_timer

## Ciclo natural como frente de tempo: não pula etapa. Céu limpo só fecha em
## nublado, tempestade só nasce de garoa e sempre afina em garoa antes de abrir.
func _advance_natural_weather() -> void:
	var roll := _weather_rng.randf()
	match weather_state:
		0: weather_state = 3
		3: weather_state = 1 if roll<.45 else 0
		1: weather_state = 2 if roll<.25 else 1 if roll<.45 else 3
		2: weather_state = 1
		_: weather_state = 0
	if weather_state==1: rain_intensity = _weather_rng.randf_range(.14,.30)
	_known_state = weather_state
	_cloud_seconds = CLOUD_NATURAL_SECONDS
	var span: Vector2 = STATE_SECONDS.get(weather_state,Vector2(180,300))
	weather_timer = _weather_rng.randf_range(span.x,span.y)

## Troca de clima feita fora do ciclo natural: a chuva aparece inteira na hora.
func _sync_external_state() -> void:
	if weather_state==_known_state: return
	_known_state = weather_state
	rain_level = _rain_target()
	_cloud_seconds = CLOUD_FORCED_SECONDS

func _rain_target() -> float:
	return 1.0 if weather_state==2 else rain_intensity if weather_state==1 else 0.0

## Dia do ciclo lunar. Save antigo sem o campo começa no quarto crescente,
## para a primeira noite já ter alguma lua.
func moon_day() -> int:
	return int(controller.state.world_state.get("moon_day", 2))

## Fração iluminada da lua (0 nova, 1 cheia), como a fase real: (1-cos)/2.
func moon_illumination() -> float:
	var phase := fposmod((float(moon_day())+time_of_day)/MOON_CYCLE_DAYS,1.0)
	return (1.0-cos(phase*TAU))*.5

func _embedded_building() -> bool:
	if controller.session == null: return false
	if controller.session.get("service_roofs") != null and controller.session.service_roofs.is_active(): return true
	return controller.session.get("building_entrance") != null and controller.session.building_entrance.in_building()

func _inside_shelter() -> bool:
	if controller.session != null and controller.session.get("service_roofs") != null and controller.session.service_roofs.is_active(): return false
	if _embedded_building(): return not controller.session.building_entrance.on_rooftop()
	return not controller.state.place_id.is_empty()

func _update() -> void:
	_sync_external_state()
	var daylight := clampf(sin((time_of_day-.25)*TAU)*1.5+.25,0,1)
	var inside: bool = not controller.state.place_id.is_empty() and not _embedded_building()
	var mountain: bool = controller.state.region_id == "mountain"
	mountain_weather = {}
	if controller.session != null and controller.session.cold != null:
		mountain_weather = controller.session.cold.weather_sample()
	var front: float = float(mountain_weather.get("front",0.0))
	var focus: Vector3 = REGIONAL_ATMOSPHERE.focus_position(controller)
	var regional_weight: float = REGIONAL_ATMOSPHERE.weights_at(focus).mountain
	var desert: float = REGIONAL_ATMOSPHERE.desert_weight(focus)
	var rain_exposure := (1.0-regional_weight)*(1.0-desert)
	var target_clouds := _harbor_overcast()
	_visual_clouds = target_clouds if _visual_clouds < 0.0 else lerpf(_visual_clouds,target_clouds,1.0-exp(-maxf(atmosphere_step,0.0)/_cloud_seconds))
	var local_clouds := _visual_clouds*(1.0-desert)
	var clouds: float = lerpf(local_clouds,front,regional_weight)
	if inside: clouds = front if mountain else _harbor_overcast()
	# Preserve existing indoor base light; outdoor exposure follows the V1 clock.
	if not inside:
		daylight = REGIONAL_ATMOSPHERE.daylight_at(time_of_day)
	controller.sun.rotation_degrees.x = -15-daylight*55
	# De noite a luz direcional é a lua: a força segue a fase e as nuvens a
	# encobrem mais do que encobrem o sol (céu fechado = noite escura).
	var moon := moon_illumination()*(1.0-clouds*.75)
	controller.sun.light_energy = lerpf(lerpf(MOON_LIGHT_NEW,MOON_LIGHT_FULL,moon),1.6,daylight)*lerpf(1.0,.58,clouds)
	var clear_sun := HARBOR_SUN_NIGHT.lerp(HARBOR_SUN_DAY,daylight)
	controller.sun.light_color = clear_sun.lerp(HARBOR_OVERCAST_LIGHT,clouds*.72)
	var clear_ambient := HARBOR_AMBIENT_NIGHT.lerp(HARBOR_AMBIENT_DAY,daylight)
	controller.environment.environment.ambient_light_color = clear_ambient.lerp(HARBOR_OVERCAST_LIGHT,clouds*.46)
	controller.environment.environment.ambient_light_energy = lerpf(lerpf(MOON_AMBIENT_NEW,MOON_AMBIENT_FULL,moon),.65,daylight)*lerpf(1.0,.82,clouds)
	var clear_sky := HARBOR_SKY_NIGHT.lerp(HARBOR_SKY_FULL_MOON,moon).lerp(HARBOR_SKY_DAY,daylight)
	# Isolated interiors are cutaway rooms, not floating platforms in the sky.
	controller.environment.environment.background_color = Color("10151a") if inside else clear_sky.lerp(HARBOR_SKY_OVERCAST,clouds*.78)
	atmosphere.apply(controller,time_of_day,local_clouds,front,inside,atmosphere_step)
	if not inside:
		DESERT_MOON.apply(controller.sun,controller.environment.environment,daylight,clouds,moon,REGIONAL_ATMOSPHERE.desert_weight(focus))
	# A storm closes the distant sky without hiding nearby streets or actors.
	# Reuse the existing depth fog and lighting, fading out toward Mountain.
	if not inside and _visual_clouds > .72:
		var storm_weight := rain_exposure*smoothstep(.72,1.0,_visual_clouds)
		var env: Environment = controller.environment.environment
		var storm_sky := Color("111923").lerp(Color("424e5b"),daylight)
		env.background_color = env.background_color.lerp(storm_sky,storm_weight)
		env.fog_light_color = env.fog_light_color.lerp(storm_sky,storm_weight*.8)
		env.fog_sky_affect = lerpf(env.fog_sky_affect,.92,storm_weight)
		controller.sun.light_energy *= lerpf(1.0,.72,storm_weight)
	# Release before the next sky owner snapshots the environment. Otherwise a
	# coast -> drag strip -> coast -> interior trip can retain our own sky.
	if inside or rain_exposure <= .001:
		coastal_look.release(controller.environment.environment)
	drag_sky.apply(controller.environment.environment,focus,time_of_day,clouds,moon_illumination(),inside)
	if drag_sky.installed:
		# Preserve depth fog on terrain while keeping the cloud deck visible.
		controller.environment.environment.fog_sky_affect = minf(controller.environment.environment.fog_sky_affect,.38)
	coastal_look.apply(controller.environment.environment,controller.sun,daylight,local_clouds,coastal_wetness,rain_exposure,inside,time_of_day)
	# One shared road material per Harbor geometry, independent of chunk count.
	if controller.world.production != null:
		var harbor = controller.world.production.regions.get("harbor")
		if is_instance_valid(harbor) and harbor.harbor_road_geometry != null:
			harbor.harbor_road_geometry.set_weather_wetness(coastal_wetness)
	if controller.world.production != null:
		var night_lights := 1.0-smoothstep(.25,.70,REGIONAL_ATMOSPHERE.daylight_at(time_of_day))
		if is_instance_valid(controller.world.production.connection):
			controller.world.production.connection.set_night_lights(night_lights)
		var mountain_region = controller.world.production.regions.get("mountain")
		if is_instance_valid(mountain_region): mountain_region.set_night_lights(night_lights)
		var desert_region = controller.world.production.regions.get("desert")
		if is_instance_valid(desert_region): desert_region.set_night_lights(night_lights)
	var covered: bool = _inside_shelter() or atmosphere.SHELTER.sheltered(focus) or controller.world.player.get_meta("mountain_shelter",false) or controller.world.player.get_meta("port_container_shelter",false)
	_covered = covered
	# Stopping emission leaves living particles visible for up to 2.2 seconds.
	# Hide those particles in the same frame as entering a covered place.
	precipitation.visible = not covered and rain_exposure>.001
	hail.visible = not covered and regional_weight > .001
	snow.visible = not covered and regional_weight > .001
	var storm_state: int = int(mountain_weather.get("state",0))
	var rain_strength := rain_strength_at(focus)
	# Preserve drizzle density; reserve the additional drops for heavy rain.
	precipitation.amount_ratio = rain_strength*lerpf(1000.0/COASTAL_RAIN.MAX_DROPS,1.0,smoothstep(.35,1.0,rain_strength))
	precipitation.speed_scale = lerpf(.65,1.0,rain_strength)
	COASTAL_RAIN.apply(precipitation,rain_strength,daylight,get_viewport().get_camera_3d())
	rain_ground.set_conditions(focus,rain_strength,daylight,covered)
	precipitation.emitting = not covered and rain_strength>.001
	snow.emitting = not covered and storm_state>0 and regional_weight>.001
	snow.amount_ratio = regional_weight*(150.0 if storm_state==1 else 260.0 if storm_state==3 else 400.0)/400.0
	snow.speed_scale = lerpf(.45,1.15,front)
	snow.draw_pass_1.material.albedo_color = Color(1,1,1,front*.9)
	hail.emitting = not covered and storm_state==3 and regional_weight>.001
	hail.amount_ratio = smoothstep(.85,1.0,front)*regional_weight
	weather_audio.set_conditions(rain_strength,covered)
	weather_audio.set_interior_silence(inside)
	weather_audio.set_dialogue_focus(controller.session!=null and controller.session.get("dialogue_open")==true)
	# Raio só quando a chuva já engrossou: a tempestade chega, não estoura.
	storm.sync(rain_exposure*smoothstep(.55,.9,rain_level),covered)
	var palette: Dictionary = atmosphere.current
	surface_effects.set_conditions(focus,hail.amount_ratio if hail.emitting else 0.0,float(palette.get("haze",0)),palette.get("fog_color",Color.WHITE),covered,desert,_harbor_overcast())
	wind_audio.volume_db = lerpf(-30,-17,float(mountain_weather.get("intensity",0.0)))-(14.0 if covered else 0.0)+linear_to_db(maxf(.001,regional_weight))
	if regional_weight>.001 and not wind_audio.playing: wind_audio.play()
	elif regional_weight<=.001: wind_audio.stop()

## Regional precipitation also drives wheel spray and puddles. The saved Harbor
## weather remains intact while the desert presents dry wind instead.
func rain_strength_at(point: Vector3) -> float:
	_sync_external_state()
	return rain_level*(1.0-REGIONAL_ATMOSPHERE.weights_at(point).mountain)*(1.0-REGIONAL_ATMOSPHERE.desert_weight(point))

func _harbor_overcast() -> float:
	match weather_state:
		1: return .72 # V1 drizzle: cool, readable and visibly distinct from clear day.
		2: return 1.0 # Heavy storm, natural or explicitly activated.
		3: return .52
		_: return 0.0

func get_coastal_wetness() -> float:
	return coastal_wetness

func get_city_lighting_factor() -> float:
	var daylight := REGIONAL_ATMOSPHERE.daylight_at(time_of_day)
	var night := 1.0-smoothstep(.18,.62,daylight)
	# Cloudy daylight B stays natural; rain C brings warm existing fittings on
	# gradually, with the same six-source pool and no extra shadow casters.
	var rain_light := smoothstep(.54,.80,maxf(_visual_clouds,0.0))*.52
	return maxf(night,rain_light)
