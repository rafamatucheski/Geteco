extends "res://world/harbor/interiors/ClothingInteriorArt3D.gd"

## A compact sales floor matching the Boutique Alpina's 6.7 x 4.0 m facade.
## The facade owns the roof; this model only renders the open room and fixtures.
func _ready() -> void:
	_wood = "b5a081"
	_cloth = "66795e"
	counter = Vector2(0, -1.15)
	box("Foundation", Vector3(6.7, .18, 4.0), Vector3(0, -.11, 0), "535b60")
	for i in 13:
		box("Floorboard", Vector3(.5, .045, 3.8), Vector3(-3.0 + i * .5, 0, 0), "b5a081" if i % 3 else "9d8b73")
	_solid("BackWall", Vector3(6.5, 3.0, .22), Vector3(0, 1.5, -1.88), "493c32")
	for side in [-1.0, 1.0]:
		_solid("SideWall%d" % int(side), Vector3(.22, 3.0, 3.75), Vector3(side * 3.24, 1.5, 0), "493c32")
		_solid("FrontWall%d" % int(side), Vector3(2.56, 2.9, .17), Vector3(side * 2.02, 1.45, 1.88), "493c32")
		box("Window", Vector3(1.45, 1.3, .035), Vector3(side * 2.08, 1.55, 1.78), "657e83")
		box("WindowFrame", Vector3(1.58, .07, .05), Vector3(side * 2.08, 2.22, 1.82), "26333c")
		box("WallLamp", Vector3(.34, .14, .25), Vector3(side * 2.36, 2.72, -.45), "d2b384")
	_solid("Checkout", Vector3(2.7, 1.05, .78), Vector3(0, .525, counter.y), _wood)
	_solid("Checkout", Vector3(2.8, .08, .88), Vector3(0, 1.09, counter.y), "c3b496")
	box("Register", Vector3(.38, .25, .3), Vector3(.72, 1.24, counter.y), "293835")
	_shelves("WestCollection", Vector2(-2.48, -.2))
	_shelves("EastCollection", Vector2(2.48, -.2))
	_mannequin("TailoredCoat", Vector2(-2.3, -1.08), "889481")
	_mannequin("AlpineCoat", Vector2(2.3, -1.08), "c1aa88")
	_bench("VelvetSeat", Vector2(-2.28, 1.35))
	box("AisleRunner", Vector3(1.8, .012, 2.35), Vector3(0, .04, .38), "66795e")
	for x in [-2.2, 2.2]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x, 2.65, -.45)
		lamp.light_color = Color("ffd6a1")
		lamp.light_energy = .75
		lamp.omni_range = 4.0
		lamp.shadow_enabled = false
		add_child(lamp)
