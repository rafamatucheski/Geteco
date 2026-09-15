extends Node3D
## Cached architectural model. Dimensions are metres; collision uses its floor projection.
const B = preload("res://world/shared/pedestrians/CitizenDetails.gd")
const WHITE = Color("e5ece8")
const TEAL = Color("438c91")
const STEEL = Color("a7b7bc")
var door_leaves: Array[MeshInstance3D] = []
var door_handles: Array[MeshInstance3D] = []
var solids: Array[Rect2] = []
func box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	return B.piece(self,size,at,color)
func solid(at: Vector2, size: Vector2) -> void: solids.append(Rect2(at-size*.5,size))
func _ready() -> void:
	box(Vector3(20,.18,14),Vector3(0,-.12,0),Color("c7d5d4"))
	for x in range(-10,11): box(Vector3(.016,.008,14),Vector3(x,0,0),Color("9aafaf"))
	for z in range(-7,8): box(Vector3(20,.008,.016),Vector3(0,0,z),Color("9aafaf"))
	# Cutaway walls keep all treatment and waiting areas legible.
	for x in [-10,10]:
		box(Vector3(.18,2.8,14),Vector3(x,1.4,0),WHITE)
		box(Vector3(.035,.65,14),Vector3(x-sign(x)*.11,.7,0),TEAL)
		solid(Vector2(x,0),Vector2(.3,14))
	for x in [-5.8,5.8]:
		box(Vector3(8.4,2.8,.18),Vector3(x,1.4,-7),WHITE)
		box(Vector3(8.4,.65,.06),Vector3(x,.7,-6.88),TEAL)
		solid(Vector2(x,-7),Vector2(8.4,.3))
	box(Vector3(20,.45,.18),Vector3(0,.225,7),WHITE)
	solid(Vector2(0,7),Vector2(20,.3))
	solid(Vector2(0,-7.2),Vector2(3.2,.2))
	# Double glass entrance, metal frame and entry mat.
	for x in [-1.55,1.55]: box(Vector3(.10,2.65,.18),Vector3(x,1.32,-6.95),STEEL)
	box(Vector3(3.2,.12,.18),Vector3(0,2.65,-6.95),STEEL)
	for x in [-.8,.8]:
		door_leaves.append(box(Vector3(1.45,2.35,.06),Vector3(x,1.2,-7.03),Color("73969e")))
		door_handles.append(box(Vector3(.06,.6,.08),Vector3(x*.2,1.1,-6.93),WHITE))
	box(Vector3(3.1,.015,1.8),Vector3(0,.015,-5.9),Color("4d666a"))
	# Reception desk, return, workstations and paper trays.
	box(Vector3(5.7,1.05,1.05),Vector3(-5.5,.525,-2.4),TEAL)
	box(Vector3(5.95,.12,1.3),Vector3(-5.5,1.1,-2.4),WHITE)
	box(Vector3(.9,1.05,2.4),Vector3(-8,.525,-3.05),TEAL)
	solid(Vector2(-5.5,-2.4),Vector2(6,1.3))
	solid(Vector2(-8,-3.05),Vector2(1,2.5))
	for x in [-6.6,-4.4]:
		box(Vector3(.5,.04,.32),Vector3(x,1.19,-2.5),Color("263d47"))
		box(Vector3(.08,.27,.08),Vector3(x,1.32,-2.7),STEEL)
		box(Vector3(.65,.43,.07),Vector3(x,1.58,-2.7),Color("263d47"))
		box(Vector3(.55,.32,.012),Vector3(x,1.58,-2.65),Color("78bbc2"))
		box(Vector3(.5,.035,.19),Vector3(x,1.19,-2.2),Color("526068"))
	box(Vector3(.42,.10,.3),Vector3(-7.6,1.22,-2.3),WHITE)
	# Waiting seats: cushions, backrests, metal beam, arms and feet.
	for z in [.5,3.4]:
		for x in [-8.1,-6.8,-5.5]:
			box(Vector3(1,.14,.82),Vector3(x,.55,z),TEAL)
			box(Vector3(1,.7,.14),Vector3(x,.94,z+.4),TEAL)
			for side in [-1,1]:
				box(Vector3(.07,.55,.07),Vector3(x+side*.43,.28,z),STEEL)
				box(Vector3(.07,.06,.7),Vector3(x+side*.5,.82,z),STEEL)
			solid(Vector2(x,z),Vector2(1.12,1))
	# Treatment bays with real mattresses, pillows, raised rails and caster wheels.
	for z in [-3.5,2.4]:
		for x in [4.3,7.7]: bed(x,z)
		box(Vector3(.08,2.15,3.8),Vector3(6,1.07,z),Color("82b8b6"))
		for fold in 18:
			box(Vector3(.12,1.8,.075),Vector3(6,1.1,z-1.8+fold*.21),Color("6a9fa2"))
		box(Vector3(.08,.08,3.9),Vector3(6,2.22,z),STEEL)
		solid(Vector2(6,z),Vector2(.12,3.8))
		for x in [4.3,7.7]: monitor(x+1.0,z-1.3)
	# Clinical storage, sink, faucet and dispenser.
	box(Vector3(3.2,.95,.7),Vector3(7.8,.48,6.2),WHITE)
	box(Vector3(3.3,.08,.8),Vector3(7.8,.98,6.2),STEEL)
	box(Vector3(.75,.025,.48),Vector3(8.6,1.03,6.2),Color("526d79"))
	box(Vector3(.05,.35,.05),Vector3(8.6,1.2,6.5),STEEL)
	box(Vector3(.05,.05,.23),Vector3(8.6,1.36,6.4),STEEL)
	for x in [6.5,7.3,8.1,8.9]: box(Vector3(.35,.04,.05),Vector3(x,.74,5.81),STEEL)
	solid(Vector2(7.8,6.2),Vector2(3.4,.9))
	# Waste bins and a stocked medical trolley.
	for x in [2.1,2.65]:
		box(Vector3(.4,.65,.4),Vector3(x,.33,5.8),WHITE if x<2.5 else Color("e0bb52"))
		box(Vector3(.44,.06,.44),Vector3(x,.68,5.8),TEAL)
	for y in [.3,.85]: box(Vector3(.9,.07,.65),Vector3(.9,y,2.7),STEEL)
	for x in [.5,1.3]: box(Vector3(.045,.9,.045),Vector3(x,.5,2.7),STEEL)
	for x in [.65,1.0,1.25]: box(Vector3(.15,.24,.15),Vector3(x,1,2.7),WHITE)
	solid(Vector2(.9,2.7),Vector2(1,.8))
	# Wall cabinets, wash station, water dispenser and a plant in the waiting area.
	for x in [6.8,8.6]:
		box(Vector3(1.65,.8,.44),Vector3(x,1.9,6.7),WHITE)
		box(Vector3(.03,.8,.02),Vector3(x,1.9,6.46),STEEL)
		box(Vector3(.04,.22,.04),Vector3(x+.1,1.9,6.44),STEEL)
	box(Vector3(.75,1.05,.65),Vector3(-8.8,.53,5.8),WHITE)
	box(Vector3(.53,.28,.025),Vector3(-8.8,.71,5.46),Color("3d535c"))
	B.piece(self,Vector3(.6,.8,.6),Vector3(-8.8,1.45,5.8),Color("739fbc"),true)
	solid(Vector2(-8.8,5.8),Vector2(.8,.8))
	B.piece(self,Vector3(.7,.65,.7),Vector3(-3.4,.32,5.7),Color("c1aa8b"),true)
	for i in 7:
		var leaf=B.piece(self,Vector3(.25,.85,.22),Vector3(-3.4+sin(i)*.2,.9,5.7+cos(i)*.2),Color("437469"),true)
		leaf.rotation.z=sin(i)*.65
	for x in [-5,5]:
		box(Vector3(2.7,.12,.18),Vector3(x,2.55,-6.83),STEEL)
		box(Vector3(2.5,.06,.1),Vector3(x,2.50,-6.73),WHITE)
