extends RefCounted
## Só apresentação da suspensão: o corpo de colisão e o contato dos pneus não mudam.
static var enabled := OS.get_environment("GETECO_DRAG_BODY_BASELINE") != "1"
var car: Node3D
var rest := Transform3D.IDENTITY
var wheels: Array[Dictionary] = []
var riders: Array[Dictionary] = []
var elapsed := 0.0
var previous_speed := 0.0
var pitch := 0.0

func bind(vehicle: Node3D) -> void:
	car = vehicle
	rest = car.visual.transform
	for wheel in car.wheels:
		var unspin := Transform3D(Basis(Vector3.RIGHT,-car.wheel_spin),Vector3.ZERO)
		wheels.append({"node":wheel,"rest":wheel.transform*unspin})
	for child_name in ["DragRivalDriver","DragEntryNumber"]:
		var child := car.get_node_or_null(child_name)
		if child != null: riders.append({"node":child,"rest":child.transform})

func step(delta: float, drive) -> void:
	if not enabled: return
	var dt := clampf(delta,.001,.1)
	var acceleration := maxf(0.0,(float(drive.speed_mps)-previous_speed)/dt)
	previous_speed = float(drive.speed_mps)
	if drive.launched: elapsed += dt
	var weight := 1.0-smoothstep(1.1,2.8,elapsed)
	var target := deg_to_rad(2.4)*clampf(acceleration/8.0,0.0,1.0)*weight if drive.launched else 0.0
	pitch = lerpf(pitch,target,1.0-exp(-dt*(9.0 if target>pitch else 4.5)))
	var tilt := Transform3D(Basis(Vector3.RIGHT,pitch),Vector3.ZERO)
	# Gira o corpo suspenso perto do centro; a frente sobe e a traseira agacha.
	var pivot := Vector3(0,.6,0)
	tilt.origin = pivot-tilt.basis*pivot
	car.visual.transform = tilt*rest
	var counter: Transform3D = car.visual.transform.affine_inverse()*rest
	for item in wheels:
		var spin := Transform3D(Basis(Vector3.RIGHT,car.wheel_spin),Vector3.ZERO)
		item.node.transform = counter*item.rest*spin
	for item in riders:
		if is_instance_valid(item.node): item.node.transform = tilt*item.rest

func reset() -> void:
	if not is_instance_valid(car): return
	car.visual.transform = rest
	for item in wheels:
		if is_instance_valid(item.node):
			item.node.transform = item.rest*Transform3D(Basis(Vector3.RIGHT,car.wheel_spin),Vector3.ZERO)
	for item in riders:
		if is_instance_valid(item.node): item.node.transform = item.rest
