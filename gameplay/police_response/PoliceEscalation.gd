extends RefCounted
## Consequências confirmadas, não a cadência de tiro da arma, governam a resposta.
const SHOT_EPISODE_SECONDS := 3.0
const FATAL_POINTS_FIVE := 180
const FATAL_POINTS_SIX := 360
const MIN_SECONDS_FIVE := 60.0
const MIN_SECONDS_SIX := 120.0
var incident_seconds := 0.0
var fatal_points := 0
var shot_cooldown := 0.0

func tick(delta: float, wanted: bool) -> void:
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	if wanted: incident_seconds = minf(MIN_SECONDS_SIX, incident_seconds + delta)

func accept(points: int, current: int, kind: String) -> int:
	var ceiling := 139 # Alarms/theft cannot summon the heaviest forces.
	if kind in ["gunfire", "suppressed"]:
		ceiling = 59
		if shot_cooldown > 0.0: return 0
		shot_cooldown = SHOT_EPISODE_SECONDS
		points = mini(points, 1 if kind == "suppressed" else 4)
	elif kind in ["assault", "police_assault", "vehicle_assault", "explosion"]:
		ceiling = 259
	elif kind in ["civilian_killed", "police_killed"]:
		fatal_points = mini(600, fatal_points + (mini(points, 30) if kind == "police_killed" else points))
		ceiling = 259
		if fatal_points >= FATAL_POINTS_FIVE and incident_seconds >= MIN_SECONDS_FIVE: ceiling = 419
		if fatal_points >= FATAL_POINTS_SIX and incident_seconds >= MIN_SECONDS_SIX: ceiling = 600
	elif kind == "police_theft":
		ceiling = 59
	return mini(points, maxi(0, ceiling - current))

func snapshot() -> Dictionary:
	return {"seconds": incident_seconds, "fatal": fatal_points, "shot": shot_cooldown}

static func validate(data: Dictionary) -> bool:
	for key in ["seconds", "fatal", "shot"]:
		if typeof(data.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key]) < 0.0: return false
	return data.seconds <= MIN_SECONDS_SIX and data.fatal <= 600 and float(data.fatal) == floorf(float(data.fatal)) and data.shot <= SHOT_EPISODE_SECONDS

func restore(data: Dictionary) -> void:
	incident_seconds = float(data.get("seconds", 0.0))
	fatal_points = int(data.get("fatal", 0))
	shot_cooldown = float(data.get("shot", 0.0))