func set_door_amount(amount: float) -> void:
	for i in 2:
		var side=-1.0 if i==0 else 1.0
		door_leaves[i].position.x=side*(.8+amount*1.35)
		door_handles[i].position.x=side*(.16+amount*1.35)
func bed(x: float,z: float) -> void:
	box(Vector3(1.65,.18,2.8),Vector3(x,.55,z),STEEL)
	box(Vector3(1.5,.25,2.65),Vector3(x,.75,z),WHITE)
	box(Vector3(1.52,.07,1.5),Vector3(x,.9,z+.5),Color("80b6be"))
	B.piece(self,Vector3(1.2,.22,.6),Vector3(x,.95,z-.9),WHITE,true)
	for side in [-1,1]:
		box(Vector3(.06,.10,1.9),Vector3(x+side*.84,1.03,z),STEEL)
		for end in [-1,1]:
			box(Vector3(.06,.4,.06),Vector3(x+side*.84,.8,z+end*.85),STEEL)
			box(Vector3(.08,.4,.08),Vector3(x+side*.6,.31,z+end*1.05),STEEL)
			B.piece(self,Vector3(.19,.19,.13),Vector3(x+side*.6,.12,z+end*1.05),Color("344953"),true)
	solid(Vector2(x,z),Vector2(1.85,2.9))
func monitor(x: float,z: float) -> void:
	box(Vector3(.5,.07,.5),Vector3(x,.06,z),STEEL)
	box(Vector3(.06,1.4,.06),Vector3(x,.75,z),STEEL)
	box(Vector3(.62,.48,.22),Vector3(x,1.55,z),WHITE)
	box(Vector3(.5,.35,.015),Vector3(x,1.55,z+.12),Color("163944"))
	for i in 7:
		var line=box(Vector3(.06,.023,.017),Vector3(x-.2+i*.06,1.55+(0.08 if i==3 else 0),z+.13),Color("61e0b2"))
		if i in [2,4]: line.rotation.z=.8 if i==2 else -.8
