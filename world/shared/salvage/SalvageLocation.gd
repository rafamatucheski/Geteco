extends RefCounted
const HARBOR_CENTER := Vector2(-750, 550)
const LEGACY_CENTER := Vector2(-2150, -1150)
const LAND := Rect2(-620, -540, 1270, 1120)
const YARD := Rect2(-520, -310, 1040, 650)

static func center(legacy: bool) -> Vector2:
	return LEGACY_CENTER if legacy else HARBOR_CENTER

static func access(legacy: bool) -> PackedVector2Array:
	var c := center(legacy)
	if legacy:
		return PackedVector2Array([Vector2(870, 100),Vector2(870,-500),Vector2(c.x,-500),c+Vector2(0,150)])
	return PackedVector2Array([Vector2(-1250,1250),Vector2(-1250,1000),Vector2(c.x,1000),c+Vector2(0,150)])

static func safe_load_position(point: Vector2, legacy: bool) -> Vector2:
	var c := center(legacy)
	# Old isolated yard saves resume on the connected access, including cars.
	if not legacy and Rect2(Vector2(-2250,350)+Vector2(-820,-540),Vector2(1640,1120)).has_point(point):
		return c+Vector2(0,470)
	if YARD.grow(35).has_point(point-c): return c+Vector2(0,470)
	var old := Vector2(900,330) if legacy else Vector2(8150,1780)
	if Rect2(old-Vector2(180,140),Vector2(370,290)).has_point(point):
		return Vector2(1272,448) if legacy else Vector2(8000,1850)
	return point
