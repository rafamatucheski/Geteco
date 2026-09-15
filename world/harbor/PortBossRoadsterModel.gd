extends "res://prototypes/living_cast/SculptedFleetVehicleModel.gd"
## Exclusive open cockpit. No deck spans the seat/footwell volume.
func is_open_top() -> bool:
	return true

func _wheel_style() -> String:
	return "multi" # Ten gold spokes; all other dimensions are authored below.

func build() -> void:
	vehicle_id = "porto_rosso"
	paint = mat("paint", "e01824", .65, .19)
	var carbon := mat("carbon", "15191e", .25, .42)
	var leather := mat("leather", "bd8655", 0, .8)
	var trim := mat("trim", "363c44", .8, .25)
	var glass := mat("glass", "6b9aab", .3, .16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = .4
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight", "e1f7ff", .1, .15, .85)
	var tail := mat("taillight", "ff273b", .1, .2, .8)
	# Separate sculpted bonnet and engine deck leave a true open cabin.
	sculpted_shell([Vector3(-2.32,.63,.38),Vector3(-1.85,.96,.73),Vector3(-1.40,1.02,.84),Vector3(-.72,.94,.69)], [-1.40], .34, .36)
	sculpted_shell([Vector3(.75,.98,.70),Vector3(1.35,1.04,.83),Vector3(2.22,.85,.57)], [1.35], .35, .39)
	box(Vector3(0,.25,.03),Vector3(1.78,.12,1.6),carbon)
	for side in [-1.0,1.0]:
		box(Vector3(side*.90,.48,0),Vector3(.16,.39,1.55),paint)
		box(Vector3(side*.91,.29,0),Vector3(.2,.07,1.75),carbon)
		box(Vector3(side*.34,.48,.12),Vector3(.51,.12,.58),leather)
		var back := box(Vector3(side*.34,.76,.43),Vector3(.43,.54,.13),leather)
		back.rotation.x = -.14
		ell(Vector3(side*.34,1.08,.47),Vector3(.29,.20,.14),leather)
		for bolster in [-1.0,1.0]:
			ell(Vector3(side*.34+bolster*.22,.75,.38),Vector3(.095,.54,.22),leather)
		tube([Vector3(side*.57,.78,.70),Vector3(side*.57,1.13,.73),Vector3(side*.15,1.13,.73),Vector3(side*.15,.78,.70)],.035,trim)
		box(Vector3(side*.91,.64,.97),Vector3(.04,.2,.40),carbon)
		box(Vector3(side*.64,.50,-2.14),Vector3(.42,.045,.075),head)
		box(Vector3(side*.59,.61,2.18),Vector3(.48,.05,.06),tail)
		add_wheel(side*1.00,.34,-1.40,.36,.255,.27,10,"c7a36a")
		add_wheel(side*1.03,.35,1.35,.39,.28,.295,10,"c7a36a")
		box(Vector3(side*.97,.92,-.67),Vector3(.23,.10,.18),paint)
		box(Vector3(side*.91,.67,.22),Vector3(.035,.035,.18),trim)
	box(Vector3(0,.70,-.56),Vector3(1.64,.15,.24),carbon)
	box(Vector3(0,.42,.06),Vector3(.14,.23,.75),carbon)
	surface([Vector3(-.83,.73,-.82),Vector3(.83,.73,-.82),Vector3(.72,1.22,-.55),Vector3(-.72,1.22,-.55)],glass)
	tube([Vector3(-.83,.73,-.82),Vector3(-.72,1.22,-.55),Vector3(.72,1.22,-.55),Vector3(.83,.73,-.82)],.028,trim)
	var wheel := TorusMesh.new()
	wheel.inner_radius = .125
	wheel.outer_radius = .16
	var steering := mesh_node(wheel,Vector3(-.34,.83,-.34),carbon)
	steering.rotation.x = PI*.36
	box(Vector3(0,.28,-2.26),Vector3(1.73,.06,.22),carbon)
	box(Vector3(0,.27,2.18),Vector3(1.83,.08,.18),carbon)
	for i in 7:
		box(Vector3(0,.85,1.00+i*.12),Vector3(1.18,.022,.05),carbon)
	for x in [-.30,-.10,.10,.30]:
		var exhaust := cylinder(Vector3(x,.34,2.27),.065,.15,trim)
		exhaust.rotation.x = PI/2
