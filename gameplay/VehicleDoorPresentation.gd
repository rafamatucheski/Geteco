extends Node3D
## Lightweight driver-door leaves for baked fleet models that do not expose hinges.
## They are presentation only: Driving keeps physical admission and clearance authoritative.

var vehicle: CharacterBody3D
var hinges: Dictionary = {}
var motions: Dictionary = {}
var material: StandardMaterial3D
var coupe_ready := false

func configure(owner_vehicle: CharacterBody3D) -> void:
	vehicle = owner_vehicle
	name = "DriverDoorPresentation"
	if vehicle.archetype == "sport_coupe":
		var coupe_doors = preload("res://gameplay/VehicleCoupeDoors.gd").new()
		add_child(coupe_doors)
		if coupe_doors.configure(vehicle):
			hinges = coupe_doors.hinges
			coupe_ready = true
			return
		coupe_doors.queue_free()
	material = StandardMaterial3D.new()
	material.albedo_color = vehicle.paint_color
	material.metallic = .32
	material.roughness = .30
	for side in [-1, 1]:
		var hinge := Node3D.new()
		hinge.name = "DriverDoorL" if side < 0 else "DriverDoorR"
		var length := clampf(vehicle.half_length * .48, .72, 1.28)
		var front_z := -clampf(vehicle.half_length * .42, .62, 1.05)
		var hinge_y := .63
		var height := .76
		# Cabine alta: a folha da porta acompanha o piso elevado, na frente do chassi.
		var step: float = vehicle.boarding_step_height() if vehicle.has_method("boarding_step_height") else 0.0
		if step > 0.0:
			length = 1.0 if step > .5 else 1.1
			front_z = vehicle._cab_z() - length * .5
			hinge_y = .63 + step
			height = .9
		hinge.position = Vector3(float(side) * (vehicle.half_width + .055), hinge_y, front_z)
		var panel := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.035, height, length)
		panel.mesh = mesh
		panel.position = Vector3(float(side) * .02, 0.0, length * .5)
		panel.material_override = material
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		hinge.add_child(panel)
		add_child(hinge)
		hinges[side] = hinge

func apply_paint(color: Color) -> void:
	if is_instance_valid(material): material.albedo_color = color

func set_open(side: int, opened: bool, duration := .28) -> void:
	if not hinges.has(side): return
	var previous: Tween = motions.get(side)
	if is_instance_valid(previous): previous.kill()
	var hinge: Node3D = hinges[side]
	var target := float(side) * (1.05 if coupe_ready else .72) if opened else 0.0
	if duration <= 0.0:
		hinge.rotation.y = target
		return
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(hinge, "rotation:y", target, duration)
	motions[side] = tween

func close_all(duration := .18) -> void:
	for side in hinges: set_open(side, false, duration)
