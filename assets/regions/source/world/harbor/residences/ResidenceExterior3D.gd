extends "res://assets/regions/source/world/harbor/cemetery/CemeteryPropBuilder.gd"

var variant_index := 0
func _ready() -> void:
	var parking := preload("res://world/places/ResidenceParking.gd").new()
	parking.name = "ResidentialGarage"
	parking.position = preload("res://world/places/ResidenceParking.gd").placement(variant_index)
	add_child(parking)
	var variant: int = variant_index
	var plaster: String = ["d3c4a5","b6c8c6","d8d9cd"][variant]
	var timber: String = ["684a36","455d68","423d36"][variant]
	var height := 2.9 if variant != 2 else 4.8
	box("Foundation",Vector3(9.4,.28,6.6),Vector3(0,.08,0),"807e73")
	box("Walls",Vector3(9,height,6.2),Vector3(0,height*.5+.18,0),plaster)
	box("StonePlinth",Vector3(9.12,.42,6.3),Vector3(0,.35,0),"8b8c7d")
	for x in [-4.4,4.4]:
		box("CornerPillar",Vector3(.22,height,.25),Vector3(x,height*.5+.18,3.15),"e4dfd0")
	if variant == 0:
		for side in [-1.0,1.0]:
			var roof := box("PitchedRoof",Vector3(4.95,.18,7.05),Vector3(side*2.22,3.67,0),"805748")
			roof.rotation.z = -side*.25
			for row in 10:
				var tile := box("TileCourse",Vector3(.045,.045,7.07),Vector3(side*(.16+row*.49),4.25-row*.126,0),"9a6a51")
				tile.rotation.z = -side*.25
		box("Ridge",Vector3(.2,.15,7.15),Vector3(0,4.3,0),"bd8a68")
	else:
		box("RoofSlab",Vector3(9.65,.25,6.9),Vector3(0,height+.3,0),"555e60")
		for x in [-4.65,4.65]: box("RoofParapet",Vector3(.18,.4,6.75),Vector3(x,height+.6,0),plaster)
		box("RearParapet",Vector3(9.5,.4,.18),Vector3(0,height+.6,-3.3),plaster)
		if variant == 2:
			box("Balcony",Vector3(6.9,.15,1.0),Vector3(.45,3.15,3.45),"d4d1c1")
			for x in range(-29,39,5): box("Balustrade",Vector3(.035,.75,.045),Vector3(x*.1,3.59,3.94),"4d5856")
			box("Handrail",Vector3(6.9,.05,.07),Vector3(.45,4.0,3.94),"596563")
	box("Chimney",Vector3(.6,1.1,.65),Vector3(3.1,height+.55,-1.7),"797d76")
	box("ChimneyCap",Vector3(.85,.15,.85),Vector3(3.1,height+1.14,-1.7),"414947")
	box("DoorFrame",Vector3(1.38,2.37,.16),Vector3(0,1.3,3.15),"e2d9c3")
	box("FrontDoor",Vector3(1.12,2.16,.12),Vector3(0,1.22,3.26),timber)
	for y in [.65,1.5]: box("DoorPanel",Vector3(.84,.64,.04),Vector3(0,y,3.34),timber)
	box("DoorHandle",Vector3(.045,.19,.09),Vector3(.4,1.1,3.4),"c5ac79")
	box("PorchStep",Vector3(2.2,.14,.9),Vector3(0,.04,3.57),"c9c4b4")
	box("PorchCanopy",Vector3(2.8,.13,1.35),Vector3(0,2.73,3.56),timber)
	for x in [-2.9,2.9]:
		_window(x,1.65,3.19,timber)
		if variant == 2: _window(x,3.9,3.19,timber)
		box("Planter",Vector3(1.65,.32,.52),Vector3(x,.34,3.51),"7c7060")
		for leaf in 5:
			var shrub := cylinder("Shrub",.21,.45,Vector3(x-.6+leaf*.3,.66,3.52),"537258")
			shrub.scale.z = .75
	for x in [-.95,.95]:
		box("PorchLampBack",Vector3(.19,.3,.13),Vector3(x,1.95,3.29),"39443e")
		box("PorchLampGlass",Vector3(.14,.21,.14),Vector3(x,1.95,3.4),"ecd7a2")

func _window(x: float,y: float,z: float,timber: String) -> void:
	box("WindowFrame",Vector3(1.55,1.35,.16),Vector3(x,y,z),"e0dbcb")
	box("WindowGlass",Vector3(1.3,1.1,.06),Vector3(x,y,z+.12),"7299a5")
	box("Mullion",Vector3(.07,1.15,.07),Vector3(x,y,z+.18),timber)
	box("Transom",Vector3(1.38,.07,.07),Vector3(x,y,z+.18),timber)
	box("Sill",Vector3(1.8,.12,.35),Vector3(x,y-.71,z+.08),"d5d0bd")
