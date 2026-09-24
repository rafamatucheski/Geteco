extends "res://world/harbor/cemetery/CemeteryPropBuilder.gd"

func _ready() -> void:
	box("Foundation",Vector3(28,.22,20.8),Vector3(0,-.15,.4),"373e3e")
	box("ConcreteFloor",Vector3(27.8,.05,20.6),Vector3(0,0,.4),"777a70")
	for x in range(-12,14,2):
		box("ConcreteJoint",Vector3(.025,.012,20),Vector3(x,.04,0),"59615b")
	for z in range(-10,11,2):
		box("ConcreteJoint",Vector3(28,.012,.025),Vector3(0,.04,z),"59615b")
	_solid("BackWall",Vector3(28,4,.25),Vector3(0,2,-10),"b6b4a0")
	for side in [-1.0,1.0]:
		_solid("SideWall%d"%int(side),Vector3(.25,4,20),Vector3(side*14,2,0),"898e81")
		box("WallStripe",Vector3(.05,.28,19.8),Vector3(side*13.85,1.5,0),"a94835")
	for spec in [[-11.6,4.75],[-3.44,2.25],[3.44,2.25],[11.6,4.75]]:
		_solid("FrontPier%.2f"%spec[0],Vector3(spec[1],.6,.3),Vector3(spec[0],.3,10),"6d756c")
	for lane in [-6.875,0.0,6.875]:
		for side in [-1.0,1.0]:
			box("BayLine",Vector3(.09,.014,16.6),Vector3(lane+side*2.25,.045,1.2),"d9ba62")
			box("DoorJamb",Vector3(.18,3.6,.35),Vector3(lane+side*2.3,1.8,10),"b1b1a2")
		box("Drain",Vector3(3.9,.02,.3),Vector3(lane,.055,6.5),"343e3a")
		for i in 18:
			box("DrainGrate",Vector3(.06,.015,.32),Vector3(lane-1.8+i*.21,.073,6.5),"8b9489")
		box("ShutterHousing",Vector3(4.8,.35,.42),Vector3(lane,3.8,10),"8f9890")
		box("RearWindow",Vector3(3.8,1.05,.06),Vector3(lane,2.6,-9.84),"7f9c9b")
		for x in [-1.9,0,1.9]:
			box("WindowMullion",Vector3(.08,1.15,.09),Vector3(lane+x,2.6,-9.77),"404f49")
	for index in 5:
		var z := -7.5+index*1.25
		_solid("GearLocker%d"%index,Vector3(1.1,2.35,1.1),Vector3(-12.5,1.175,z),"a54735")
		box("LockerDoor",Vector3(.04,2.14,.96),Vector3(-11.93,1.18,z),"b85943")
		box("LockerHandle",Vector3(.07,.22,.045),Vector3(-11.89,1.08,z+.3),"d1c2a0")
		for vent in 4:
			box("Vent",Vector3(.03,.03,.55),Vector3(-11.88,1.8+vent*.08,z),"553f33")
	_solid("MedicalCabinet",Vector3(1.2,1.5,2.8),Vector3(12.4,.75,-5.3),"d2d0bb")
	box("MedicalCross",Vector3(.025,.65,.18),Vector3(11.78,1.0,-5.3),"b34638")
	box("MedicalCross",Vector3(.025,.18,.65),Vector3(11.77,1.0,-5.3),"b34638")
	_solid("OxygenRack",Vector3(1.25,.2,2.4),Vector3(12.4,.15,-1.5),"525d51")
	for i in 3:
		var tank := cylinder("OxygenTank",.26,1.3,Vector3(12.4,.9,-2.2+i*.7),"94a993")
		tank.set_meta("interior_solid_id",&"OxygenRack")
		box("TankValve",Vector3(.15,.12,.12),Vector3(12.4,1.62,-2.2+i*.7),"b49b66")
	_solid("WorkBench",Vector3(5.2,1.0,1.1),Vector3(0,.5,-8.4),"816545")
	_solid("WorkBench",Vector3(5.4,.09,1.2),Vector3(0,1.05,-8.4),"baa379")
	for i in 4:
		box("Helmet",Vector3(.35,.23,.38),Vector3(-1.8+i*1.2,1.22,-8.4),"c9b154")
	for x in [-7,0,7]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x,3.6,-2.0)
		lamp.light_color = Color("ffdfaa")
		lamp.light_energy = .8
		lamp.omni_range = 9
		add_child(lamp)
		box("CeilingLight",Vector3(2.8,.12,.45),Vector3(x,3.65,-2.0),"ddd8b9")

func _solid(id: String,size: Vector3,point: Vector3,color: String) -> MeshInstance3D:
	var mesh := box(id,size,point,color)
	mesh.set_meta("interior_solid_id",StringName(id))
	return mesh
