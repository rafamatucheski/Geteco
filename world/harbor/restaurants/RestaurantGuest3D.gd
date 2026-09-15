extends Node3D
## Articulated café patron. One metre matches the street citizen scale.
const PARTS := preload("res://characters/pedestrians/CitizenDetails.gd")
var variant := 0
var body: Node3D
var head: Node3D
var arms: Array[Node3D] = []
var elbows: Array[Node3D] = []
var hips: Array[Node3D] = []
var knees: Array[Node3D] = []
var fork: Node3D
var sit_amount := 1.0
var activity := "talking"

func build(index: int) -> void:
	variant = index
	var skin: Color = [Color("d7a179"), Color("8e5c42"), Color("e9bb9e"), Color("6b4635")][index % 4]
	var shirt: Color = [Color("56817c"), Color("cf875b"), Color("dcceaf"), Color("516886"), Color("976277"), Color("6c7851")][index % 6]
	var pants := Color("303d50")
	var hair: Color = [Color("38271f"), Color("29282b"), Color("a99782"), Color("62412a")][index % 4]
	body = Node3D.new()
	body.name = "SeatedBody"
	add_child(body)
	PARTS.piece(body, Vector3(.34,.43,.22), Vector3(0,1.12,0), shirt, true)
	PARTS.piece(body, Vector3(.31,.15,.23), Vector3(0,.87,0), pants, true)
	PARTS.piece(body, Vector3(.10,.10,.10), Vector3(0,1.37,0), skin, true)
	head = Node3D.new()
	head.position.y = 1.51
	body.add_child(head)
	PARTS.piece(head, Vector3(.25,.29,.245), Vector3.ZERO, skin, true)
	PARTS.piece(head, Vector3(.265,.14,.25), Vector3(0,.105,.012), hair, true)
	if index % 2 == 1:
		PARTS.piece(head, Vector3(.24,.22,.11), Vector3(0,-.005,.10), hair, true)
		PARTS.piece(head, Vector3(.09,.14,.11), Vector3(0,-.11,.15), hair, true)
	for side in [-1,1]:
		PARTS.piece(head, Vector3(.025,.019,.014), Vector3(side*.052,.014,-.119), Color("29252a"))
		PARTS.piece(head, Vector3(.034,.055,.040), Vector3(side*.127,-.015,0), skin, true)
	PARTS.piece(head, Vector3(.04,.048,.055), Vector3(0,-.02,-.13), skin, true)
	PARTS.piece(head, Vector3(.05,.009,.01), Vector3(0,-.069,-.11), skin.darkened(.35))
	# Collar, pocket and buttons stay small enough to match the rest of the cast.
	PARTS.piece(body, Vector3(.12,.045,.024), Vector3(0,1.315,-.087), shirt.lightened(.25))
	PARTS.piece(body, Vector3(.063,.062,.014), Vector3(-.087,1.20,-.10), shirt.darkened(.16))
	for side in [-1,1]:
		var arm := Node3D.new()
		arm.position = Vector3(side*.205,1.29,0)
		body.add_child(arm)
		arms.append(arm)
		PARTS.piece(arm, Vector3(.125,.27,.14), Vector3(0,-.115,0), shirt, true)
		var elbow := Node3D.new()
		elbow.position.y = -.235
		arm.add_child(elbow)
		elbows.append(elbow)
		PARTS.piece(elbow, Vector3(.09,.235,.10), Vector3(0,-.105,0), skin, true)
		PARTS.piece(elbow, Vector3(.085,.095,.06), Vector3(0,-.24,0), skin, true)
		var hip := Node3D.new()
		hip.position = Vector3(side*.10,.88,0)
		body.add_child(hip)
		hips.append(hip)
		PARTS.piece(hip, Vector3(.15,.405,.19), Vector3(0,-.19,0), pants, true)
		var knee := Node3D.new()
		knee.position.y = -.38
		hip.add_child(knee)
		knees.append(knee)
		PARTS.piece(knee, Vector3(.13,.36,.15), Vector3(0,-.17,0), pants, true)
		PARTS.piece(knee, Vector3(.15,.115,.26), Vector3(0,-.37,-.045), Color("eee5d0") if index % 3 == 0 else Color("332e2a"), true)
	fork = Node3D.new()
	fork.position = Vector3(0,-.257,-.025)
	elbows[1].add_child(fork)
	PARTS.piece(fork,Vector3(.018,.12,.015),Vector3(0,-.025,0),Color("b9c2c7"))
	for tooth in 3:
		PARTS.piece(fork,Vector3(.006,.032,.011),Vector3((tooth-1)*.012,-.10,0),Color("d4dbdf"))
	pose(0.0,1.0,false)

func pose(clock: float, seated: float, walking: bool) -> void:
	sit_amount = seated
	body.position.y = -.41 * seated
	var phase := fposmod(clock + variant * 2.71, 15.0)
	var bite := sin(clampf((phase-7.0)/3.2,0.0,1.0)*PI)
	activity = "eating" if phase >= 7.0 and phase < 10.2 else "talking"
	for i in 2:
		hips[i].rotation.x = seated * PI*.5 + (sin(clock*4.0+i*PI)*.35 if walking else 0.0)
		knees[i].rotation.x = -seated * PI*.5
		arms[i].rotation.x = seated * (.52 + (bite*.13 if i == 1 else .05*sin(clock*1.7+variant)))
		elbows[i].rotation.x = seated * (1.10 + (bite*1.30 if i == 1 else .10*sin(clock*2.0)))
		arms[i].rotation.z = (-.09 if i == 0 else .09) + seated*.055*sin(clock*1.5+variant)
		if walking:
			arms[i].rotation.x = sin(clock*4.0+i*PI+PI)*.3
	head.rotation.y = seated * .12*sin(clock*.65+variant)
	head.rotation.x = seated * (.035*sin(clock*1.3) + bite*.09)
	fork.visible = seated > .8
