extends "res://cars/motorcycles/UrbanMotorcycle.gd"

func build() -> void:
	super.build()
	paint.albedo_color = Color("edf0f2")
	var navy := mat("police_navy", "19304b", 0.15, 0.65)
	for side in [-1.0, 1.0]:
		box(Vector3(side * .29, .65, .60), Vector3(.22, .29, .40), paint)
		box(Vector3(side * .405, .67, .60), Vector3(.012, .09, .30), navy)
		var beacon := mat("bar_left" if side < 0 else "bar_right", "ef283b" if side < 0 else "2879ed", .1, .25)
		box(Vector3(side * .27, 1.02, -.42), Vector3(.10, .08, .10), beacon)
	rider_jacket.albedo_color = navy.albedo_color
	rider_helmet.albedo_color = Color("edf0f2")
