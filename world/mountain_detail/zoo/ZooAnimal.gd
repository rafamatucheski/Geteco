extends Node3D
## Shared sculpted anatomy with articulated limbs; distance-driven walking and true rests.
const ANATOMY = preload("res://world/mountain_detail/zoo/ZooAnimalAnatomy.gd")
var species := "giraffe"
var phase := 0.0
var home := Vector3.ZERO
var legs: Array[Node3D] = []
var knees: Array[Node3D] = []
var tail: Array[Node3D] = []
var head: Node3D
var torso: Node3D
var neck: Node3D
var clock := 0.0
var moving := false
var _gait := 0.0
var _motion_initialized := false
var _leg_height := 1.0
var _coat := ""
var _stride := .8
func _ready() -> void:
	_coat = {"giraffe":"d8b56a","lion":"bf9055","monkey":"77684e","zebra":"e4dfcf"}[species]
	_leg_height = {"giraffe":1.82,"lion":.70,"monkey":.31,"zebra":.94}[species]
	_stride = {"giraffe":1.1,"lion":.75,"monkey":.36,"zebra":.8}[species]
	torso = Node3D.new(); torso.name = "ShouldersAndRibcage"; add_child(torso)
	_build_torso()
	_build_legs()
	_build_head()
	_build_tail()
	if int(phase)%3 == 2: scale = Vector3.ONE*(.68 if species == "giraffe" else .82)
	advance(0.0)
func _bone(parent: Node3D, label: String, at: Vector3) -> Node3D:
	var bone := Node3D.new(); bone.name = label; bone.position = at; parent.add_child(bone)
	return bone
func _build_torso() -> void:
	var g = ANATOMY.new(species+"_torso")
	var y := _leg_height
	match species:
		"giraffe":
			g.loft([Vector3(0,y+.34,-.91),Vector3(0,y+.48,-.57),Vector3(0,y+.37,.08),Vector3(0,y+.21,.62),Vector3(0,y+.17,.92)],
				[Vector2(.03,.08),Vector2(.38,.52),Vector2(.43,.49),Vector2(.32,.37),Vector2(.04,.09)],_coat)
		"zebra":
			g.loft([Vector3(0,y+.29,-.83),Vector3(0,y+.40,-.54),Vector3(0,y+.36,.0),Vector3(0,y+.33,.53),Vector3(0,y+.28,.81)],
				[Vector2(.07,.12),Vector2(.35,.46),Vector2(.40,.46),Vector2(.35,.41),Vector2(.09,.20)],_coat)
		"lion":
			g.loft([Vector3(0,y+.27,-1.01),Vector3(0,y+.36,-.69),Vector3(0,y+.28,-.17),Vector3(0,y+.24,.39),Vector3(0,y+.25,.82)],
				[Vector2(.09,.14),Vector2(.33,.37),Vector2(.32,.32),Vector2(.24,.24),Vector2(.24,.28)],_coat)
			g.form(Vector3(0,y+.10,-.67),Vector3(.51,.37,.57),"d7b787")
		"monkey":
			g.loft([Vector3(0,y+.26,-.35),Vector3(0,y+.30,-.17),Vector3(0,y+.24,.12),Vector3(0,y+.17,.34)],
				[Vector2(.05,.08),Vector2(.19,.26),Vector2(.23,.28),Vector2(.10,.14)],_coat)
			g.form(Vector3(0,y+.10,-.11),Vector3(.28,.26,.47),"b4a285")
	g.flush(torso)
