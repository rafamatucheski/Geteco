extends RefCounted
## Shared palette for the Harbor approach and Mountain Pass bridge.
const ASPHALT := Color("202932")
const SHOULDER := Color("aaa9a1")
const CURB := Color("70767a")
const EDGE := Color(0.92, 0.94, 0.96, 0.85)
const WEAR := ASPHALT
const LANE := Color("dfc84d")
const MARKING_WIDTH := 3.0
const DASH_LENGTH := 28.0
const DASH_GAP := 26.0


static func dashed_multiline(points: PackedVector2Array, initial_phase := 0.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.size() < 2:
		return result
	var travelled := fposmod(initial_phase, DASH_LENGTH + DASH_GAP)
	var cycle_length := DASH_LENGTH + DASH_GAP
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		var segment_length := a.distance_to(b)
		if segment_length <= 0.01:
			continue
		var direction := a.direction_to(b)
		var walked := 0.0
		while walked < segment_length - 0.01:
			var phase := fmod(travelled + walked, cycle_length)
			var drawing := phase < DASH_LENGTH
			var remaining := (DASH_LENGTH - phase) if drawing else (cycle_length - phase)
			var step := minf(remaining, segment_length - walked)
			if drawing and step > 0.5:
				result.append(a + direction * walked)
				result.append(a + direction * (walked + step))
			walked += maxf(step, 0.5)
		travelled += segment_length
	return result


static func dashed_segments(points: PackedVector2Array, initial_phase := 0.0) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var multiline := dashed_multiline(points, initial_phase)
	for index in range(0, multiline.size(), 2):
		result.append(PackedVector2Array([multiline[index], multiline[index + 1]]))
	return result
