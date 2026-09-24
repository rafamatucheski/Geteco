extends "res://world/mountain_pass/MountainCabinInline3D.gd"

func _ready() -> void:
	_box("Floor", Vector3(0, -.08, 0), Vector3(3.42, .16, 3.90), "705943")
	for x in 7:
		_box("FloorPlank", Vector3(-1.42 + x * .47, .01, 0), Vector3(.45, .02, 3.78), "876947" if x % 2 else "967757")
	_solid("RearLogs", Vector3(0, 1.35, -1.88), Vector3(3.4, 2.7, .16), "664632")
	for side in [-1.0, 1.0]:
		_solid("SideLogs%d" % int(side), Vector3(side * 1.67, 1.35, 0), Vector3(.16, 2.7, 3.76), "61412d")
		_solid("FrontLogs%d" % int(side), Vector3(side * 1.10, 1.35, 1.88), Vector3(1.22, 2.7, .16), "664632")
		_solid("WorkerBunk%d" % int(side), Vector3(side * 1.15, .84, -.72), Vector3(.82, 1.68, 1.52), "303638")
		for level in [.43, 1.23]:
			_box("Mattress", Vector3(side * 1.15, level, -.72), Vector3(.76, .14, 1.38), "c0b69f")
			_box("Blanket", Vector3(side * 1.15, level + .1, -.48), Vector3(.76, .07, .84), "60746b" if side < 0 else "795b5a")
	_solid("WorkBench", Vector3(0, .58, -1.48), Vector3(1.10, 1.16, .62), "967654")
	_box("Saw", Vector3(-.12, 1.18, -1.48), Vector3(.73, .035, .11), "9ca9a6")
	_solid("IronStove", Vector3(-1.14, .54, 1.08), Vector3(.63, 1.08, .58), "343738")
	_box("StoveFire", Vector3(-1.14, .55, 1.38), Vector3(.32, .28, .025), "ec9d5c", true)
	_solid("Woodpile", Vector3(1.19, .25, 1.25), Vector3(.60, .5, .51), "62452f")
	var light := OmniLight3D.new()
	light.position = Vector3(-.85, 2.1, .65)
	light.light_color = Color("ffd09a")
	light.light_energy = 1.1
	light.omni_range = 4.0
	add_child(light)
