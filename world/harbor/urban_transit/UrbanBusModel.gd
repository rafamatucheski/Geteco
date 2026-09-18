extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"
## One independently rendered body of the articulated express bus.
var door_leaves: Array[Node3D] = []
var destination_sign: Label3D
func is_front() -> bool: return true
func build() -> void:
	paint = mat("paint","c82d32",0.15,0.5)
	var roof := mat("bus_roof","deddd4",0.1,0.65)
	var black := mat("bus_black","17232c",0.0,0.8)
	var glass := mat("glass","294754",0.25,0.28)
	var trim := mat("trim","bac3c6",0.65,0.3)
	var length := 8.0 if is_front() else 6.5
	box(Vector3(0,0.72,0),Vector3(2.4,0.94,length),paint)
	box(Vector3(0,0.25,0),Vector3(2.34,0.15,length),black)
	box(Vector3(0,2.78,0),Vector3(2.44,0.18,length),roof)
	box(Vector3(0,2.94,0.7),Vector3(1.6,0.18,1.6),roof)
	for side in [-1.0,1.0]:
		for marker_z in [-length*0.44, 0.0, length*0.44]:
			box(Vector3(side*1.235,1.05,marker_z),Vector3(0.055,0.14,0.20),mat("running_amber","ffad35",0.1,0.3))
		for z in [-length*0.36,0.1,length*0.32]:
			box(Vector3(side*1.205,1.96,z),Vector3(0.025,1.38,1.62),glass)
		for z in [-length*0.49,-0.85,0.95,length*0.49]:
			box(Vector3(side*1.22,1.94,z),Vector3(0.04,1.42,0.07),black)
		box(Vector3(side*1.21,1.2,0),Vector3(0.03,0.07,length),trim)
		for z in ([-2.75,2.4] if is_front() else [1.6]):
			add_wheel(side*1.13,0.47,z,0.46,0.28,0.27,6,"a7afb4")
		# Sliding glass leaves on the raised-platform side.
		var door_z := -1.10 if is_front() else -1.45
		box(Vector3(side*1.225,1.42,door_z),Vector3(0.04,2.20,1.05),black)
		for leaf_side in [-1.0,1.0]:
			var leaf := Node3D.new()
			leaf.position = Vector3(side*1.25,1.42,door_z+leaf_side*0.255)
			leaf.set_meta("closed_z",leaf.position.z)
			leaf.set_meta("slide",leaf_side)
			add_child(leaf)
			var panel := box(Vector3.ZERO,Vector3(0.05,2.12,0.49),trim)
			panel.reparent(leaf,false)
			var window := box(Vector3(side*0.04,0.15,0),Vector3(0.025,1.62,0.39),glass)
			window.reparent(leaf,false)
			door_leaves.append(leaf)
		var brand := Label3D.new()
		brand.text = "EXPRESSO • URBANO"
		brand.font_size = 48
		brand.pixel_size = 0.0023
		brand.outline_size = 0
		brand.position = Vector3(side*1.225,0.80,0.5)
		brand.rotation.y = side*PI/2
		add_child(brand)
	if is_front():
		box(Vector3(0,1.90,-4.02),Vector3(2.24,1.35,0.04),glass)
		box(Vector3(0,2.53,-4.05),Vector3(2.25,0.35,0.04),black)
		destination_sign = Label3D.new()
		destination_sign.text = "510 CIRCULAR"
		destination_sign.font_size = 48
		destination_sign.pixel_size = 0.0033
		destination_sign.outline_size = 0
		destination_sign.modulate = Color("ffd97c")
		destination_sign.position = Vector3(0,2.53,-4.08)
		destination_sign.rotation.y = PI
		add_child(destination_sign)
		for side in [-1.0,1.0]:
			box(Vector3(side*0.91,0.74,-4.04),Vector3(0.35,0.20,0.05),mat("headlight","fff4ca",0.1,0.3,0.6))
		box(Vector3(0,1.94,4.02),Vector3(2.2,1.35,0.03),glass)
		for side in [-1.0,1.0]:
			box(Vector3(side*1.01,0.7,4.03),Vector3(0.12,0.36,0.03),mat("taillight","ea3930",0.1,0.3,0.4))
	else:
		box(Vector3(0,1.94,3.27),Vector3(2.2,1.35,0.03),glass)
		for side in [-1.0,1.0]:
			box(Vector3(side*1.01,0.7,3.28),Vector3(0.12,0.36,0.03),mat("taillight","ea3930",0.1,0.3,0.4))

func set_doors(amount: float) -> void:
	for leaf in door_leaves:
		leaf.position.z = float(leaf.get_meta("closed_z"))+float(leaf.get_meta("slide"))*amount*0.45

func set_running_lights(active: bool) -> void:
	for key in ["headlight", "taillight", "running_amber"]:
		var lamp := materials.get(key) as StandardMaterial3D
		if lamp:
			lamp.emission_enabled = active
			lamp.emission = lamp.albedo_color
			lamp.emission_energy_multiplier = 2.8 if active else 0.0