func _build_legs() -> void:
	var length: float = {"giraffe":1.65,"zebra":1.48,"lion":1.69,"monkey":.52}[species]
	var width: float = {"giraffe":.28,"zebra":.25,"lion":.24,"monkey":.16}[species]
	for side in [-1.0,1.0]:
		for end in [-1.0,1.0]:
			var front: bool = end < 0
			var hip := Vector3(side*width,_leg_height,end*length*.35)
			var leg := _bone(self,"FrontLeg" if front else "HindLeg",hip); legs.append(leg)
			var upper := _leg_height*.49
			var lower := _leg_height-upper
			var thickness: float = {"giraffe":.105,"zebra":.12,"lion":.13,"monkey":.065}[species]
			var knee_at := Vector3(0,-upper,.035 if front else .10)
			var g = ANATOMY.new(species+"_upper_"+str(side)+str(end))
			g.loft([Vector3(0,.17,0),Vector3(0,-upper*.20,0),knee_at*.78,knee_at],
				[Vector2(thickness*1.4,thickness*1.7),Vector2(thickness*1.45,thickness*1.6),Vector2(thickness*.69,thickness*.82),Vector2(thickness*.7,thickness*.72)],_coat,hip)
			g.flush(leg)
			var knee := _bone(leg,"CarpalJoint" if front else "Hock",knee_at); knees.append(knee)
			var foot := Vector3(0,-lower+.065,-knee_at.z)
			var shin = ANATOMY.new(species+"_lower_"+str(side)+str(end))
			shin.loft([Vector3.ZERO,Vector3(0,-lower*.36,.02),foot+Vector3(0,.09,.01),foot],
				[Vector2(thickness*.72,thickness*.72),Vector2(thickness*.53,thickness*.60),Vector2(thickness*.47,thickness*.53),Vector2(thickness*.63,thickness*.62)],_coat,hip+knee_at)
			var hoof := species in ["giraffe","zebra"]
			var foot_color := "36322d" if hoof else ("66523c" if species == "monkey" else "cda56e")
			shin.form(foot+Vector3(0,-.015,-.065),Vector3(thickness*2.0,.13,thickness*2.7),foot_color)
			if species in ["lion","monkey"]:
				for toe in [-1.0,0.0,1.0]:
					shin.form(foot+Vector3(toe*thickness*.53,-.023,-thickness*1.37),Vector3(thickness*.5,.075,.08),foot_color)
			shin.flush(knee)
