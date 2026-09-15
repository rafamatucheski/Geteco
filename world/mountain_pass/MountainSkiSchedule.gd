class_name MountainSkiSchedule
extends RefCounted

## Gerencia o horário de operação oficial do resort de ski Cume Branco.
## Horário de funcionamento: 08:00 às 18:00 (durante a luz do dia).
## Fora desse horário as pistas e o teleférico fecham para manutenção,
## acendendo os balizadores noturnos, mas o chalé permanece como abrigo.

const OPEN_HOUR := 8.0
const CLOSE_HOUR := 18.0

static func get_current_hour(node: Node) -> float:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return 12.0
	var clock := node.get_tree().get_first_node_in_group("day_night_manager")
	if clock != null and "time_of_day" in clock:
		return fmod(float(clock.time_of_day) * 24.0, 24.0)
	return 12.0

static func is_open(node: Node) -> bool:
	var h := get_current_hour(node)
	return h >= OPEN_HOUR and h < CLOSE_HOUR

static func get_time_formatted(node: Node) -> String:
	var h := get_current_hour(node)
	var hour_int := int(h) % 24
	var minute_int := int(fmod(h * 60.0, 60.0))
	return "%02d:%02d" % [hour_int, minute_int]

static func get_closed_notice(node: Node, facility: String = "ESTAÇÃO") -> String:
	var time_str := get_time_formatted(node)
	return "%s FECHADA · FUNCIONAMENTO: 08:00 ÀS 18:00 (%s)" % [facility.to_upper(), time_str]
