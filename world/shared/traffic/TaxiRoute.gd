extends "res://world/shared/roads/EmergencyLaneRouter.gd"
## Keep the cab on its actual initial lane, never jump to oncoming traffic.
var start_lane: Path2D
var _start_query := true
func plan(car: Node2D, target: Vector2) -> Array[Dictionary]:
	_start_query = true
	_plan(car,target)
	return legs

func _nearest_lanes(lanes: Dictionary, at: Vector2) -> Array[Dictionary]:
	var candidates := super._nearest_lanes(lanes,at)
	if _start_query:
		_start_query = false
		if is_instance_valid(start_lane) and start_lane in lanes.values():
			return candidates.filter(func(item: Dictionary) -> bool: return lanes[item.id] == start_lane)
	return candidates
