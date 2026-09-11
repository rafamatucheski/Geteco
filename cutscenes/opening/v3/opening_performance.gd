extends RefCounted
## Trajetórias contínuas. O objeto só sai do apoio depois do contato dos dedos.
var stage: Node3D
var weights: Array[float] = [0.0,0.0]
var rotations: Array[Basis] = [Basis.IDENTITY,Basis.IDENTITY]
var contacts: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
var targets: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]

func _init(value: Node3D) -> void: stage=value
func blend(t: float, a: float, b: float) -> float: return smoothstep(a,b,t)

func grip(index: int, object: Node3D, point: Vector3, weight: float, basis: Basis) -> Vector3:
	weights[index]=weight; rotations[index]=basis
	contacts[index]=object.to_global(point)
	var wrist: Vector3=contacts[index]-basis*stage.hands[index].contact_local
	return stage.actor.to_local(wrist)

func photo_grip(index: int, y: float, weight: float) -> Vector3:
	var side: float=-1 if index==0 else 1
	return grip(index,stage.loose_photo,Vector3(side*.126,y,-.003),weight,
		stage.loose_photo.global_basis*Basis(Vector3.FORWARD,PI))

func apply(t: float) -> void:
	weights.assign([0.0,0.0])
	var left:=Vector3(-.22,.85,-.23)
	var right:=Vector3(.24,.85,-.22)
	var photo: Node3D=stage.loose_photo
	var bag: Node3D=stage.backpack
	var phone: Node3D=stage.phone
	# Um único papel existe no quadro, na retirada e dentro da mochila.
	photo.visible=t<42 or (t>=53 and t<61)
	stage.frame_photo.visible=true
	photo.position=stage.photo_frame.to_global(Vector3(0,.118,-.020))
	photo.rotation=Vector3.ZERO
	bag.visible=t<42 or (t>=53 and t<61)
	bag.position=Vector3(.52,.39,.02); bag.rotation=Vector3.ZERO
	stage.flap.rotation.x=-1.25
	phone.visible=t<42
	phone.position=Vector3(.08,.67,-.21); phone.rotation=Vector3(PI/2,0,.1)
	if t>=16 and t<17.25: phone.position.x+=sin(t*85)*.0009
	for palm in stage.palms: palm.basis=Basis.IDENTITY
	if t<6:
		var hold:=1.0-blend(t,4.2,5.3)
		var at:=grip(1,stage.pot,Vector3(.077,.0,-.012),hold,stage.pot.global_basis)
		right=right.lerp(at,hold)
	elif t<13:
		var hold:=blend(t,9.5,10.4)*(1-blend(t,11.15,12.0))
		var at:=grip(0,stage.lid,Vector3(.15,0,-.09),hold,stage.lid.global_basis*Basis(Vector3.FORWARD,PI))
		left=left.lerp(at,hold)
		stage._camera(Vector3(-.57,1.05,-1.28).lerp(Vector3(-.47,.97,-1.14),(t-6)/7),Vector3(-.30,.79,-.28),33)
	if t>=13 and t<18:
		stage._camera(Vector3(-.10,1.20,-.84),Vector3(.08,.68,-.23),29)
	# O telefone permanece na mesa até a mão alcançá-lo; volta ao mesmo apoio.
	if t>=17.25 and t<32.8:
		var reach:=blend(t,17.25,18.20)
		var lift:=blend(t,18.20,19.0)*(1-blend(t,31,32.1))
		phone.position=Vector3(.08,.67,-.21).lerp(stage.actor.position+Vector3(.130,1.205,.015),lift)
		phone.rotation=Vector3(PI/2,0,.1).lerp(Vector3(0,PI/2,-.10),lift)
		var hold:=reach*(1-blend(t,32.15,32.8))
		var at:=grip(1,phone,Vector3(-.014,-.020,-.011),hold,phone.global_basis*Basis(Vector3.FORWARD,PI))
		right=right.lerp(at,hold)
	# Inclinação pequena permite alcançar a borda sem esticar o braço além do rig.
	if t>=32.4 and t<38:
		stage.actor.position.z=-.045*blend(t,32.4,33.6)*(1-blend(t,35.5,36.5))
		stage.host.torso_node.rotation.x+=.05*blend(t,32.4,33.6)*(1-blend(t,35.5,36.5))
	if t>=33.7 and t<42:
		var from: Vector3=stage.photo_frame.to_global(Vector3(0,.118,-.020))
		var take:=blend(t,33.7,35.2)
		photo.position=from.lerp(Vector3(-.08,.88,-.27),take)
		photo.position.y+=sin(take*PI)*.045
		photo.rotation=Vector3(-.20,0,-.035)*take
	if t>=32.5 and t<39.75:
		var reach:=blend(t,32.5,33.65)
		var hold:=reach*(1-blend(t,39.25,39.75))
		var at:=photo_grip(0,lerpf(.055,-.035,blend(t,33.9,35.2)),hold)
		left=left.lerp(at,hold)
	if t>=34.15 and t<36.2:
		var hold:=blend(t,34.15,34.85)*(1-blend(t,35.7,36.2))
		var at:=photo_grip(1,-.035,hold)
		right=right.lerp(at,hold)
	# A direita traz a mochila; a esquerda insere o papel pela abertura superior.
	if t>=36.2 and t<42:
		var carry:=blend(t,36.9,37.7)
		bag.position=Vector3(.52,.39,.02).lerp(Vector3(.18,.655,-.22),carry)
		bag.position.y+=sin(carry*PI)*.055
		var reach:=blend(t,36.2,36.9)
		var at:=grip(1,bag,Vector3(0,.36,.018),reach,bag.global_basis)
		right=right.lerp(at,reach)
		var place:=blend(t,37.55,38.15)
		photo.position=Vector3(-.08,.88,-.27).lerp(Vector3(.18,1.13,-.22),place)
		photo.rotation=Vector3(-.20,0,-.035).lerp(Vector3.ZERO,place)
		photo.position=photo.position.lerp(Vector3(.18,.815,-.22),blend(t,38.15,39.25))
		stage.flap.rotation.x=lerpf(-1.25,0,blend(t,41.65,41.98))
		if t<39.75:
			var hold:=1-blend(t,39.25,39.75)
			left=left.lerp(photo_grip(0,-.035,hold),hold)
		if t>=38: stage._camera(Vector3(.78,1.31,-1.03),Vector3(.16,.91,-.22),35)
	# O telefone também viaja: a direita o recolhe antes de fechar a mochila.
	if t>=39.75 and t<42:
		var leave_handle:=1-blend(t,39.75,40.0)
		var hold:=blend(t,40.0,40.6)*(1-blend(t,41.65,41.98))
		var lift:=blend(t,40.6,41.1)
		phone.position=Vector3(.08,.67,-.21).lerp(Vector3(.18,1.12,-.22),lift)
		phone.rotation=Vector3(PI/2,0,.1).lerp(Vector3.ZERO,lift)
		phone.position=phone.position.lerp(Vector3(.18,.84,-.22),blend(t,41.1,41.65))
		var resting:=Vector3(.24,.85,-.22)
		var handle_wrist:=right
		var at:=grip(1,phone,Vector3(-.014,-.020,-.011),hold,phone.global_basis*Basis(Vector3.FORWARD,PI))
		right=resting.lerp(handle_wrist,leave_handle).lerp(at,hold)
	if t>=53 and t<61:
		var age:=t-53
		bag.position=stage.actor.to_global(Vector3(.30,.60,-.02))
		bag.rotation=Vector3.ZERO
		stage.flap.rotation.x=lerpf(-1.25,0,blend(t,54.8,55.5))
		var local:=Vector3(.30,.81,-.02).lerp(Vector3(.30,1.10,-.02),blend(t,53.2,54.0))
		local=local.lerp(Vector3(0,.98,-.25),blend(t,54.0,54.8))
		local=local.lerp(Vector3(0,.90,-.21),blend(t,58.7,60.4))
		photo.position=stage.actor.to_global(local)
		photo.rotation=Vector3(-.24,0,0)*blend(t,54,54.8)
		photo.rotation.z=sin(age*1.4)*.009*blend(t,54.5,55.5)
		left=Vector3(-.13,.77,-.18); right=Vector3(.33,.93,-.035)
		var reach:=blend(t,53,53.2)
		right=right.lerp(photo_grip(1,lerpf(.055,-.035,blend(t,54,54.8)),reach),reach)
		var support:=blend(t,54.0,54.8)
		left=left.lerp(photo_grip(0,-.035,support),support)
		stage.host.head_node.rotation=Vector3(-.15,.12,0).lerp(Vector3(-.02,-.45,0),blend(t,57.2,60))
		stage._camera(Vector3(.38,1.19,-1.40).lerp(Vector3(.24,1.15,-1.25),age/8),Vector3(-.51,.96,-.01),40)
	targets.assign([left,right])
	stage._arm(stage.host.left_upper_arm,stage.host.left_lower_arm,left,Vector3(-.7,-1,.1))
	stage._arm(stage.host.right_upper_arm,stage.host.right_lower_arm,right,Vector3(.10,-1,-1.5) if t>=17.25 and t<32.8 else Vector3(.7,-1,.1))
	for i in 2:
		var palm: Node3D=stage.palms[i]
		var natural:=palm.global_basis.orthonormalized()
		palm.global_basis=natural.slerp(rotations[i],weights[i]).orthonormalized()
		stage.hands[i].set_grip(weights[i])
