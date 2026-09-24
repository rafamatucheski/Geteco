extends RefCounted
## V1 art controls translated to native 3D, with no scene scans or new lights.
const PALETTE := preload("res://runtime/atmosphere/AtmospherePalette.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const CEMETERY := preload("res://world/regions/OriginalCemetery3D.gd")
const SHELTER := preload("res://runtime/cold/OriginalHeatSources.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
var current: Dictionary = {}
var weights: Dictionary = {}

static func focus_position(controller) -> Vector3:
	var driving = controller.world.get("driving")
	if driving != null and driving.occupied and is_instance_valid(driving.car):
		return driving.car.global_position
	return controller.world.player.global_position

# Original DayNightWeatherManager keyframes. Brightness and chroma are separated
# for 3D lights, as V1 already did before its regional composition pass.
const HOURS := [0.0,.19,.24,.30,.36,.68,.74,.79,.84,.88,1.0]
const CLOCK_COLORS := [Color(.25,.29,.40),Color(.25,.29,.40),
	Color(.61,.67,.73),Color(.91,.82,.74),Color.WHITE,Color.WHITE,
	Color(1,.88,.70),Color(1,.62,.38),Color(.52,.44,.58),
	Color(.25,.29,.40),Color(.25,.29,.40)]

static func clock_color(hour: float) -> Color:
	var h := fposmod(hour,1.0)
	for i in range(1,HOURS.size()):
		if h <= HOURS[i]:
			return CLOCK_COLORS[i-1].lerp(CLOCK_COLORS[i],(h-HOURS[i-1])/(HOURS[i]-HOURS[i-1]))
	return CLOCK_COLORS[0]

static func daylight_at(hour: float) -> float:
	var night: float = CLOCK_COLORS[0].get_luminance()
	return clampf((clock_color(hour).get_luminance()-night)/(1.0-night),0,1)

static func weights_at(point: Vector3) -> Dictionary:
	var original := Vector2(point.x,point.z)*16.0
	var local := original-PLACES.MOUNTAIN_OFFSET
	var mountain := PALETTE.mountain_weight(original,PLACES.MOUNTAIN_OFFSET)
	return {"mountain":mountain,"summit":PALETTE.summit_weight(local),
		"resort":PALETTE.resort_weight(local)*mountain,
		"cemetery":PALETTE.cemetery_weight(original-CEMETERY.SOURCE_CENTER,Vector2(780,700))*(1.0-mountain)}

static func sample_at(point: Vector3, hour: float, clouds: float, snow: float) -> Dictionary:
	var w := weights_at(point)
	var result := PALETTE.sample(0,hour,clouds,w.mountain,w.summit,snow)
	result = PALETTE.resort_sample(result,w.resort)
	return PALETTE.cemetery_sample(result,w.cemetery)

func apply(controller, hour: float, clouds: float, snow: float, inside: bool, delta: float) -> void:
	var point := focus_position(controller)
	weights = weights_at(point)
	var env: Environment = controller.environment.environment
	if inside:
		env.fog_enabled = false
		env.adjustment_enabled = false
		current.clear()
		return
	var target := sample_at(point,hour,clouds,snow)
	current = target if current.is_empty() else PALETTE.blend(current,target,1.0-exp(-delta*3.0))
	controller.sun.light_color *= current.sunlight_tint
	var clock_tint := clock_color(hour)
	var luminance := clock_tint.get_luminance()
	var dusk := smoothstep(.67,.76,hour)*(1.0-smoothstep(.78,.88,hour))
	clock_tint = clock_tint.lerp(Color(luminance,luminance,luminance),dusk*.70)
	var chroma := clock_tint/maxf(clock_tint.r,maxf(clock_tint.g,clock_tint.b))
	var regional_clouds: float = lerpf(clouds,snow,weights.mountain)
	controller.sun.light_color *= Color.WHITE.lerp(chroma,(1.0-regional_clouds)*daylight_at(hour))
	# The open water crossing gets direct sun from every side. Ease the local
	# daytime exposure across the approach and bridge without a light seam.
	var bridge_x := smoothstep(395.0,415.0,point.x)*(1.0-smoothstep(565.0,590.0,point.x))
	var bridge_z := 1.0-smoothstep(18.0,45.0,absf(point.z-WORLD_CONNECTION.CENTER_Z))
	var bridge_day := bridge_x*bridge_z*daylight_at(hour)
	controller.sun.light_energy *= 1.0-0.16*bridge_day
	env.ambient_light_energy *= 1.0-0.08*bridge_day
	env.ambient_light_color *= current.shadow_tint
	env.adjustment_enabled = true
	env.adjustment_saturation = current.saturation
	env.adjustment_contrast = current.contrast
	# Depth fog supported by Mobile: keep nearby obstacles clear and distant
	# scenery softer. Shelter suppresses exterior mist, never the world clock.
	env.fog_enabled = not SHELTER.sheltered(point) and not controller.world.player.get_meta("mountain_shelter",false)
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = current.fog_color
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_density = current.haze
	env.fog_depth_begin = 18.0
	env.fog_depth_end = 75.0
	env.fog_depth_curve = 1.25
	env.fog_sky_affect = current.distant_haze
	# Higher moon removes the huge grazing-angle shadow wedges at night.
	var daylight := daylight_at(hour)
	controller.sun.rotation_degrees.x = -lerpf(42.0,70.0,daylight)
