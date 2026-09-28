extends Node
## V1 time/weather IDs, rendered by shared native 3D lights and local particles.
const PARTICLE_TEXTURES := preload("res://runtime/atmosphere/WeatherParticleTextures.gd")
# Productive V1 HarborGame and MountainPass both override the manager to 24 min.
const DAY_LENGTH_SECONDS := 1440.0
var controller
var time_of_day := .32
var weather_state := 0
var weather_timer := 120.0
var clock := 0.0
var precipitation: GPUParticles3D
var rain_audio: AudioStreamPlayer
var wind_audio: AudioStreamPlayer
var hail: GPUParticles3D
var snow: GPUParticles3D
var mountain_weather: Dictionary = {}
var atmosphere = preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd").new()
var atmosphere_step := .2
var weather_audio: Node
var storm: Node
var surface_effects: Node3D
var rain_intensity := .22
var _covered := false
var _weather_rng := RandomNumberGenerator.new()

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
	for channel in [wind_audio]:
		if is_instance_valid(channel):
			channel.stop()
			channel.stream = null
	for emitter in [precipitation,hail,snow]:
		if is_instance_valid(emitter): emitter.queue_free()
	if is_instance_valid(surface_effects): surface_effects.queue_free()
	PARTICLE_TEXTURES.release_cache()
func _ready() -> void:
	_weather_rng.randomize()
	time_of_day = float(controller.state.world_state.get("time",.32))
	weather_state = int(controller.state.world_state.get("weather",0))
	rain_intensity = clampf(float(controller.state.world_state.get("rain_intensity",.22)),.14,.30)
	precipitation = GPUParticles3D.new()
	precipitation.amount = 600
	precipitation.lifetime = 1.6
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
	weather_audio = preload("res://audio/weather/WeatherAudioMixer.gd").new()
	add_child(weather_audio)
	rain_audio = weather_audio.layers[0]
	storm = preload("res://runtime/atmosphere/StormPresentation.gd").new()
	storm.weather = self
	storm.mixer = weather_audio
	add_child(storm)
	surface_effects = preload("res://runtime/atmosphere/WeatherSurfaceEffects.gd").new()
	controller.world.add_child(surface_effects)
	wind_audio = AudioStreamPlayer.new()
	wind_audio.stream = preload("res://audio/regional/wind_0.ogg")
	if AudioServer.get_bus_index("Ambient")>=0: wind_audio.bus = &"Ambient"
	add_child(wind_audio)
	wind_audio.finished.connect(func(): if atmosphere.weights.get("mountain",0.0)>0.001: wind_audio.play())
	_update()
func _process(delta: float) -> void:
	if "--benchmark" not in OS.get_cmdline_user_args():
		var next_time := fposmod(time_of_day+delta/DAY_LENGTH_SECONDS,1.0)
		# Virada da meia-noite conta um dia para a fase da lua (salvo no mundo).
		if next_time < time_of_day: controller.state.world_state.moon_day = moon_day()+1
		time_of_day = next_time
	# Harbor keeps its own weather. Mountain reads the persisted thermal clock.
	if controller.state.region_id != "mountain":
		weather_timer -= delta
		if weather_timer <= 0:
			weather_timer = _weather_rng.randf_range(90,180)
			var roll := _weather_rng.randf()
			# Occasional heavy storms join the natural cycle; keep drizzle distinct.
			weather_state = 0 if roll<.42 else 3 if roll<.70 else 1 if roll<.92 else 2
			if weather_state==1: rain_intensity = _weather_rng.randf_range(.14,.30)
	precipitation.global_position = atmosphere.focus_position(controller)+Vector3.UP*10
	hail.global_position = precipitation.global_position
	snow.global_position = precipitation.global_position
	clock += delta
	var focus: Vector3 = atmosphere.focus_position(controller)
	var covered: bool = not controller.state.place_id.is_empty() or atmosphere.SHELTER.sheltered(focus) or controller.world.player.get_meta("mountain_shelter",false) or controller.world.player.get_meta("port_container_shelter",false)
	if clock >= .2 or covered!=_covered:
		atmosphere_step = clock
		clock = 0
		_update()
	controller.state.world_state.time = time_of_day
	controller.state.world_state.weather = weather_state
	controller.state.world_state.rain_intensity = rain_intensity
## Dia do ciclo lunar. Save antigo sem o campo começa no quarto crescente,
## para a primeira noite já ter alguma lua.
func moon_day() -> int:
	return int(controller.state.world_state.get("moon_day", 2))

## Fração iluminada da lua (0 nova, 1 cheia), como a fase real: (1-cos)/2.
func moon_illumination() -> float:
	var phase := fposmod((float(moon_day())+time_of_day)/MOON_CYCLE_DAYS,1.0)
	return (1.0-cos(phase*TAU))*.5

