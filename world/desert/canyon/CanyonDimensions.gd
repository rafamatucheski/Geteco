extends RefCounted
## Geology-only reshaping. Human bodies, the camp and the bridge width never scale.
## Source coordinates describe the gorge after the desert's rigid west relocation.
const SOURCE_BOUNDS := Rect2(-1340,-790,270,360)
const CENTER_X := -1204.0
const FIXED_END_Z := -530.0
const SOURCE_DEPTH := 72.0
const WIDTH_FACTOR := .6
const LENGTH_FACTOR := .3
const DEPTH_FACTOR := .3

static func source_to_field(point: Vector2) -> Vector2:
	var z := FIXED_END_Z+(point.y-FIXED_END_Z)*LENGTH_FACTOR if point.y<FIXED_END_Z else point.y
	return Vector2(CENTER_X+(point.x-CENTER_X)*WIDTH_FACTOR,z)

static func field_to_source(point: Vector2) -> Vector2:
	var z := FIXED_END_Z+(point.y-FIXED_END_Z)/LENGTH_FACTOR if point.y<FIXED_END_Z else point.y
	return Vector2(CENTER_X+(point.x-CENTER_X)/WIDTH_FACTOR,z)
