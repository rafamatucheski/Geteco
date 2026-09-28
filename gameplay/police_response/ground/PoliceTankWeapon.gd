extends RefCounted
## AI aims the same swept cannon used by a player who steals the tank.
var aim := 0.0

func tick(unit: RefCounted, delta: float, target: Node3D) -> void:
	var gameplay: Node3D = unit.controller.gameplay
	var car: CharacterBody3D = unit.vehicle
	if not is_instance_valid(car) or not is_instance_valid(target):
		aim = 0.0
		return
	var cannon: Node3D = car.get("tank_cannon")
	if not is_instance_valid(cannon) or not car.external_input or unit.crew_remaining <= 0 or not gameplay.state.weapons_allowed() or not gameplay.police_force_authorized() or gameplay.police_surrendering() or not unit._sees_target(target):
		aim = 0.0
		return
	var point := target.global_position+Vector3.UP*.9
	var distance := car.global_position.distance_to(point)
	if distance < 7.0 or distance > cannon.RANGE:
		aim = 0.0
		return
	cannon.aim_at(point,delta)
	if not cannon.is_aligned(point,.07):
		aim = 0.0
		return
	aim += delta
	if aim < 1.0: return
	if cannon.fire(gameplay,true):
		aim = 0.0
		unit.controller.emit_dispatch_event("tank_fired",{"unit":unit,"point":point})
