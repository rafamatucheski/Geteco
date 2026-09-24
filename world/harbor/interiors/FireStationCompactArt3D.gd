extends "res://world/harbor/cemetery/CemeteryPropBuilder.gd"

## Three real 3.6 m bay openings in the 310 x 220 px Northgate facade.
var shutters: Array[MeshInstance3D] = []
var lintels: Array[MeshInstance3D] = []

func _ready() -> void:
	box("ConcreteFloor",Vector3(15,.12,13.2),Vector3(0,-.08,0),"777d78")
	for x in range(-7,8,2): box("FloorJoint",Vector3(.018,.008,13),Vector3(x,.008,0),"636b66")
	for z in range(-6,7,2): box("FloorJoint",Vector3(14.8,.008,.018),Vector3(0,.008,z),"636b66")
	_solid("RearWall",Vector3(15,3.5,.22),Vector3(0,1.75,-6.6),"aeb4a8")
	for side in [-1.0,1.0]:
		_solid("SideWall%d" % int(side),Vector3(.22,3.5,13.2),Vector3(side*7.5,1.75,0),"7e8982")
		box("WallStripe",Vector3(.03,.22,12.8),Vector3(side*7.36,1.2,0),"c4543d")
	var piers := [[-6.9,1.2],[-2.25,.9],[2.25,.9],[6.9,1.2]]
	for index in piers.size():
		var pier: Array = piers[index]
		_solid("FrontPier%d" % index,Vector3(pier[1],3.45,.24),Vector3(pier[0],1.725,6.6),"8b958a")
	for index in 3:
		var lane := float(index-1)*4.5
		for side in [-1.0,1.0]:
			box("BayLine",Vector3(.07,.016,10.9),Vector3(lane+side*1.9,.012,.15),"d6bf74")
			box("DoorJamb",Vector3(.08,2.95,.25),Vector3(lane+side*1.83,1.48,6.55),"d0d4c7")
		lintels.append(box("DoorLintel",Vector3(3.75,.47,.28),Vector3(lane,3.24,6.55),"687b79"))
		var shutter := box("Shutter",Vector3(3.58,2.88,.075),Vector3(lane,1.44,6.62),"79908e")
		shutters.append(shutter)
		for rib in 11:
			box("ShutterRib",Vector3(3.54,.018,.018),Vector3(0,-1.18+rib*.235,.06),"c0cfca",shutter)
		box("Drain",Vector3(3.5,.016,.24),Vector3(lane,.018,5.0),"313e40")
		box("RearWindow",Vector3(2.5,.9,.035),Vector3(lane,2.32,-6.43),"63898c")
	_solid("AlarmLocker",Vector3(.9,2.25,1.5),Vector3(-6.85,1.12,-4.5),"ad4939")
	for i in 3:
		box("LockerDoor",Vector3(.05,1.88,.4),Vector3(-6.36,1.08,-5.05+i*.49),"c6634d")
	_solid("MedicalCabinet",Vector3(.95,1.95,1.5),Vector3(6.8,.97,-4.5),"d7d9ca")
	box("MedicalCross",Vector3(.04,.58,.15),Vector3(6.30,1.15,-4.5),"bb4c3f")
	box("MedicalCross",Vector3(.04,.15,.58),Vector3(6.29,1.15,-4.5),"bb4c3f")
	_solid("RearWorkBench",Vector3(2.3,.93,.75),Vector3(0,.465,-5.82),"775d43")
	box("BenchTop",Vector3(2.38,.06,.83),Vector3(0,.96,-5.82),"b8a77e")
	for x in [-4.5,0.0,4.5]:
		var light := OmniLight3D.new()
		light.position=Vector3(x,3.2,-1.2)
		light.light_color=Color("ffe8bd")
		light.light_energy=.5
		light.omni_range=6.5
		add_child(light)
		box("CeilingLight",Vector3(1.5,.07,.34),Vector3(x,3.43,-1.2),"e8e6d4")

func _solid(id: String,size: Vector3,point: Vector3,color: String) -> MeshInstance3D:
	var part := box(id,size,point,color)
	part.set_meta("interior_solid_id",StringName(id))
	return part

func set_gate_amount(index: int,amount: float) -> void:
	if index<0 or index>=shutters.size(): return
	# Coil the shutter into its housing so the raised panel does not hide the bay.
	shutters[index].position.y=1.44+amount*1.32
	shutters[index].scale.y=1.0-amount*.92

func set_cutaway_occupied(occupied: bool) -> void:
	for lintel in lintels: lintel.visible = not occupied
