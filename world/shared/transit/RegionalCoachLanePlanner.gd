extends "res://cars/traffic/TaxiRoute.gd"
## Both ends are pinned to directed lanes; an opposite carriageway is not a goal.
var goal_lane: Path2D

func _nearest_lanes(lanes: Dictionary, point: Vector2) -> Array[Dictionary]:
	var start_query := _start_query
	var candidates := super._nearest_lanes(lanes, point)
	if not start_query and is_instance_valid(goal_lane):
		return candidates.filter(func(item: Dictionary) -> bool: return lanes[item.id] == goal_lane)
	return candidates