func _update() -> void:
	var daylight := clampf(sin((time_of_day-.25)*TAU)*1.5+.25,0,1)
	var inside: bool = not controller.state.place_id.is_empty()
	var mountain: bool = controller.state.region_id == "mountain"
	mountain_weather = {}
	if controller.session != null and controller.session.cold != null:
		mountain_weather = controller.session.cold.weather_sample()
	var front: float = float(mountain_weather.get("front",0.0))
	var focus: Vector3 = atmosphere.focus_position(controller)
	var regional_weight: float = atmosphere.weights_at(focus).mountain
	var clouds: float = lerpf(_harbor_overcast(),front,regional_weight)
	if inside: clouds = front if mountain else _harbor_overcast()
	# Preserve existing indoor base light; outdoor exposure follows the V1 clock.
	if not inside:
		daylight = atmosphere.daylight_at(time_of_day)
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
	atmosphere.apply(controller,time_of_day,_harbor_overcast(),front,inside,atmosphere_step)
	# A storm closes the distant sky without hiding nearby streets or actors.
	# Reuse the existing depth fog and lighting, fading out toward Mountain.
	if not inside and weather_state == 2:
		var storm_weight := 1.0-regional_weight
		var env: Environment = controller.environment.environment
		var storm_sky := Color("111923").lerp(Color("424e5b"),daylight)
		env.background_color = env.background_color.lerp(storm_sky,storm_weight)
		env.fog_light_color = env.fog_light_color.lerp(storm_sky,storm_weight*.8)
		env.fog_sky_affect = lerpf(env.fog_sky_affect,.92,storm_weight)
		controller.sun.light_energy *= lerpf(1.0,.72,storm_weight)
	if controller.world.production != null:
		var night_lights := 1.0-smoothstep(.25,.70,atmosphere.daylight_at(time_of_day))
		if is_instance_valid(controller.world.production.connection):
			controller.world.production.connection.set_night_lights(night_lights)
		var mountain_region = controller.world.production.regions.get("mountain")
		if is_instance_valid(mountain_region): mountain_region.set_night_lights(night_lights)
	var covered: bool = inside or atmosphere.SHELTER.sheltered(focus) or controller.world.player.get_meta("mountain_shelter",false) or controller.world.player.get_meta("port_container_shelter",false)
	_covered = covered
	# Stopping emission leaves living particles visible for up to 2.2 seconds.
	# Hide those particles in the same frame as entering a covered place.
	precipitation.visible = not covered
	hail.visible = not covered and regional_weight > .001
	snow.visible = not covered and regional_weight > .001
	var storm_state: int = int(mountain_weather.get("state",0))
	var rain_strength := (1.0 if weather_state==2 else rain_intensity if weather_state==1 else 0.0)*(1.0-regional_weight)
	precipitation.amount_ratio = rain_strength
	precipitation.speed_scale = lerpf(.65,1.0,rain_strength)
	precipitation.draw_pass_1.material.albedo_color.a = lerpf(.38,.65,rain_strength)
	precipitation.emitting = not covered and weather_state in [1,2] and regional_weight<.999
	snow.emitting = not covered and storm_state>0 and regional_weight>.001
	snow.amount_ratio = regional_weight*(150.0 if storm_state==1 else 260.0 if storm_state==3 else 400.0)/400.0
	snow.speed_scale = lerpf(.45,1.15,front)
	snow.draw_pass_1.material.albedo_color = Color(1,1,1,front*.9)
	hail.emitting = not covered and storm_state==3 and regional_weight>.001
	hail.amount_ratio = smoothstep(.85,1.0,front)*regional_weight
	weather_audio.set_conditions(rain_strength,covered)
	weather_audio.set_interior_silence(inside)
	weather_audio.set_dialogue_focus(controller.session!=null and controller.session.get("dialogue_open")==true)
	storm.sync(1.0-regional_weight,covered)
	var palette: Dictionary = atmosphere.current
	surface_effects.set_conditions(focus,hail.amount_ratio if hail.emitting else 0.0,float(palette.get("haze",0)),palette.get("fog_color",Color.WHITE),covered)
	wind_audio.volume_db = lerpf(-30,-17,float(mountain_weather.get("intensity",0.0)))-(14.0 if covered else 0.0)+linear_to_db(maxf(.001,regional_weight))
	if regional_weight>.001 and not wind_audio.playing: wind_audio.play()
	elif regional_weight<=.001: wind_audio.stop()

func _harbor_overcast() -> float:
	match weather_state:
		1: return .72 # V1 drizzle: cool, readable and visibly distinct from clear day.
		2: return 1.0 # Heavy storm, natural or explicitly activated.
		3: return .52
		_: return 0.0
