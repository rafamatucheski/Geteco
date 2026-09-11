extends RefCounted
const Timeline=preload("res://cutscenes/opening/v3/opening_timeline.gd")
## Blocking em espaço do ator; elipses apenas nos cortes de montagem.
var stage: Node3D
var weights: Array[float] = [0.0,0.0]
var rotations: Array[Basis] = [Basis.IDENTITY,Basis.IDENTITY]
var contacts: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
var targets: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
var phone_grips: Array[bool] = [false,false]
const PHONE_REST := Vector3(.34,.75,-.20)
const POT_CONTACT := Vector3(.098,.010,-.018)
const PHONE_CONTACT := Vector3(.022,-.020,-.020)

func _init(value: Node3D) -> void: stage=value
func blend(t: float, a: float, b: float) -> float: return smoothstep(a,b,t)

func grip(index: int, object: Node3D, point: Vector3, weight: float, basis: Basis) -> Vector3:
	weights[index]=weight; rotations[index]=basis
	phone_grips[index]=object==stage.phone
	stage.hands[index].contact_local.z=-.060 if phone_grips[index] else -.043
	contacts[index]=object.to_global(point)
	var wrist: Vector3=contacts[index]-basis*stage.hands[index].contact_local
	return stage.actor.to_local(wrist)

func phone_position(lift: float) -> Vector3:
	# Primeiro sobe por fora da mesa, do mesmo lado do ouvido.
	var ear: Vector3=stage.actor.to_global(Vector3(.145,1.155,.005))
	return PHONE_REST.bezier_interpolate(Vector3(.40,.82,-.20),Vector3(.34,1.04,-.04),ear,lift)

