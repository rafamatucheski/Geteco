extends "res://prototypes/living_cast/models/UnionSedanModel.gd"
## Classic New York yellow cab, with readable roof and side identification.
func build() -> void:
	super.build()
	paint.albedo_color = Color("ffc526")
	var ink := mat("cab_ink", "14191e", 0.1, 0.65)
	var ivory := mat("cab_ivory", "fff0bb", 0.0, 0.6)
	var glow := mat("cab_sign", "fff0bb", 0.0, 0.4, 0.65)
	box(Vector3(0,1.40,0.10), Vector3(1.02,0.06,0.40), ink)
	box(Vector3(0,1.57,0.10), Vector3(0.95,0.28,0.34), glow)
	for side in [-1.0, 1.0]:
		_letter("TAXI", Vector3(0,1.57,0.10+side*0.176), 0 if side > 0 else PI, 0.0042)
		box(Vector3(side*0.898,0.56,0.10), Vector3(0.018,0.18,1.62), ivory).set_meta("door_trim",true)
		for row in 2:
			for col in 18:
				if (row+col)%2 == 0:
					box(Vector3(side*0.912,0.515+row*0.09,-0.665+col*0.09),Vector3(0.015,0.09,0.09),ink).set_meta("door_trim",true)
		_letter("NYC TAXI", Vector3(side*0.922,0.72,0.22),side*PI/2,0.0024).set_meta("door_trim",true)
		_letter("7K28", Vector3(side*0.882,0.66,1.55),side*PI/2,0.002)
	# Roof-facing letters remain legible from the gameplay camera.
	var top := _letter("TAXI", Vector3(0,1.716,0.10),0,0.0038)
	top.rotation.x = -PI/2
	var driver := Node3D.new()
	driver.name = "TaxiDriver"
	add_child(driver)
	var shirt := box(Vector3(-0.30,0.85,-0.10),Vector3(0.25,0.27,0.20),mat("cab_driver_shirt","43586b"))
	shirt.reparent(driver,false)
	var head := box(Vector3(-0.30,1.08,-0.13),Vector3(0.17,0.19,0.18),mat("cab_driver_skin","bc8b63"))
	head.reparent(driver,false)

func _letter(words: String, at: Vector3, yaw: float, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = 48
	label.pixel_size = pixel
	label.modulate = Color("14191e")
	label.outline_size = 0
	label.position = at
	label.rotation.y = yaw
	add_child(label)
	return label
