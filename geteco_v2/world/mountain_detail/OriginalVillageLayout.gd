extends RefCounted
## All public coordinates are MOUNTAIN-LOCAL, before the region streaming offset.
const ORIGIN := Vector2(7560, -1650)
const RESERVATION_BOUNDS := Rect2(7310, -2010, 690, 720)
const BERTH := Vector2(7500, -1760)
const BERTH_HEADING := Vector2.RIGHT
const BUS_DOOR := Vector2(7537, -1730)
const STATION_SHIFT := Vector2(0,18)
const SHELTERED_WAIT := Vector2(7460, -1614)
const STATION_BOUNDS := Rect2(7395, -1687, 125, 55)
const STATION_DOOR := Vector2(7460, -1614)
const SHOP_CENTER := Vector2(7790, -1640)
const SHOP_DOOR := Vector2(7790, -1594)
const SHOP_BOUNDS := Rect2(7709, -1676, 162, 66)
const HEAT_SOURCE := Vector2(7650, -1553)
const PLAZA := Vector2(7630, -1590)
const CABIN_CENTERS := [Vector2(7405, -1480), Vector2(7545, -1480), Vector2(7725, -1440), Vector2(7870, -1440)]
const CABIN_DOORS := [Vector2(7405, -1436), Vector2(7545, -1436), Vector2(7725, -1396), Vector2(7870, -1396)]
const ACCESS_CORRIDORS := [
	[Vector2(6901, -1566), Vector2(6840, -1740), Vector2(7010, -1870), Vector2(7240, -1760), BERTH, Vector2(7700, -1760), Vector2(7790, -1850), Vector2(7700, -1940)],
	[Vector2(7700, -1940), Vector2(7010, -1940), Vector2(6880, -1890), Vector2(6750, -1810), Vector2(6630, -1680), Vector2(6694, -1600)],
]
const BUS_TO_PLAZA := [BUS_DOOR, Vector2(7550, -1718), Vector2(7550, -1590), PLAZA]
const PLAZA_TO_SHOP := [PLAZA, Vector2(7790, -1590), SHOP_DOOR]
const PLAZA_TO_WAIT := [PLAZA, Vector2(7460, -1590), SHELTERED_WAIT]
const BENCH_CENTERS := [Vector2(7418,-1613),Vector2(7498,-1613),Vector2(7646,-1508),Vector2(7678,-1560)]

static func bench_access_route(seat_point: Vector2) -> PackedVector2Array:
	if seat_point.y < -1600:
		return PackedVector2Array([PLAZA,Vector2(seat_point.x,-1585)])
	if seat_point.x < 7660:
		return PackedVector2Array([PLAZA,Vector2(7615,-1590),Vector2(7615,-1480),Vector2(seat_point.x,-1480)])
	return PackedVector2Array([PLAZA,Vector2(7706,-1590),Vector2(7706,-1532),Vector2(seat_point.x,-1532)])

static func cabin_route(index: int) -> PackedVector2Array:
	var door: Vector2 = CABIN_DOORS[index]
	# The east-side walkway turns below each cabin, never through its footprint.
	var side_x := float(CABIN_CENTERS[index].x) + 70.0
	return PackedVector2Array([PLAZA, Vector2(side_x, -1590), Vector2(side_x, door.y + 14), door + Vector2(0, 14), door])

static func is_reserved(point: Vector2) -> bool:
	if RESERVATION_BOUNDS.has_point(point):
		return true
	for path in ACCESS_CORRIDORS:
		for i in range(path.size() - 1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1])) < 82.0:
				return true
	return false
