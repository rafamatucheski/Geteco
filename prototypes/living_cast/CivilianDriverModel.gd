extends "res://world/mountain_pass/WinterResidentModel.gd"
## Casual civilian, same human scale as Dante: green overshirt, jeans,
## sneakers, hair, ears and facial features. No independent NPC physics.
func _ready() -> void:
	coat_color = [Color("39835a"),Color("7d6e53"),Color("485b70"),Color("77524d")].pick_random()
	scale = Vector3(randf_range(.90,1.12),randf_range(.93,1.09),1)
	var skin := Color("c89272")
	for side in [-1.0,1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side*0.12,0.82,0)
		add_child(leg)
		limbs.append(leg)
		part(leg,Vector3(0,-0.32,0),Vector3(0.18,0.64,0.20),Color("33465c"))
		part(leg,Vector3(0,-0.73,0.07),Vector3(0.20,0.18,0.32),Color("ece6d6"))
		var arm := Node3D.new()
		arm.position = Vector3(side*0.26,1.35,0)
		add_child(arm)
		limbs.append(arm)
		part(arm,Vector3(0,-0.18,0),Vector3(0.18,0.38,0.20),coat_color)
		part(arm,Vector3(0,-0.42,0.015),Vector3(0.14,0.20,0.15),skin)
	part(self,Vector3(0,1.13,0),Vector3(0.48,0.63,0.31),coat_color)
	part(self,Vector3(0,1.15,0.17),Vector3(0.02,0.54,0.025),Color("ece6d6"))
	part(self,Vector3(-0.13,1.25,0.16),Vector3(0.13,0.13,0.04),coat_color.darkened(0.18))
	part(self,Vector3(0,0.82,0),Vector3(0.43,0.07,0.30),Color("322b28"))
	part(self,Vector3(0,1.48,0),Vector3(0.16,0.18,0.18),skin)
	part(self,Vector3(0,1.63,0),Vector3(0.32,0.32,0.28),skin)
	part(self,Vector3(0,1.75,-0.025),Vector3(0.34,0.11,0.29),Color("302723"))
	for side in [-1.0,1.0]:
		part(self,Vector3(side*0.17,1.62,0),Vector3(0.07,0.11,0.08),skin)
		part(self,Vector3(side*0.065,1.65,0.139),Vector3(0.035,0.026,0.02),Color("25272a"))
	part(self,Vector3(0,1.59,0.16),Vector3(0.06,0.07,0.07),skin.lightened(0.1))
	for side in [-1,1]:
		part(self,Vector3(side*.07,1.685,.137),Vector3(.065,.017,.025),Color("48352b"))
		part(self,Vector3(side*.065,1.41,.145),Vector3(.10,.12,.05),coat_color.lightened(.2))
		part(limbs[1 if side<0 else 3],Vector3(0,-.30,0),Vector3(.19,.045,.205),coat_color.darkened(.20))
	part(self,Vector3(0,1.55,.143),Vector3(.065,.017,.02),skin.darkened(.35))
	part(self,Vector3(0,.84,.165),Vector3(.075,.045,.035),Color("bab39f"))
	for y in [1.05,1.17,1.29]: part(self,Vector3(0,y,.186),Vector3(.025,.025,.012),Color("bdbdaf"))

func _process(delta: float) -> void:
	clock += delta
	for i in limbs.size():
		limbs[i].rotation.x = sin(clock*7.0+(PI if i in [0,3] else 0.0))*(0.35 if walking else 0.012)
