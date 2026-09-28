extends Node
## V1 thunder cadence and delayed audio, translated to the shared 3D sunlight.
## No transient lights, tweens, or timer callbacks surviving shelter/region changes.
var weather
var mixer
var lightning_timer := 14.0
var flash_age := 1.0
var thunder_delay := -1.0
var flashes := 0
var thunder_count := 0
var _exposure := 0.0
var _base_sun := 0.0
var _base_ambient := 0.0
var _base_color := Color.WHITE
var _applied := false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func sync(exposure: float, covered: bool) -> void:
	_exposure = 0.0 if covered or weather.weather_state!=2 else exposure
	_base_sun = weather.controller.sun.light_energy
	_base_color = weather.controller.sun.light_color
	_base_ambient = weather.controller.environment.environment.ambient_light_energy
	if _exposure<=.001: cancel()
	_apply_flash()

func cancel() -> void:
	flash_age = 1.0
	thunder_delay = -1.0
	lightning_timer = 14.0
	if is_instance_valid(mixer) and is_instance_valid(mixer.thunder): mixer.thunder.stop()

func trigger_lightning() -> bool:
	if _exposure<=.001 or weather.weather_state!=2 or thunder_delay>=0: return false
	flash_age = 0.0
	thunder_delay = _rng.randf_range(.8,3.2)
	lightning_timer = _rng.randf_range(14,26)
	flashes += 1
	return true

static func envelope(age: float) -> float:
	if age<0 or age>=.57: return 0
	if age<.05: return age/.05
	if age<.13: return lerpf(1.0,.08,(age-.05)/.08)
	if age<.17: return lerpf(.08,.75,(age-.13)/.04)
	return .75*pow(1.0-(age-.17)/.4,2)

func _process(delta: float) -> void:
	if _exposure>.001:
		lightning_timer -= delta
		if lightning_timer<=0: trigger_lightning()
		if thunder_delay>=0:
			thunder_delay -= delta
			if thunder_delay<0:
				mixer.play_thunder()
				thunder_count += 1
	flash_age += delta
	_apply_flash()

func _apply_flash() -> void:
	var strength := envelope(flash_age)*_exposure
	if strength<=0 and not _applied: return
	var sun: DirectionalLight3D = weather.controller.sun
	var env: Environment = weather.controller.environment.environment
	sun.light_energy = _base_sun+strength*.85
	sun.light_color = _base_color.lerp(Color(.78,.87,1),strength*.65)
	env.ambient_light_energy = _base_ambient+strength*.16
	_applied = strength>0
