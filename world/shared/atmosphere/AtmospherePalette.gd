extends RefCounted
const HARBOR := preload("res://world/shared/atmosphere/profiles/harbor.tres")
const FOREST := preload("res://world/shared/atmosphere/profiles/forest.tres")
const WINTER := preload("res://world/shared/atmosphere/profiles/winter.tres")
const DESERT := preload("res://world/shared/atmosphere/profiles/desert.tres")
const COAST := preload("res://world/shared/atmosphere/profiles/coast.tres")

static func blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var result := {}
	for key in a:
		result[key] = lerp(a[key], b[key], clampf(weight, 0, 1))
	return result

static func mountain_weight(point: Vector2, origin: Vector2) -> float:
	# Matches the authored eastbound bridge, including approach before the seam.
	return smoothstep(origin.x + 2400.0, origin.x + 4200.0, point.x) * (1.0 - smoothstep(origin.y + 1700.0, origin.y + 2900.0, point.y))

static func summit_weight(local_point: Vector2) -> float:
	return 1.0 - smoothstep(-1700.0, 250.0, local_point.y)

static func resort_weight(local_point: Vector2) -> float:
	# Authored promenade/lodge precinct; fades before wilderness and ski slopes.
	var distance := ((local_point - Vector2(7190, -2730)) / Vector2(470, 290)).length()
	return 1.0 - smoothstep(0.55, 1.5, distance)

static func resort_sample(outdoor: Dictionary, weight: float) -> Dictionary:
	var occupied := outdoor.duplicate()
	# Keep cold shadows and storm visibility; warm highlights from occupied areas.
	occupied.sunlight_tint *= Color(1.07, 1.015, 0.94)
	occupied.saturation = minf(1.0, outdoor.saturation + 0.07)
	occupied.contrast = lerpf(outdoor.contrast, 1.025, 0.5)
	return blend(outdoor, occupied, weight)

static func cemetery_weight(local_point: Vector2, lot_size: Vector2) -> float:
	# Use the actual lot, including its transform, rather than city coordinates.
	var normalized := local_point.abs() / (lot_size * 0.5).max(Vector2.ONE)
	return 1.0 - smoothstep(0.65, 1.35, maxf(normalized.x, normalized.y))

static func cemetery_sample(outdoor: Dictionary, weight: float) -> Dictionary:
	var quiet := outdoor.duplicate()
	quiet.shadow_tint *= Color(0.94, 0.985, 1.035)
	quiet.saturation *= 0.86
	quiet.fog_color *= Color(0.92, 0.98, 1.025)
	quiet.haze = minf(0.22, outdoor.haze + 0.035)
	quiet.wind *= 0.55
	# Lamps keep their warm highlights; night fog inherits the dark outdoor air.
	return blend(outdoor, quiet, weight)

static func sample(biome: int, hour: float, cloud: float, mountain: float, summit: float, snow: float) -> Dictionary:
	var base: Resource = HARBOR
	match biome:
		1: base = WINTER
		2: base = DESERT
		3: base = FOREST
		4: base = COAST
	var low: Dictionary = FOREST.sample(hour, snow)
	var high: Dictionary = WINTER.sample(hour, snow)
	return blend(base.sample(hour, cloud), blend(low, high, summit), mountain)
