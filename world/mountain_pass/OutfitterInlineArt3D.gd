extends "res://world/harbor/interiors/ClothingInteriorArt3D.gd"

## Último Abrigo: the sales floor fits the existing six-metre cabin facade.
func _ready() -> void:
	_wood = "786047"
	_cloth = "73868c"
	counter = Vector2(0, -1.17)
	box("Foundation", Vector3(6.0, .18, 3.0), Vector3(0, -.11, -.35), "57534b")
	for i in 12:
		box("Floorboard", Vector3(.49, .04, 2.75), Vector3(-2.70 + i * .49, .01, -.35), "ae9374" if i % 3 else "947d65")
	_solid("BackWall", Vector3(5.9, 2.75, .19), Vector3(0, 1.38, -1.76), "554332")
	for side in [-1.0, 1.0]:
		_solid("SideWall%d" % int(side), Vector3(.19, 2.75, 2.66), Vector3(side * 2.91, 1.38, -.36), "554332")
		_solid("FrontWall%d" % int(side), Vector3(2.25, 2.65, .18), Vector3(side * 1.84, 1.33, .96), "554332")
		box("Window", Vector3(1.15, 1.12, .035), Vector3(side * 1.83, 1.48, .85), "77878a")
		box("WindowFrame", Vector3(1.30, .07, .05), Vector3(side * 1.83, 2.10, .88), "352f2b")
	_solid("Checkout", Vector3(2.05, 1.0, .70), Vector3(0, .5, counter.y), _wood)
	box("Register", Vector3(.35, .25, .3), Vector3(.53, 1.12, counter.y), "343a37")
	_shelves("WestCoats", Vector2(-2.23, -.35))
	_shelves("EastCoats", Vector2(2.23, -.35))
	_mannequin("StormCoat", Vector2(-2.24, .44), "a35d42")
	_mannequin("TrailCoat", Vector2(2.24, .44), "7e9892")
	box("AisleRunner", Vector3(1.45, .012, 1.30), Vector3(0, .035, .08), "7b6850")
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.45, -.45)
	lamp.light_color = Color("ffd6a1")
	lamp.light_energy = .85
	lamp.omni_range = 4.0
	lamp.shadow_enabled = false
	add_child(lamp)
