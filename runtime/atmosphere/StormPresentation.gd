extends Node
## V1 thunder cadence and delayed audio, translated to the shared 3D sunlight.
## One reusable world discharge; no transient lights or delayed timer callbacks.
const BOLT := preload("res://runtime/atmosphere/LightningBolt3D.gd")
const MIN_STRIKE_DISTANCE := 9.0
const MAX_STRIKE_DISTANCE := 55.0
const STRIKE_ATTEMPTS := 6
var weather
var mixer
var bolt: Node3D
# Process-local diagnostic switch; does not change weather or persistent state.
var bolts_enabled := true
var strike_position := Vector3.INF
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
var _bolt_rng := RandomNumberGenerator.new()
var _strike_focus := Vector3.ZERO

func _ready() -> void:
	# Weather updates coverage and the baseline light at priority 100.
	process_priority = 101
	_rng.randomize()
	bolt = BOLT.new()
	bolt.name = "LightningBolt"
	add_child(bolt)

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
	strike_position = Vector3.INF
	if is_instance_valid(bolt): bolt.clear()
	if is_instance_valid(mixer) and is_instance_valid(mixer.thunder): mixer.thunder.stop()
	_apply_flash()

func trigger_lightning() -> bool:
	if _exposure<=.001 or weather.weather_state!=2 or thunder_delay>=0 or flash_age<.57: return false
	flash_age = 0.0
	thunder_delay = _rng.randf_range(.8,3.2)
	lightning_timer = _rng.randf_range(14,26)
	flashes += 1
	_strike_focus = _focus_position()
	strike_position = Vector3.INF
	if is_instance_valid(bolt):
		bolt.clear()
		# The race sky already renders its own distant discharge. Keep one event.
		var local_sky: Variant = weather.get("drag_sky")
		var sky_has_bolt: bool = local_sky != null and local_sky.installed
		if bolts_enabled and not sky_has_bolt:
			# Geometry never consumes the cadence RNG or the gameplay/global RNG.
			_bolt_rng.seed = _rng.state
			strike_position = _pick_strike_position(_strike_focus)
			if strike_position.is_finite():
				bolt.strike(strike_position,_bolt_rng)
				thunder_delay = maxf(.12,strike_position.distance_to(_strike_focus)/343.0)
	return true

func _focus_position() -> Vector3:
	var world: Node3D = weather.controller.world
	var driving: Variant = world.get("driving")
	if driving != null and driving.occupied and is_instance_valid(driving.car):
		return driving.car.global_position
	return world.player.global_position

func _pick_strike_position(focus: Vector3) -> Vector3:
	var world: Node3D = weather.controller.world
	var camera := get_viewport().get_camera_3d()
	var space := world.get_world_3d().direct_space_state
	for attempt in STRIKE_ATTEMPTS:
		var point: Vector3
		if is_instance_valid(camera):
			var viewport_size := camera.get_viewport().get_visible_rect().size
			var side := _bolt_rng.randf_range(.12,.30)
			if _bolt_rng.randf() > .5: side = 1.0-side
			var screen := viewport_size*Vector2(side,_bolt_rng.randf_range(.40,.70))
			var origin := camera.project_ray_origin(screen)
			var direction := camera.project_ray_normal(screen)
			if direction.y >= -.1: continue
			point = origin+direction*((focus.y-origin.y)/direction.y)
		else:
			var angle := _bolt_rng.randf_range(0,TAU)
			point = focus+Vector3(cos(angle),0,sin(angle))*_bolt_rng.randf_range(14,28)
		var distance := Vector2(point.x-focus.x,point.z-focus.z).length()
		if distance < MIN_STRIKE_DISTANCE or distance > MAX_STRIKE_DISTANCE: continue
		# Static surfaces only: never attach a strike to an actor or moving car.
		# Start above roofs, so the discharge stops at the first exposed surface.
		var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*80,point-Vector3.UP*80,1)
		var hit := space.intersect_ray(query)
		if hit.is_empty(): continue
		var normal: Vector3 = hit.normal
		if normal.y < .5: continue
		point = hit.position+Vector3.UP*.025
		if weather.rain_strength_at(point) < .55: continue
		if is_instance_valid(camera):
			if camera.is_position_behind(point): continue
			var rect := camera.get_viewport().get_visible_rect()
			if not rect.grow(-rect.size.y*.12).has_point(camera.unproject_position(point)): continue
		return point
	# Preserve a cloud flash if no suitable visible collision surface exists.
	return Vector3.INF

static func envelope(age: float) -> float:
	if age<0 or age>=.57: return 0
	if age<.05: return age/.05
	if age<.13: return lerpf(1.0,.08,(age-.05)/.08)
	if age<.17: return lerpf(.08,.75,(age-.13)/.04)
	return .75*pow(1.0-(age-.17)/.4,2)

func _process(delta: float) -> void:
	if weather.weather_state != 2 and _exposure > .001:
		_exposure = 0.0
		cancel()
	if (thunder_delay >= 0 or flash_age < .57) and _focus_position().distance_to(_strike_focus) > 80.0:
		cancel()
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
	if is_instance_valid(bolt): bolt.set_strength(strength if bolts_enabled else 0.0)
	if strength<=0 and not _applied: return
	var sun: DirectionalLight3D = weather.controller.sun
	var env: Environment = weather.controller.environment.environment
	sun.light_energy = _base_sun+strength*.85
	sun.light_color = _base_color.lerp(Color(.78,.87,1),strength*.65)
	env.ambient_light_energy = _base_ambient+strength*.16
	_applied = strength>0
