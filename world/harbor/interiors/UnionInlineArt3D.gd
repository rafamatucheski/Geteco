extends "res://world/harbor/interiors/ClothingInteriorArt3D.gd"

## A Union sales floor contained by NorthFrontage3's existing 230 x 180 px lot.
## The wide center aisle connects the real street threshold to the checkout.
func _ready() -> void:
	_wood = "705342"
	_cloth = "6b4145"
	counter = Vector2(0, -1.28)
	box("Foundation", Vector3(8.4, .18, 4.4), Vector3(0, -.11, 0), "444b4a")
	for i in 16:
		box("Floorboard", Vector3(.52, .04, 4.2), Vector3(-3.9 + i * .52, 0, 0), "8c7560" if i % 4 else "6d594b")
	_solid("BackWall", Vector3(8.2, 3.1, .2), Vector3(0, 1.55, -2.1), "9d9785")
	for side in [-1.0, 1.0]:
		_solid("SideWall%d" % int(side), Vector3(.2, 3.1, 4.2), Vector3(side * 4.1, 1.55, 0), "625c53")
		_solid("FrontPlinth%d" % int(side), Vector3(2.7, .67, .18), Vector3(side * 2.65, .335, 2.12), "364e4d")
		box("WindowSill", Vector3(2.78, .09, .28), Vector3(side * 2.65, .72, 2.12), "c7aa77")
		box("WindowLintel", Vector3(2.7, .35, .18), Vector3(side * 2.65, 2.62, 2.12), "364e4d")
		box("WindowFrame", Vector3(.08, 1.9, .14), Vector3(side * 2.65, 1.72, 2.12), "c7aa77")
		_shelves("Collection%d" % int(side), Vector2(side * 3.45, -.30))
		_mannequin("WindowLook%d" % int(side), Vector2(side * 2.62, 1.42), "7a4844" if side < 0 else "475e71")
		_rack("WallRack%d" % int(side), Vector2(side * 2.5, -1.65), false)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(side * 2.75, 2.7, -.25)
		lamp.light_color = Color("ffe1ae")
		lamp.light_energy = .72
		lamp.omni_range = 4.6
		add_child(lamp)
	_solid("Checkout", Vector3(2.5, 1.03, .68), Vector3(0, .515, counter.y), _wood)
	box("CheckoutTop", Vector3(2.62, .09, .78), Vector3(0, 1.075, counter.y), "c3b496")
	box("Register", Vector3(.38, .24, .30), Vector3(.68, 1.24, counter.y), "293835")
	_bench("FittingBench", Vector2(-1.9, -.10))
	box("AisleRunner", Vector3(1.7, .012, 2.35), Vector3(0, .035, .66), "654b4b")
	box("EntryMat", Vector3(1.5, .014, .46), Vector3(0, .038, 1.86), "465c58")