func _build_head() -> void:
	var g
	if species == "giraffe":
		var base := Vector3(0,2.49,-.63)
		neck = _bone(torso,"SlopedNeck",base)
		g = ANATOMY.new("giraffe_neck")
		g.loft([Vector3(0,-.18,.11),Vector3(0,.23,-.05),Vector3(0,.92,-.22),Vector3(0,1.59,-.43)],
			[Vector2(.28,.31),Vector2(.25,.28),Vector2(.16,.20),Vector2(.14,.17)],_coat,base)
		g.loft([Vector3(0,.08,.24),Vector3(0,.79,.02),Vector3(0,1.54,-.25)],
			[Vector2(.043,.045),Vector2(.036,.055),Vector2(.012,.02)],"66492e")
		g.flush(neck)
		head = _bone(neck,"Head",Vector3(0,1.60,-.43))
		g = ANATOMY.new("giraffe_head")
		g.loft([Vector3(0,.03,.20),Vector3(0,.09,.01),Vector3(0,-.04,-.30),Vector3(0,-.09,-.53)],
			[Vector2(.06,.09),Vector2(.22,.25),Vector2(.15,.14),Vector2(.13,.105)],_coat,base+head.position)
		g.form(Vector3(0,-.065,-.51),Vector3(.29,.22,.18),"a98654")
		for side in [-1.0,1.0]:
			_ear(g,Vector3(side*.19,.17,.09),side,.32,.21,_coat,"bd9866")
			g.loft([Vector3(side*.125,.22,.03),Vector3(side*.125,.45,.07),Vector3(side*.125,.51,.07)],
				[Vector2(.045,.045),Vector2(.032,.035),Vector2(.025,.025)],"93703f")
			g.form(Vector3(side*.125,.51,.07),Vector3(.10,.09,.10),"4d382b")
			_eye(g,Vector3(side*.198,.10,-.09),side,.046)
			g.form(Vector3(side*.087,-.008,-.572),Vector3(.043,.032,.025),"483d30")
	elif species == "zebra":
		var base := Vector3(0,1.30,-.58)
		neck = _bone(torso,"ArchedNeck",base)
		g = ANATOMY.new("zebra_neck")
		g.loft([Vector3(0,-.05,.13),Vector3(0,.30,-.07),Vector3(0,.62,-.24),Vector3(0,.73,-.39)],
			[Vector2(.28,.31),Vector2(.22,.30),Vector2(.15,.22),Vector2(.11,.15)],_coat,base)
		g.loft([Vector3(0,.10,.36),Vector3(0,.48,.19),Vector3(0,.78,-.05),Vector3(0,.90,-.26)],
			[Vector2(.045,.06),Vector2(.045,.13),Vector2(.045,.14),Vector2(.018,.02)],"282724")
		g.flush(neck)
		head = _bone(neck,"Head",Vector3(0,.68,-.39))
		g = ANATOMY.new("zebra_head")
		g.loft([Vector3(0,.07,.11),Vector3(0,.03,-.04),Vector3(0,-.17,-.27),Vector3(0,-.30,-.48)],
			[Vector2(.10,.13),Vector2(.20,.24),Vector2(.145,.18),Vector2(.13,.12)],_coat,base+head.position)
		g.form(Vector3(0,-.28,-.47),Vector3(.31,.25,.22),"4d4943")
		for side in [-1.0,1.0]:
			_ear(g,Vector3(side*.13,.20,.015),side,.095,.38,_coat,"726657")
			_eye(g,Vector3(side*.19,.055,-.11),side,.041)
			g.form(Vector3(side*.09,-.24,-.56),Vector3(.047,.045,.025),"242421")
	elif species == "lion":
		head = _bone(torso,"Head",Vector3(0,1.10,-.89))
		g = ANATOMY.new("lion_head_"+str(int(phase)%2))
		if int(phase)%2 == 0:
			# One faceted mantle with broad ruff planes, not a ring of balls.
			g.loft([Vector3(0,.02,.37),Vector3(0,.02,.12),Vector3(0,-.01,-.14),Vector3(0,-.03,-.30)],
				[Vector2(.25,.32),Vector2(.47,.53),Vector2(.43,.51),Vector2(.29,.33)],"705034",Vector3.ZERO,12)
			g.loft([Vector3(0,-.15,.03),Vector3(0,-.37,-.06),Vector3(0,-.56,-.09)],
				[Vector2(.33,.18),Vector2(.23,.15),Vector2(.03,.03)],"58412e")
		g.form(Vector3(0,.02,-.21),Vector3(.58,.54,.57),_coat)
		g.form(Vector3(0,-.13,-.44),Vector3(.34,.24,.29),"dec8a2")
		for side in [-1.0,1.0]:
			_ear(g,Vector3(side*.25,.24,-.02),side,.13,.16,_coat,"634b35")
			g.form(Vector3(side*.105,-.06,-.49),Vector3(.23,.17,.17),"e2cfac")
			_eye(g,Vector3(side*.17,.093,-.417),side,.043)
			g.form(Vector3(side*.17,.153,-.385),Vector3(.15,.07,.105),"9d733f")
		g.form(Vector3(0,-.015,-.574),Vector3(.14,.095,.075),"40332c")
		g.form(Vector3(0,-.16,-.552),Vector3(.15,.026,.025),"67503b")
	else:
		head = _bone(torso,"Head",Vector3(0,.78,-.29))
		g = ANATOMY.new("monkey_head")
		g.form(Vector3(0,.025,0),Vector3(.39,.43,.40),_coat)
		g.form(Vector3(0,-.015,-.17),Vector3(.29,.31,.13),"bda484")
		g.form(Vector3(0,-.085,-.235),Vector3(.19,.12,.12),"8c7760")
		for side in [-1.0,1.0]:
			_ear(g,Vector3(side*.17,.01,0),side,.11,.14,_coat,"bc9f7c")
			_eye(g,Vector3(side*.068,.05,-.229),side,.029)
			g.form(Vector3(side*.034,-.061,-.296),Vector3(.021,.018,.018),"3e352b")
		g.form(Vector3(0,-.132,-.279),Vector3(.10,.018,.023),"4c3d31")
	g.flush(head)
