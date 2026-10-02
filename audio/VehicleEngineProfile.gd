extends RefCounted
## V1 VehicleEngineSound family selection and authored acoustic band metadata.
const FLEET := preload("res://runtime/FleetCatalog.gd")
const GEAR_TOPS := {
	"bike_sport": [0.22, 0.37, 0.53, 0.69, 0.85, 1.0],
	"bike_cruiser": [0.25, 0.43, 0.63, 0.82, 1.0],
	"bike_urban": [0.22, 0.40, 0.61, 0.81, 1.0],
	"vq35": [0.24, 0.40, 0.57, 0.73, 0.87, 0.935, 1.0],
	"m8_v8": [0.13, 0.25, 0.38, 0.52, 0.65, 0.77, 0.88, 0.94, 1.0],
	"rosso_v12": [0.12, 0.23, 0.36, 0.51, 0.68, 0.84, 0.92, 1.0],
	"street": [0.19, 0.34, 0.51, 0.71, 0.855, 1.0],
	"sport": [0.20, 0.37, 0.56, 0.77, 0.885, 1.0],
	"muscle": [0.24, 0.45, 0.71, 0.855, 1.0],
	"suv": [0.17, 0.31, 0.47, 0.65, 0.84, 0.92, 1.0],
	"diesel": [0.16, 0.29, 0.44, 0.62, 0.82, 0.91, 1.0],
	"truck": [0.15, 0.29, 0.46, 0.64, 0.83, 0.915, 1.0],
	"tank": [0.17, 0.33, 0.54, 0.77, 1.0],
	"electric": [1.0],
	"bus": [0.14, 0.26, 0.40, 0.56, 0.76, 0.88, 1.0],
	"fire_diesel": [0.12, 0.23, 0.36, 0.50, 0.66, 0.83, 0.915, 1.0],
	"ambulance": [0.18, 0.33, 0.51, 0.72, 0.86, 1.0],
	"police": [0.16, 0.29, 0.45, 0.63, 0.83, 0.915, 1.0],
}
const NOMINAL := {
	"ambulance": [5, 7, 10, 13, 18, 24, 33],
	"bike_cruiser": [8, 10, 14, 19, 25, 34, 46],
	"bike_sport": [10, 16, 23, 34, 50, 74, 110],
	"bike_urban": [12, 16, 21, 28, 38, 52, 70],
	"bus": [3, 4, 6, 8, 10, 14, 18],
	"diesel": [5, 7, 9, 12, 16, 21, 28],
	"electric": [8, 13, 20, 30, 42, 56, 72],
	"fire_diesel": [4, 5, 7, 9, 12, 16, 21],
	"m8_v8": [7, 10, 15, 23, 34, 50, 74],
	"muscle": [6, 8, 11, 16, 22, 32, 45],
	"police": [6, 9, 13, 18, 26, 37, 52],
	"rosso_v12": [8, 11, 16, 23, 34, 49, 70],
	"sport": [7, 11, 15, 21, 31, 44, 62],
	"street": [6, 9, 13, 18, 25, 35, 50],
	"suv": [6, 8, 11, 15, 21, 30, 42],
	"truck": [4, 5, 6, 8, 11, 14, 19],
	"tank": [10, 13, 16, 20, 24, 28, 33],
	"vq35": [6, 9, 13, 18, 26, 38, 55],
}

static func family(archetype: String) -> String:
	# Match V1 VehicleEngineSound.family_for_vehicle, including the old catalogue's
	# missing engine_family fields. The V2 fleet JSON retained those omissions.
	if archetype == "maciota_m8": return "m8_v8"
	if archetype == "maciota_350z": return "vq35"
	if archetype == "porto_rosso": return "rosso_v12"
	var spec: Dictionary = FLEET.spec(archetype)
	var declared := str(spec.get("engine_family", "")).strip_edges().to_lower()
	if GEAR_TOPS.has(declared): return declared
	if str(spec.get("vehicle_kind", "car")) == "motorcycle": return "bike_urban"
	var roof := str(spec.get("roof_prop", ""))
	var mass := float(spec.get("mass", 1.0))
	var pitch := float(spec.get("engine_pitch", 1.0))
	var speed := float(spec.get("max_speed", 400.0))
	if archetype == "route_city": return "bus"
	if roof == "fire_lightbar": return "fire_diesel"
	if roof == "ambulance_lightbar": return "ambulance"
	if roof == "police_lightbar": return "police"
	if mass >= 2.4: return "truck"
	if archetype.contains("van"): return "diesel"
	if mass >= 1.45: return "suv"
	if pitch >= 1.15 or (pitch >= 1.08 and speed >= 540.0): return "sport"
	if pitch <= 0.90 and mass >= 1.15: return "muscle"
	return "street"

static func bank_family(archetype: String) -> String:
	var chosen := family(archetype)
	# V1 synthesizes Monaliza from the street profile, which is also its
	# acoustic fallback here. Electric has its own exported inverter bank.
	return chosen if NOMINAL.has(chosen) else "street"

static func drive_load(speed: float, throttle: float, braking: bool) -> float:
	# Opposite input is the service brake until the car stops and engages reverse.
	if braking or (absf(speed) > .4 and speed * throttle < 0.0): return 0.0
	return clampf(absf(throttle), 0.0, 1.0)

static func loaded_rpm(wheel_rpm: float, idle: float, p_load: float, ratio: float) -> float:
	# Drivetrain remains coupled while coasting; throttle adds a small load flare.
	var coupled := lerpf(idle, wheel_rpm, .88 + .12 * p_load)
	var launch := idle + p_load * (1.0 - idle) * .48 * (1.0 - smoothstep(.02, .14, ratio))
	return clampf(maxf(coupled, launch) + p_load * .045, idle, 1.0)
