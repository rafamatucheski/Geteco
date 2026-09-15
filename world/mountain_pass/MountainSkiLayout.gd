class_name MountainSkiLayout
extends RefCounted

## Geometria canônica da área de ski. O chalé ocupa a clareira superior já
## existente e as descidas usam a face norte que o terreno de neve já desenha.
const LODGE_POSITION := Vector2(7140, -2760)
const RIDGE_Y := -3000.0
const FAR_SIDE_BOTTOM_Y := -4860.0
const LIFT_SUMMIT := Vector2(6880, -3015)
const LIFT_BASE := Vector2(7100, -4890)
const LIFT_CABLE_POINTS := [LIFT_SUMMIT, Vector2(8050,-3600), Vector2(7900,-4220), LIFT_BASE]

const COURSES := [
	{
		"id": "ski_primeira_descida",
		"name": "PRIMEIRA DESCIDA",
		"difficulty": "VERDE",
		"start": Vector2(6600, -3050),
		"checkpoints": [Vector2(6540, -3370), Vector2(6680, -3690), Vector2(6570, -4010), Vector2(6700, -4310)],
		"reward": 260,
		"best_time_bonus": 120,
		"required_clues": 0,
	},
	{
		"id": "ski_slalom_pinhal",
		"name": "SLALOM DO PINHAL",
		"difficulty": "AZUL",
		"start": Vector2(7000, -3050),
		"checkpoints": [Vector2(7160, -3370), Vector2(6890, -3680), Vector2(7240, -4010), Vector2(6900, -4370), Vector2(7100, -4690)],
		"reward": 480,
		"best_time_bonus": 220,
		"required_clues": 0,
	},
	{
		"id": "ski_pista_da_sombra",
		"name": "PISTA DA SOMBRA",
		"difficulty": "PRETA",
		"start": Vector2(7380, -3050),
		"checkpoints": [Vector2(7580, -3400), Vector2(7330, -3740), Vector2(7700, -4120), Vector2(7420, -4510), Vector2(7600, -4780)],
		"reward": 900,
		"best_time_bonus": 400,
		"required_clues": 3,
	},
]

static func all_course_points(course: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array([course.start])
	for point in course.checkpoints:
		points.append(point)
	return points

static func closest_downhill_direction(point: Vector2) -> Vector2:
	var best_distance := INF
	var best_direction := Vector2.UP
	for course in COURSES:
		var points := all_course_points(course)
		for i in range(points.size() - 1):
			var closest := Geometry2D.get_closest_point_to_segment(point, points[i], points[i + 1])
			var distance := point.distance_squared_to(closest)
			if distance < best_distance:
				best_distance = distance
				best_direction = points[i].direction_to(points[i + 1])
	return best_direction.normalized()

static func is_on_far_side(point: Vector2) -> bool:
	return point.y <= RIDGE_Y + 90.0 and point.y >= FAR_SIDE_BOTTOM_Y - 130.0 and point.x >= 6100.0 and point.x <= 7950.0
