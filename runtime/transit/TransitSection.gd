extends CharacterBody3D
var bus: CharacterBody3D
var traffic: bool:
	get: return is_instance_valid(bus) and bus.traffic
var speed: float:
	get: return bus.speed if is_instance_valid(bus) else 0.0
var blocked: bool:
	get: return is_instance_valid(bus) and bus.blocked
var stall_time: float:
	get: return bus.stall_time if is_instance_valid(bus) else 0.0
var junction_wait: bool:
	get: return is_instance_valid(bus) and bus.junction_wait
var bypass_side := 0.0
func is_servicing_stop() -> bool: return is_instance_valid(bus) and bus.is_servicing_stop()
func driver_seat_anchor() -> Vector3: return global_position
func receive_damage(amount: float, source: Node = null) -> void:
	if is_instance_valid(bus): bus.receive_damage(amount,source)
