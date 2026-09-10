extends "res://world/mountain_pass/WinterResidentModel.gd"
## Atendentes adultos: silhueta contínua, braços articulados e roupa social.
const DETAIL = preload("res://world/shared/pedestrians/CitizenDetails.gd")
var forearms: Array[Node3D] = []

func _ready() -> void:
	scale = Vector3.ONE
	var skin := Color("c38e70") if appearance_female else Color("b88c70")
	var suit := Color("345a60") if appearance_female else Color("344254")
	var shirt := Color("e4dfd0")
	var hair := Color("493027") if appearance_female else Color("302925")
	var shoulders := .205 if appearance_female else .23
	for side in [-1,1]:
		var leg := Node3D.new()
		leg.position=Vector3(side*.105,.87,0)
		add_child(leg)
		limbs.append(leg)
		_shape(leg,Vector3(.15,.73,.18),Vector3(0,-.365,0),suit.darkened(.18))
		_shape(leg,Vector3(.16,.10,.27),Vector3(0,-.815,.04),Color("282a2c"))
		var arm := Node3D.new()
		arm.position=Vector3(side*shoulders,1.40,0)
		add_child(arm)
		limbs.append(arm)
		_garment(arm,Vector3(.125,.29,.15),Vector3(0,-.13,0),suit)
		var forearm := Node3D.new()
		forearm.position=Vector3(0,-.27,0)
		arm.add_child(forearm)
		forearms.append(forearm)
		_garment(forearm,Vector3(.105,.23,.12),Vector3(0,-.105,0),suit)
		_shape(forearm,Vector3(.108,.042,.125),Vector3(0,-.21,0),shirt)
		_shape(forearm,Vector3(.09,.115,.055),Vector3(0,-.285,.015),skin)
	# Ombros e cintura suaves evitam o tronco cúbico do antigo motorista.
	_garment(self,Vector3(.38 if appearance_female else .43,.55,.25),Vector3(0,1.15,0),suit)
	_shape(self,Vector3(.34,.16,.24),Vector3(0,.88,0),suit.darkened(.1))
	_shape(self,Vector3(.12,.13,.13),Vector3(0,1.47,0),skin)
	DETAIL.piece(self,Vector3(.14,.32,.018),Vector3(0,1.26,.128),shirt)
	for side in [-1,1]:
		var lapel := DETAIL.piece(self,Vector3(.065,.27,.025),Vector3(side*.087,1.29,.14),suit.lightened(.15))
		lapel.rotation.z=side*.20
	DETAIL.piece(self,Vector3(.075,.047,.015),Vector3(-.12,1.31,.145),Color("c3b78f"))
	if not appearance_female:
		DETAIL.piece(self,Vector3(.035,.23,.014),Vector3(0,1.23,.15),Color("784951"))
	else:
		DETAIL.piece(self,Vector3(.10,.035,.021),Vector3(0,1.41,.145),Color("aa795d"))
	# Cabeça com cerca de 1/7 da altura; nariz discreto e rente ao rosto.
	_shape(self,Vector3(.225,.285,.225),Vector3(0,1.635,0),skin)
	_shape(self,Vector3(.24,.105,.235),Vector3(0,1.748,-.013),hair)
	_shape(self,Vector3(.228,.17,.09),Vector3(0,1.66,-.088),hair)
	for side in [-1,1]:
		_shape(self,Vector3(.035,.065,.044),Vector3(side*.115,1.625,0),skin)
		_shape(self,Vector3(.026,.012,.014),Vector3(side*.047,1.65,.106),Color("302b2a"))
		DETAIL.piece(self,Vector3(.035,.010,.008),Vector3(side*.047,1.677,.103),hair)
	_shape(self,Vector3(.034,.046,.035),Vector3(0,1.615,.115),skin)
	_shape(self,Vector3(.04,.01,.01),Vector3(0,1.565,.102),skin.darkened(.28))
	if appearance_female:
		_shape(self,Vector3(.17,.17,.15),Vector3(0,1.65,-.18),hair)
		for side in [-1,1]:
			_shape(self,Vector3(.05,.15,.13),Vector3(side*.104,1.70,-.025),hair)
			_shape(self,Vector3(.018,.025,.018),Vector3(side*.128,1.60,.015),Color("c7a466"))
	_process(0.0)

func _shape(parent: Node3D, size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	var piece := DETAIL.piece(parent,size,point,color,true)
	var mesh := piece.mesh as SphereMesh
	mesh.radial_segments=16
	mesh.rings=8
	return piece

func _garment(parent: Node3D, size: Vector3, point: Vector3, color: Color) -> void:
	var piece := DETAIL.piece(parent,Vector3.ONE,point,color)
	var mesh := CylinderMesh.new()
	mesh.top_radius=.5
	mesh.bottom_radius=.42
	mesh.height=1.0
	mesh.radial_segments=16
	piece.mesh=mesh
	piece.scale=size

func _process(delta: float) -> void:
	clock+=delta
	for i in limbs.size():
		if i%2==0:
			limbs[i].rotation.x=sin(clock*7.0+(PI if i==0 else 0.0))*(.33 if walking else .0)
		else:
			var side := -1.0 if i==1 else 1.0
			limbs[i].rotation=Vector3(sin(clock*7.0+(PI if i==3 else 0.0))*(.25 if walking else .012),0,side*.045)
	for forearm in forearms:
		forearm.rotation.x=-.10
