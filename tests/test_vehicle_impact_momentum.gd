extends SceneTree

class Street extends "res://gameplay/street_physics/StreetPhysics.gd":
	func _ready() -> void:
		set_physics_process(false)
class Car extends "res://scripts/Vehicle.gd":
	func _ready() -> void:
		set_physics_process(false)

var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var street = Street.new()
	root.add_child(street)
	var a = Car.new()
	var b = Car.new()
	root.add_child(a)
	root.add_child(b)
	for scenario in ["rear", "head_on", "heavy", "glancing"]:
		a.handling.mass = 1.0
		b.handling.mass = 4.0 if scenario == "heavy" else 1.0
		for car in [a,b]:
			car.stop_boarding_motion()
		a.horizontal_velocity = Vector3(3 if scenario == "glancing" else 0, 0, -12)
		b.horizontal_velocity = Vector3(0, 0, 12 if scenario == "head_on" else 0)
		var before: Vector3 = a.horizontal_velocity * a.handling.mass + b.horizontal_velocity * b.handling.mass
		var energy: float = a.horizontal_velocity.length_squared() * a.handling.mass + b.horizontal_velocity.length_squared() * b.handling.mass
		street._crash(a,b,Vector3.BACK,24.0 if scenario == "head_on" else 12.0,Vector3.ZERO,a.horizontal_velocity)
		var after: Vector3 = a.horizontal_velocity * a.handling.mass + b.horizontal_velocity * b.handling.mass
		check(after.distance_to(before) < 0.001, scenario + ": momentum conserved in driving velocity")
		check(a.horizontal_velocity.length_squared()*a.handling.mass+b.horizontal_velocity.length_squared()*b.handling.mass <= energy+0.001, scenario+": no energy gain")
		check(Vector3(b.get_meta("crash_slide",Vector3.ZERO)).length() < 0.001, scenario+": no second translation impulse")
		check(b.velocity.z == b.horizontal_velocity.z, scenario+": physics velocity synchronized")
		if scenario == "head_on":
			check(a.horizontal_velocity.length() < 0.5 and b.horizontal_velocity.length() < 0.5,"head-on absorbs impact without strong rebound")
		else:
			check(a.horizontal_velocity.z < 0 and b.horizontal_velocity.z < 0,scenario+": both continue in impact direction")
		if scenario == "glancing": check(absf(a.horizontal_velocity.x-3.0)<0.001,"tangential motion preserved")
	a.free()
	b.free()
	street.free()
	print("IMPACT_MOMENTUM failures=", failures)
	quit(0 if failures == 0 else 1)