func apply(t: float) -> void:
	weights.assign([0.0,0.0])
	phone_grips.assign([false,false])
	var left:=Vector3(-.23,.85,-.22)
	var right:=Vector3(.26,.85,-.20)
	var photo: Node3D=stage.loose_photo
	var bag: Node3D=stage.backpack
	var phone: Node3D=stage.phone
	photo.visible=t<46
	stage.frame_photo.visible=true
	var frame_origin: Vector3=stage.photo_frame.to_global(Vector3(0,.118,-.020))
	photo.position=frame_origin; photo.rotation=Vector3.ZERO
	bag.visible=t<42 or (t>=53 and t<61)
	bag.position=Vector3(.63,.015,.03); bag.rotation=Vector3.ZERO
	stage.flap.rotation.x=0
	phone.visible=t<38 or (t>=53 and t<61)
	stage.phone_gallery.visible=false
	phone.position=PHONE_REST; phone.rotation=Vector3(PI/3,0,0)
	stage.phone_label.text="" if t>=18.2 else ("DESCONHECIDO" if stage.lang=="pt" else "UNKNOWN")
	if t>=16 and t<17.25: phone.position.x+=sin(t*85)*.0009
	for palm in stage.palms: palm.basis=Basis.IDENTITY
	if t<6:
		var hold:=1.0-blend(t,4.2,5.3)
		right=right.lerp(grip(1,stage.pot,POT_CONTACT,hold,stage.pot.global_basis),hold)
	elif t<13:
		stage.lid.rotation.x=0
		stage._camera(Vector3(-.57,1.05,-1.28).lerp(Vector3(-.47,.97,-1.14),(t-6)/7),Vector3(-.30,.79,-.28),33)
	if t>=13 and t<18:
		stage._camera(Vector3(.22,1.22,-.90),Vector3(.34,.76,-.20),30)
	if t>=17.25 and t<32.8:
		var reach:=blend(t,17.25,18.20)
		var lift:=blend(t,18.20,19.05)*(1-blend(t,31,32.1))
		phone.position=phone_position(lift)
		phone.rotation=Vector3(PI/3,0,0).lerp(Vector3(0,PI/2,.05),lift)
		var hold:=reach*(1-blend(t,32.15,32.8))
		right=right.lerp(grip(1,phone,PHONE_CONTACT,hold,phone.global_basis*Basis(Vector3.FORWARD,PI)),hold)
	# Nove segundos acrescentados: mãos pousadas, respiração, olhar e decisão.
	if stage.clock_time>=Timeline.REFLECTION_START and stage.clock_time<Timeline.REFLECTION_END:
		var age: float=stage.clock_time-Timeline.REFLECTION_START
		stage.host.torso_node.rotation.x=.025+sin(age*1.0)*.009
		stage.host.head_node.rotation=Vector3(-.15,0,0).lerp(Vector3(-.21,-.30,-.025),blend(age,3.5,7.0))
		stage.host.head_node.rotation.x-=sin(blend(age,7.4,8.6)*PI)*.045
		stage._camera(Vector3(-.28,1.12,-1.12).lerp(Vector3(-.34,1.11,-1.08),age/9),Vector3(-.025,1.035,-.04),34)
	# Depois de pensar, abre no celular uma foto que ja estava na galeria.
	# A fotografia fisica permanece no porta-retrato durante toda a cena.
	if t>=33.15 and t<38:
		var reach:=blend(t,33.15,33.95)
		var lift:=blend(t,34.05,35.10)
		phone.position=PHONE_REST.lerp(stage.actor.to_global(Vector3(.10,.99,-.28)),lift)
		phone.position.y+=sin(lift*PI)*.025
		phone.rotation=Vector3(PI/3,0,0).lerp(Vector3(.85,PI,0),lift)
		var wrist:=grip(1,phone,PHONE_CONTACT,reach,phone.global_basis*Basis(Vector3.FORWARD,PI))
		right=right.lerp(wrist,reach)
		stage.host.head_node.rotation=Vector3(-.24,.03,0)
		stage.phone_gallery.visible=t>=35.45
		if t<34.85:
			stage._camera(Vector3(-.45,1.14,-1.48),Vector3(.06,.94,-.16),36)
		else:
			var push:=blend(t,34.85,38)
			stage._camera(Vector3(.30,1.20,.015).lerp(Vector3(.19,1.09,-.04),push),phone.to_global(Vector3(0,.024,-.011)),27)
	if t>=38 and t<42:
		# Corte após a decisão: passagem de tempo até a saída pronta.
		var age:=t-38
		var walk:=blend(t,38.2,41.6)
		stage.actor.position=Vector3(1.62,0,.35).lerp(Vector3(1.88,0,1.85),walk)
		stage.actor.rotation.y=PI
		stage.host.head_node.rotation=Vector3.ZERO
		stage.host.torso_node.rotation=Vector3(.025,0,0)
		for i in 2:
			var upper: Node3D=stage.host.left_upper_leg if i==0 else stage.host.right_upper_leg
			var lower: Node3D=stage.host.left_lower_leg if i==0 else stage.host.right_lower_leg
			var stride:=sin(age*7+PI*i)*.30*sin(walk*PI)
			upper.rotation=Vector3(stride,0,0); lower.rotation=Vector3(minf(0,-stride)*.65,0,0)
		left=Vector3(-.23,.67,-.04); right=Vector3(.23,.67,-.04)
		bag.position=stage.actor.to_global(Vector3(0,.73,.22)); bag.basis=stage.actor.basis*Basis(Vector3.UP,PI)
		stage.door.rotation.y=-1.35*blend(t,38,38.8)
		stage._camera(Vector3(.65,1.48,-1.40),Vector3(1.73,.99,.90),40)
	if t>=42 and t<46:
		stage.door.rotation.y=-1.35*(1-blend(t,43.5,44.5))
	if t>=53 and t<61:
		var age:=t-53
		bag.position=Vector3(-.12,.015,.23)
		phone.position=stage.actor.to_global(Vector3(.10,.97,-.26).lerp(Vector3(.10,.87,-.22),blend(t,58.7,60.4)))
		phone.rotation=Vector3(.85,PI,0)
		stage.phone_gallery.visible=true
		left=Vector3(-.21,.72,-.22)
		right=grip(1,phone,PHONE_CONTACT,1,phone.global_basis*Basis(Vector3.FORWARD,PI))
		stage.host.head_node.rotation=Vector3(-.19,.05,0).lerp(Vector3(-.02,-.45,0),blend(t,57.2,60))
		if t<55:
			stage._camera(stage.actor.to_global(Vector3(.22,1.28,-.03)),phone.to_global(Vector3(0,.024,-.011)),28)
		else:
			stage._camera(Vector3(.30,1.19,-1.43).lerp(Vector3(.20,1.15,-1.32),age/8),Vector3(-.51,.98,-.04),40)
	targets.assign([left,right])
	for i in 2:
		var upper: Node3D=stage.host.left_upper_arm if i==0 else stage.host.right_upper_arm
		var lower: Node3D=stage.host.left_lower_arm if i==0 else stage.host.right_lower_arm
		var side: float=-1 if i==0 else 1
		var pole:=Vector3(side*.35,.76,-.07)-upper.position
		stage._arm(upper,lower,targets[i],pole,.24)
		var palm: Node3D=stage.palms[i]
		var orientation_weight:=weights[i]
		palm.global_basis=palm.global_basis.orthonormalized().slerp(rotations[i],orientation_weight).orthonormalized()
		stage.hands[i].set_grip(weights[i],phone_grips[i])
