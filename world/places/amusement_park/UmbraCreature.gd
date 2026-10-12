extends Node3D
## Articulated attraction rig. No combat, damage, navigation or autonomous tick.
const GEO := preload("res://world/places/amusement_park/ParkGeometry.gd")
var kind := "wraith"
var joints: Dictionary = {}
var base := Vector3.ZERO

func _ready() -> void:
	base = position
	if kind == "spider": _spider()
	else: _humanoid()

func part(id: String, at: Vector3, parent: Node3D = self) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = id
	pivot.position = at
	parent.add_child(pivot)
	joints[id] = pivot
	return pivot

func art(parent: Node3D):
	var geometry := GEO.new()
	parent.add_child(geometry)
	return geometry

func _humanoid() -> void:
	var pale := "b5b29b" if kind != "doll" else "cab4a5"
	var fabric := "282c31" if kind == "wraith" else "4c2930"
	var torso := part("Torso",Vector3(0,1.12,0))
	var g = art(torso)
	# Tapered shoulders, ribs and overlapping ragged cloth; human-scale silhouette.
	g.ball(Vector3(0,.2,0),Vector3(.46,.64,.25),fabric,"cloth")
	for i in 9:
		var a := TAU*i/9.0
		var p := Vector3(cos(a)*.22,-.04,sin(a)*.16)
		g.beam(p,p+Vector3(cos(a)*.13,-.7-float(i%3)*.10,sin(a)*.14),.16,.035,fabric,"cloth")
	for side in [-1,1]:
		for rib in 4:
			g.beam(Vector3(side*.04,.37-rib*.09,.134),Vector3(side*.19,.31-rib*.09,.10),.025,.027,pale)
	g.flush()
	var head := part("Head",Vector3(0,.66,.035),torso)
	g = art(head)
	g.ball(Vector3.ZERO,Vector3(.31,.42,.29),pale)
	for side in [-1,1]:
		g.ball(Vector3(side*.073,.045,.133),Vector3(.099,.096,.025),"101217")
		g.ball(Vector3(side*.073,.04,.15),Vector3(.026,.024,.009),"c69262","glow")
		g.beam(Vector3(side*.13,.08,.10),Vector3(side*.045,.09,.15),.045,.035,pale)
	g.ball(Vector3(0,-.056,.15),Vector3(.05,.076,.035),"17171a")
	if kind == "wraith":
		for side in [-1,1]: g.beam(Vector3(side*.16,.23,-.04),Vector3(side*.21,-.32,-.05),.115,.14,fabric,"cloth")
		g.box("Hood",Vector3(0,.21,-.055),Vector3(.34,.085,.30),fabric,false,"cloth")
	elif kind == "doll":
		g.ball(Vector3(0,.16,-.07),Vector3(.35,.16,.29),"2b2422")
		for side in [-1,1]: g.ball(Vector3(side*.22,.05,-.05),Vector3(.16,.28,.14),"2b2422")
		g.beam(Vector3(-.12,.14,.135),Vector3(.10,-.1,.15),.012,.008,"403430")
	g.flush()
	var jaw := part("Jaw",Vector3(0,-.10,.02),head)
	g = art(jaw)
	g.box("Mandible",Vector3(0,-.035,.065),Vector3(.21,.075,.16),pale)
	for tooth in 6: g.box("Tooth",Vector3(-.077+tooth*.031,.019,.12),Vector3(.018,.033,.023),"d7c9a5")
	g.flush()
	for side in [-1,1]:
		var arm := part("Arm%d"%side,Vector3(side*.26,.39,0),torso)
		g = art(arm)
		g.beam(Vector3.ZERO,Vector3(side*.11,-.40,0),.085,.085,pale)
		g.ball(Vector3(side*.11,-.40,0),Vector3(.105,.10,.09),pale)
		g.flush()
		var forearm := part("Forearm%d"%side,Vector3(side*.11,-.40,0),arm)
		g = art(forearm)
		g.beam(Vector3.ZERO,Vector3(side*.035,-.39,.09),.065,.055,pale)
		g.ball(Vector3(side*.035,-.44,.10),Vector3(.105,.14,.07),pale)
		for finger in 4:
			var tip := Vector3(side*.035+(finger-1.5)*.027,-.62,.17)
			g.beam(Vector3(tip.x,-.48,.11),tip,.017,.016,pale)
		g.flush()
		g = art(self)
		g.beam(Vector3(side*.115,.50,0),Vector3(side*.14,.10,.04),.085,.08,"393331","cloth")
		g.box("Boot",Vector3(side*.14,.07,.105),Vector3(.14,.14,.28),"292628")
		g.flush()
	if kind == "doll": scale = Vector3.ONE*.64
	elif kind == "wraith": scale = Vector3(1,1.18,1)

func _spider() -> void:
	var g = art(self)
	g.ball(Vector3(0,.46,-.30),Vector3(.66,.51,.90),"28222b")
	g.ball(Vector3(0,.42,.22),Vector3(.46,.35,.40),"484044")
	for i in 4: g.ball(Vector3(-.135+i*.09,.48,.406),Vector3(.038,.045,.028),"b99265","glow")
	for side in [-1,1]: g.beam(Vector3(side*.08,.32,.38),Vector3(side*.13,.17,.57),.045,.04,"c1b398")
	g.flush()
	for side in [-1,1]:
		for leg in 4:
			var pivot := part("Leg%d_%d"%[side,leg],Vector3(side*.2,.43,-.4+leg*.22))
			g = art(pivot)
			var knee := Vector3(side*.53,.23,(leg-1.5)*.22)
			g.beam(Vector3.ZERO,knee,.062,.062,"514951")
			g.beam(knee,Vector3(side*.91,-.39,(leg-1.5)*.35),.038,.032,"514951")
			g.flush()

func animate(time: float, amount: float, visitor: Vector3) -> void:
	if kind == "spider":
		position = base+Vector3(0,-amount*1.15,amount*.24)
		for side in [-1,1]:
			for leg in 4: joints["Leg%d_%d"%[side,leg]].rotation.x = sin(time*4.0+leg*.9+side)*(.035+amount*.22)
		return
	position = base+Vector3(0,sin(time*1.4)*.022+amount*.12,amount*.30)
	joints.Torso.rotation.x = -.10-amount*.30
	joints.Torso.rotation.z = sin(time*.8)*.025
	var look := visitor-(position+Vector3.UP*1.8)
	joints.Head.rotation.y = clampf(atan2(look.x,look.z)-rotation.y,-.65,.65)*.7
	joints.Head.rotation.z = sin(time*.67)*.05+amount*.25
	joints.Jaw.rotation.x = amount*.75
	for side in [-1,1]:
		joints["Arm%d"%side].rotation = Vector3(-amount*1.35,0,side*(.13+sin(time*1.6+side)*.035+amount*.30))
		joints["Forearm%d"%side].rotation.x = -.13-amount*.55
