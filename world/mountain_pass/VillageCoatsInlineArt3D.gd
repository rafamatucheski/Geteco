extends "res://world/harbor/interiors/ClothingInteriorArt3D.gd"

## Casacos da Vila occupies the full nine-metre shop shell in the transit village.
func _ready() -> void:
	_wood = "75604c"
	_cloth = "587675"
	counter = Vector2(0, -1.75)
	box("Foundation", Vector3(8.6, .18, 4.55), Vector3(0, -.11, 0), "65747a")
	for i in 18:
		box("Floorboard", Vector3(.47, .045, 4.35), Vector3(-4.0 + i * .47, 0, 0), "a48d72" if i % 3 else "8b7863")
	_solid("BackWall", Vector3(8.45, 3.0, .20), Vector3(0, 1.5, -2.18), "5d4a3e")
	for side in [-1.0, 1.0]:
		_solid("SideWall%d" % int(side), Vector3(.20, 3.0, 4.33), Vector3(side * 4.19, 1.5, 0), "5d4a3e")
		_solid("FrontWall%d" % int(side), Vector3(3.46, 2.92, .18), Vector3(side * 2.49, 1.46, 2.17), "5d4a3e")
		box("Window", Vector3(1.85, 1.48, .035), Vector3(side * 2.5, 1.55, 2.05), "6a8586")
		box("WindowFrame", Vector3(2.02, .07, .05), Vector3(side * 2.5, 2.34, 2.08), "34444b")
	_solid("Checkout", Vector3(2.75, 1.04, .78), Vector3(0, .52, counter.y), _wood)
	box("Register", Vector3(.37, .24, .31), Vector3(.77, 1.15, counter.y), "303d3a")
	_shelves("WestCollection", Vector2(-3.36, -.55))
	_shelves("EastCollection", Vector2(3.36, -.55))
	_mannequin("ScarletParka", Vector2(-3.38, 1.12), "a85045")
	_mannequin("BlueParka", Vector2(3.38, 1.12), "537b87")
	_bench("FittingBench", Vector2(-1.9, 1.25))
	box("AisleRunner", Vector3(2.05, .012, 2.7), Vector3(.25, .035, .35), "637677")
	for x in [-2.8, 2.8]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x, 2.67, -.5)
		lamp.light_color = Color("ffd8ae")
		lamp.light_energy = .72
		lamp.omni_range = 4.2
		lamp.shadow_enabled = false
		add_child(lamp)
