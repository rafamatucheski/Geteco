extends Node3D
## Display wildlife: separated lanes inside physically closed pens.
const GEO=preload("res://world/mountain_detail/zoo/ZooGeometry.gd")
var species := "giraffe"
var phase := 0.0
var home := Vector3.ZERO
var legs: Array[Node3D]=[]
var head: Node3D
var clock:=0.0
var moving:=false
func _ready() -> void:
	var g:=GEO.new()
	var coat: String={"giraffe":"d8b56a","lion":"bd8748","monkey":"77735e","zebra":"e4dfcf"}[species]
	var h:=2.0 if species=="giraffe" else (1.0 if species=="zebra" else (.82 if species=="lion" else .30))
	var length:=1.75 if species=="giraffe" else (1.9 if species=="lion" else (1.6 if species=="zebra" else .52))
	g.part("round",Vector3(0,h+(.22 if species=="lion" else .4),0),Vector3(.68,.66,length) if species=="lion" else (Vector3(.85,.95,length) if species!="monkey" else Vector3(.40,.52,.67)),coat)
	if species=="lion":
		g.part("round",Vector3(0,h+.25,-.56),Vector3(.65,.75,.72),coat)
		g.part("round",Vector3(0,h+.18,.63),Vector3(.58,.65,.66),coat)
	for side in [-1.0,1.0]:
		for end in [-1.0,1.0]:
			var leg:=Node3D.new()
			leg.position=Vector3(side*.28,h,end*length*.32)
			add_child(leg); legs.append(leg)
			var lg:=GEO.new()
			var thickness:=.22 if species=="lion" else (.105 if species=="monkey" else .16)
			lg.part("round",Vector3(0,-h*.28,0),Vector3(thickness*1.2,h*.80,thickness*1.3),coat)
			lg.part("round",Vector3(0,-h*.66,0),Vector3(thickness*.8,h*.68,thickness),coat)
			lg.part("round",Vector3(0,-h+.09,-.035),Vector3(.30,.20,.38) if species=="lion" else Vector3(.19,.18,.26),coat if species=="lion" else "342c25")
			lg.flush(leg)
	head=Node3D.new(); add_child(head)
	var hg:=GEO.new()
	if species=="giraffe":
		head.position=Vector3(0,h+.65,-.55)
		hg.part("round",Vector3(0,.87,-.2),Vector3(.42,2.1,.50),coat,Vector3(-.17,0,0))
		hg.part("round",Vector3(0,1.89,-.49),Vector3(.45,.45,.86),coat)
		for side in [-1.0,1.0]:
			hg.part("round",Vector3(side*.31,1.95,-.25),Vector3(.4,.14,.22),coat,Vector3(0,0,side*.35))
			hg.part("pole",Vector3(side*.13,2.21,-.31),Vector3(.07,.35,.07),"785033")
			hg.part("round",Vector3(side*.13,2.39,-.31),Vector3.ONE*.12,"493326")
			hg.part("round",Vector3(side*.21,1.95,-.57),Vector3.ONE*.075,"171b16")
		g.part("round",Vector3(0,h+.15,.98),Vector3(.09,.13,.7),"b7975d",Vector3(-.5,0,0))
		g.part("round",Vector3(0,h-.06,1.2),Vector3(.12,.34,.15),"493326")
	elif species=="monkey":
		head.position=Vector3(0,.90,-.25)
		hg.part("round",Vector3.ZERO,Vector3(.37,.41,.37),"b4b29b")
		hg.part("round",Vector3(0,-.035,-.17),Vector3(.26,.29,.12),"292a25")
		hg.part("round",Vector3(0,-.10,-.235),Vector3(.13,.10,.09),"444238")
		for side in [-1.0,1.0]:
			hg.part("round",Vector3(side*.21,0,0),Vector3(.13,.16,.08),"504a3a")
			hg.part("round",Vector3(side*.07,.035,-.233),Vector3.ONE*.04,"ad8e43")
		for i in 8:
			g.part("round",Vector3(0,.5+sin(i*.4)*.4,.23+i*.105),Vector3(.08,.12,.20),coat,Vector3(-i*.13,0,0))
	else:
		head.position=Vector3(0,h+(.43 if species=="lion" else .65),-length*.43)
		if species=="zebra": g.part("round",Vector3(0,h+.50,-.60),Vector3(.44,.85,.63),coat,Vector3(-.35,0,0))
		if species=="lion" and int(phase)%2==0:
			hg.part("round",Vector3(0,0,.03),Vector3(.94,1.03,.70),"65402a")
			for i in 12:
				var angle:=TAU*i/12
				hg.part("round",Vector3(sin(angle)*.39,cos(angle)*.44,.0),Vector3(.23,.37,.35),"785031",Vector3(0,0,-angle))
		hg.part("round",Vector3(0,0,-.18),Vector3(.59,.59,.67),coat)
		hg.part("round",Vector3(0,-.16,-.47),Vector3(.39,.27,.33),"d0b591" if species=="lion" else "524b44")
		for side in [-1.0,1.0]:
			hg.part("round",Vector3(side*.26,.29,-.08),Vector3(.20,.22 if species=="lion" else .43,.16),coat)
			hg.part("round",Vector3(side*.23,.055,-.40),Vector3.ONE*.075,"171b16")
			hg.part("round",Vector3(side*.115,-.12,-.59),Vector3(.21,.17,.12),"d9c0a0" if species=="lion" else "524b44")
		hg.part("round",Vector3(0,-.07,-.62),Vector3(.14,.08,.08),"262621")
		if species=="zebra":
			g.part("box",Vector3(0,h+.88,-.48),Vector3(.10,.35,.6),"302c2b")
		g.part("round",Vector3(0,h+.45,length*.64),Vector3(.09,.10,.7),coat)
		g.part("round",Vector3(0,h+.43,length*.84),Vector3(.16,.17,.23),"493326")
	hg.flush(head); g.flush(self)
	if int(phase)%3==2: scale=Vector3.ONE*(.68 if species=="giraffe" else .82)
	position=home
func advance(delta: float) -> void:
	clock+=delta
	var t:=clock*.28+phase
	var progress:=t-sin(t)
	moving=cos(t)<.85
	position=home+Vector3(sin(progress)*1.2,0,cos(progress)*.70)
	rotation.y=atan2(-cos(progress)*1.2,sin(progress)*.70)
	for i in legs.size(): legs[i].rotation.x=sin(clock*3.0+(floori(i/2.0) if species=="giraffe" else i%2)*PI)*.09*(1.0 if moving else .1)
	head.rotation.x=sin(clock*.8+phase)*.035