func _ear(g, at: Vector3, side: float, width: float, height: float, color: String, inner: String) -> void:
	var tip := at+Vector3(side*width,height,-.015)
	g.loft([at,at.lerp(tip,.48),tip],[Vector2(.07,.045),Vector2(.095,.035),Vector2(.003,.006)],color)
	g.loft([at+Vector3(0,.035,-.043),at.lerp(tip,.50)+Vector3(0,0,-.035),tip+Vector3(0,-.025,-.01)],
		[Vector2(.025,.009),Vector2(.060,.01),Vector2(.002,.002)],inner)
func _eye(g, at: Vector3, side: float, radius: float) -> void:
	g.form(at,Vector3(radius*1.7,radius*1.6,radius),"302b22")
	g.form(at+Vector3(side*.005,.007,-radius*.40),Vector3(radius*.55,radius*.70,radius*.35),"c6a46a")
	g.form(at+Vector3(0,.006,-radius*.58),Vector3(radius*.27,radius*.51,radius*.16),"171b18")
func _build_tail() -> void:
	var base: Vector3 = {"giraffe":Vector3(0,2.06,.86),"zebra":Vector3(0,1.29,.72),"lion":Vector3(0,.96,.77),"monkey":Vector3(0,.51,.26)}[species]
	var parent := torso
	var count := 5 if species == "monkey" else 3
	var length := .21 if species == "monkey" else (.24 if species == "lion" else .25)
	for i in count:
		var bone := _bone(parent,"Tail%d"%i,base if i == 0 else Vector3(0,0,length))
		var g = ANATOMY.new(species+"_tail_"+str(i))
		var radius := (.043 if species == "monkey" else .038)*(1.0-float(i)/count*.50)
		g.loft([Vector3(0,0,-.025),Vector3(0,0,length*.55),Vector3(0,0,length+.018)],
			[Vector2(radius,radius),Vector2(radius*.83,radius*.83),Vector2(radius*.70,radius*.70)],_coat)
		if i == count-1 and species != "monkey":
			g.form(Vector3(0,0,length),Vector3(.12,.12,.25),"4d3d2d")
		g.flush(bone); tail.append(bone); parent = bone
		bone.rotation.x = -.20 if species == "monkey" else .35
func advance(delta: float) -> void:
	clock += maxf(delta,0.0)
	var duration := 17.0
	var walking_time := 10.0
	var t := clock+phase*1.7
	var cycle := floorf(t/duration)
	var within := fposmod(t,duration)
	var u := minf(within/walking_time,1.0)
	var eased := u-sin(TAU*u)/TAU
	var progress := phase+(2.2*cycle)+eased*2.2
	var next_position := home+Vector3(sin(progress)*1.18,0,cos(progress)*.68)
	var distance := position.distance_to(next_position) if _motion_initialized else 0.0
	var speed := distance/maxf(delta,.00001) if delta > 0 else 0.0
	moving = within < walking_time and speed > .002
	position = next_position
	if moving or not _motion_initialized: rotation.y = atan2(-cos(progress)*1.18,sin(progress)*.68)
	if moving: _gait += distance/maxf(_stride*scale.x,.01)*TAU
	var strength := clampf(speed/.20,0.0,1.0) if moving else 0.0
	for i in legs.size():
		var offset := (floori(float(i)/2.0) if species == "giraffe" else (i%2+floori(float(i)/2.0))) * PI
		var step := sin(_gait+offset)
		legs[i].rotation.x = step*.27*strength
		knees[i].rotation.x = maxf(0.0,-step)*.36*strength
	torso.position.y = absf(sin(_gait*2.0))*.018*strength
	var idle := 1.0-strength
	torso.scale.y = 1.0+sin(clock*.75+phase)*.004*idle
	head.rotation.x = sin(_gait)*.025*strength+sin(clock*.42+phase)*.016*idle
	head.rotation.y = sin(_gait*.45+phase)*.045*strength+sin(clock*.29+phase)*.035*idle
	for i in tail.size():
		tail[i].rotation.x = (-.24 if species == "monkey" else .34)+sin(_gait-i*.5)*.055*strength
		tail[i].rotation.y = sin(_gait*.65+phase-i*.6)*.13*strength+sin(clock*.65+phase-i*.5)*.025*idle
	_motion_initialized = true
