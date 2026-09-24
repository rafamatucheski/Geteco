extends "res://world/harbor/cemetery/CemeteryPropBuilder.gd"

var door: Node3D
var window_light: MeshInstance3D

func _ready() -> void:
	box("StoneFoundation", Vector3(7.6, .3, 5.9), Vector3(0, .05, 0), "666657")
	box("BackPlaster", Vector3(7.1, 2.7, .18), Vector3(0, 1.5, -2.7), "99947a")
	for side in [-1.0, 1.0]:
		box("SidePlaster", Vector3(.18, 2.7, 5.4), Vector3(side * 3.55, 1.5, 0), "99947a")
		box("FrontPlaster", Vector3(2.8, 2.7, .18), Vector3(side * 2.15, 1.5, 2.7), "99947a")
	box("DoorHeadPlaster", Vector3(1.5, .6, .18), Vector3(0, 2.55, 2.7), "99947a")
	for z in [-2.65, 2.65]:
		box("DarkWoodLintel", Vector3(7.3, .16, .18), Vector3(0, 2.73, z), "494639")
	for x in [-3.45, 3.45]:
		box("CornerStone", Vector3(.23, 2.6, .25), Vector3(x, 1.4, 2.7), "747463")
	# Two sloped roof planes, narrow tile courses, a capped chimney.
	for side in [-1.0, 1.0]:
		var roof := box("TerracottaRoof", Vector3(4.0, .16, 6.1), Vector3(side * 1.78, 3.28, 0), "714c3c")
		roof.rotation.z = -side * .25
		for row in 9:
			var strip := box("TileCourse", Vector3(.075, .05, 6.12), Vector3(side * (.1 + row * .43), 3.75 - row * .11, 0), "925f46")
			strip.rotation.z = -side * .25
	box("RidgeCap", Vector3(.22, .17, 6.25), Vector3(0, 3.83, 0), "b07b56")
	box("Chimney", Vector3(.62, 1.2, .67), Vector3(2.3, 3.65, -1.5), "77766a")
	box("ChimneyCap", Vector3(.78, .16, .83), Vector3(2.3, 4.3, -1.5), "414a40")
	door = Node3D.new()
	door.name = "HingedDoor"
	door.position = Vector3(-.55, .18, 2.8)
	add_child(door)
	for i in 6: box("DoorPlank", Vector3(.18, 2.06, .10), Vector3(.09 + i * .18, 1.03, 0), "53614b", door)
	box("DoorHandle", Vector3(.035, .16, .045), Vector3(.93, 1.05, .075), "b69a62", door)
	box("StoneStep", Vector3(1.6, .15, .65), Vector3(0, .03, 3.07), "a4a18a")
	box("SignBoard", Vector3(3.4, .42, .09), Vector3(0, 2.55, 2.86), "3d4b3f")
	for x in [-2.2, 2.2]:
		box("WindowFrame", Vector3(1.42, 1.23, .14), Vector3(x, 1.62, 2.79), "414d3d")
		window_light = box("WindowGlass", Vector3(1.13, .93, .05), Vector3(x, 1.62, 2.88), "c8a56a")
		box("WindowMullion", Vector3(.065, 1.02, .08), Vector3(x, 1.62, 2.94), "656a51")
		box("WindowSill", Vector3(1.55, .10, .26), Vector3(x, 1.0, 2.89), "696b54")
		for side in [-1, 1]: box("GreenShutter", Vector3(.45, 1.2, .10), Vector3(x + side * .91, 1.62, 2.79), "4d5d46")
	lantern(Vector3(.88, 1.5, 2.88))
	for i in 3:
		box("Firewood", Vector3(.8, .17, .22), Vector3(2.75, .22 + i * .16, 3.0), "5e4a34")
	var sign := lettering("ANSELMO", Vector3(0, .70, 2.96), 14)
	sign.modulate = Color("dfc894")

func set_door_open(open: bool) -> void:
	if door:
		var tween := create_tween()
		tween.tween_property(door, "rotation:y", -1.3 if open else 0.0, .35)
