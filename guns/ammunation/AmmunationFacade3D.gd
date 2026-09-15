extends Node3D
const ART = preload("res://guns/ammunation/AmmunationArt.gd")
var panels: Array[Node3D] = []
var open_amount := 0.0

func set_open_amount(value: float) -> void:
	open_amount = clampf(value,0.0,1.0)
	for i in panels.size():
		panels[i].position.x = (-1.0 if i == 0 else 1.0) * (.45 + .88 * open_amount)

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	ART.box(self,Vector3(8.4,2.8,4.4),Vector3(0,1.4,0),ART.INK)
	ART.box(self,Vector3(8.65,.22,4.65),Vector3(0,2.9,0),Color("515957"))
	for side in [-1,1]: ART.box(self,Vector3(.14,.25,4.7),Vector3(side*4.3,3.06,0),ART.INK)
	ART.box(self,Vector3(8.6,.25,.14),Vector3(0,3.06,-2.28),ART.INK)
	var rooftop := Node3D.new()
	add_child(rooftop)
	rooftop.position = Vector3(0,3.025,0)
	rooftop.rotation.x = -PI*.5
	ART.target(rooftop,Vector3(-2.25,0,0),.70)
	ART.text(rooftop,"AMMU\nNATION",Vector3(.55,0,0),.014)
	ART.box(self,Vector3(1.0,.45,.8),Vector3(3,3.18,-1.25),Color("77827b"))
	for i in 6: ART.box(self,Vector3(.8,.015,.03),Vector3(3,3.415,-1.53+i*.10),ART.INK)
	ART.box(self,Vector3(8.5,.87,.16),Vector3(0,2.30,2.24),ART.RED)
	ART.text(self,"AMMU-NATION",Vector3(0,2.40,2.34),.012)
	for side in [-1,1]:
		ART.target(self,Vector3(side*3.7,2.38,2.35),.24)
		ART.box(self,Vector3(2.35,1.35,.09),Vector3(side*2.5,1.04,2.24),Color("56675d"))
		for i in 8: ART.box(self,Vector3(.032,1.39,.10),Vector3(side*2.5-.97+i*.28,1.04,2.31),ART.INK)
		ART.box(self,Vector3(.22,1.9,.24),Vector3(side*1.0,.95,2.3),ART.RED)
	ART.box(self,Vector3(1.8,1.85,.04),Vector3(0,.94,2.23),Color("080d0d"))
	for side in [-1,1]:
		var panel := Node3D.new()
		add_child(panel)
		panel.position = Vector3(side*.45,0,2.32)
		ART.box(panel,Vector3(.88,1.85,.08),Vector3(0,.94,0),Color("344741"))
		ART.box(panel,Vector3(.035,1.85,.10),Vector3(-side*.43,.94,0),Color("949c8c"))
		ART.box(panel,Vector3(.035,.4,.1),Vector3(-side*.33,.94,.08),ART.CREAM)
		panels.append(panel)
	ART.box(self,Vector3(8.7,.10,1.05),Vector3(0,1.9,2.62),ART.RED)
	ART.box(self,Vector3(8.7,.15,1.35),Vector3(0,-.01,2.65),Color("818778"))
	ART.box(self,Vector3(1.8,.025,.7),Vector3(0,.08,2.75),ART.INK)
	for side in [-1,1]:
		ART.box(self,Vector3(.15,.68,.15),Vector3(side*3.8,.34,2.9),Color("c8aa54"))
		ART.box(self,Vector3(.17,.16,.17),Vector3(side*3.8,.4,2.9),ART.INK)
