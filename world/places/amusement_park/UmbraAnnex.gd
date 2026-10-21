extends "res://world/places/amusement_park/ParkGeometry.gd"
## Full-height native solids: upper furniture must never become ground-floor walls.
const CREATURE := preload("res://world/places/amusement_park/UmbraCreature.gd")
var scares: Array[Dictionary] = []
var clock := 0.0
var pendulum: Node3D
static var _sound: AudioStreamWAV

func _ready() -> void:
	name = "UmbraNorthWing"
	direct_collisions = true
	_shell()
	_stairs(-6.0)
	_stairs(6.0)
	_dressing()
	_stations()
	flush()
	set_process(false)

func _shell() -> void:
	box("AnnexFloor",Vector3(0,-.11,-17.5),Vector3(18,.22,20),"302b2a",true,"floorboards")
	box("NorthWall",Vector3(0,3.55,-27.36),Vector3(18,7.1,.28),"303336",true,"crypt")
	for side in [-1,1]:
		box("WingWall",Vector3(side*8.86,3.55,-17.4),Vector3(.28,7.1,20),"343239",true,"wallpaper")
		for z in [-9.5,-14,-18.5,-23,-26.5]:
			box("WallColumn",Vector3(side*8.55,3.5,z),Vector3(.32,7,.35),"62564a",true,"wood")
			for y in [.32,3.75]: box("Wainscot",Vector3(side*8.64,y,z+1.5),Vector3(.10,.50,2.65),"443b33",false,"wood")
		for z in [-12,-21,-25]:
			box("WindowFrame",Vector3(side*8.66,5.4,z),Vector3(.12,2.0,1.5),"615b55",false,"wood")
			box("MoonGlass",Vector3(side*8.57,5.4,z),Vector3(.025,1.8,1.3),"263c51",false,"glow")
			for cross in [-.47,0,.47]: box("WindowMullion",Vector3(side*8.54,5.4,z+cross),Vector3(.06,1.85,.07),"292b30")
	box("WingCeiling",Vector3(0,7.15,-17.5),Vector3(18,.24,20),"191c23",true,"wood")
	# Upper gallery spans the back half; below it the crypt remains accessible.
	box("UpperGallery",Vector3(0,3.36,-22.7),Vector3(17.7,.28,9.4),"46382f",true,"floorboards")
	for x in [-4,4]: box("GalleryColumn",Vector3(x,1.65,-18.6),Vector3(.35,3.3,.38),"695847",true,"wood")
	for z in [-10,-15,-20,-25]: box("CeilingBeam",Vector3(0,6.9,z),Vector3(17.8,.30,.26),"514538")
	for y in [1.05,4.55]:
		if y>2: _rail(Vector3(-4.55,y,-17.95),Vector3(4.55,y,-17.95))
	# Closed wall above the original doorway seals exterior sunlight.
	box("SouthUpperWall",Vector3(0,5.2,-7.36),Vector3(18,3.9,.28),"343239",true,"wallpaper")
	for z in range(-27,-7):
		box("BoardSeam",Vector3(0,.006,z),Vector3(17.5,.008,.012),"181c21")
		if z < -18: box("GallerySeam",Vector3(0,3.506,z),Vector3(17.5,.008,.012),"211e23")
	lantern(Vector3(0,2.75,-8.2),"c79761",5.5,.85)
	lantern(Vector3(-6,4.75,-18.6),"9baebd",6.5,1.15)
	lantern(Vector3(6,4.75,-18.6),"bda07a",6.5,1.15)
	lantern(Vector3(0,5.9,-25.9),"ba8156",5.5,.85)
	lantern(Vector3(0,2.55,-23),"8797aa",5,.6)

func _stairs(x: float) -> void:
	# Each visible tread has its own supported step body, using Actor's existing
	# swept capsule step-up (17.5 cm), never tagging rails/furniture as walkable.
	for i in 20:
		var top := (i+1)*.175
		var at := Vector3(x,top*.5,-11.175-i*.35)
		box("Tread",at,Vector3(2.65,top,.35),"5d4a37",false,"wood")
		box("Nosing",Vector3(x,top+.006,at.z+.145),Vector3(2.65,.012,.045),"847257",false,"wood")
		var body := StaticBody3D.new()
		body.name = "StairTread%d_%d"%[int(x),i]
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = at
		body.set_meta("pedestrian_step",true)
		body.set_meta("pedestrian_step_top",top*.5)
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(2.65,top,.35)
		shape.shape = box_shape
		body.add_child(shape)
		add_child(body)
	for side in [-1,1]:
		var a := Vector3(x+side*1.38,1.10,-10.95)
		var b := Vector3(x+side*1.38,4.60,-18)
		beam(a,b,.10,.12,"9b805b","wood")
		# A solid sloping balustrade protects the entire stair run.
		var direction := (b-a).normalized()
		var right := Vector3.RIGHT
		box("StairGuard",(a+b)*.5-Vector3.UP*.52,Vector3(.10,1.16,a.distance_to(b)),"392f2e",true,"wood",Basis(right,direction.cross(right).normalized(),direction))
		for i in 21:
			var foot := Vector3(a.x,i*.175,-11-i*.35)
			beam(foot,foot+Vector3.UP*1.1,.05,.05,"8f7452","wood")
		box("Newel",Vector3(a.x,.58,-10.9),Vector3(.17,1.16,.17),"796143",true,"wood")
		ball(Vector3(a.x,1.20,-10.9),Vector3.ONE*.23,"ac8d59","metal")

func _rail(a: Vector3,b: Vector3) -> void:
	box("GalleryBalustrade",(a+b)*.5-Vector3.UP*.49,Vector3(absf(b.x-a.x),1.08,.12),"332f30",true,"wood")
	beam(a,b,.09,.1,"ab8c60","wood")
	for i in int(a.distance_to(b)/.38)+1:
		var p := a.lerp(b,float(i)/maxf(1,int(a.distance_to(b)/.38)))
		beam(p,p-Vector3.UP*.95,.045,.045,"876f50","wood")

func _dressing() -> void:
	# Banquet/crypt, fireplace, library and nursery arranged off the walking lines.
	box("BanquetTable",Vector3(0,.58,-15.7),Vector3(4.3,1.16,2.3),"40332b",true,"wood")
	box("TableCloth",Vector3(0,1.17,-15.7),Vector3(4.42,.04,2.36),"512c32",false,"velvet")
	for x in [-1.5,0,1.5]:
		cylinder(Vector3(x,1.21,-15.7),.27,.035,"9a8460","metal")
		for z in [-15.1,-16.4]:
			cylinder(Vector3(x,1.37,z),.045,.38,"b9a883")
			ball(Vector3(x,1.59,z),Vector3(.045,.10,.045),"d8a567","glow")
	box("Hearth",Vector3(0,4.15,-26.5),Vector3(3.2,1.3,1.1),"363339",true,"crypt")
	box("FireplaceMouth",Vector3(0,4.22,-25.937),Vector3(2.3,.9,.025),"101217")
	for x in [-1.42,1.42]: box("MantelPillar",Vector3(x,4.32,-25.85),Vector3(.22,1.65,.3),"716354",true,"stone")
	box("MantelShelf",Vector3(0,5.19,-26),Vector3(3.4,.18,1.30),"796953",true,"stone")
	for x in [-7.8,7.8]:
		box("Bookcase",Vector3(x,4.9,-25.4),Vector3(1.4,2.8,1.0),"44372e",true,"wood")
		for shelf in 4:
			box("Shelf",Vector3(x,3.8+shelf*.59,-24.84),Vector3(1.3,.08,.15),"8b7355")
			for book in 8:
				box("Book",Vector3(x-.55+book*.15,4.02+shelf*.59,-24.91),Vector3(.10,.30+(book%3)*.055,.21),["544a3b","4b3335","3d4846"][book%3],false,"cloth")
	box("NurseryCrib",Vector3(-3.1,3.95,-25.1),Vector3(1.9,.9,1.2),"57453f",true,"wood")
	for x in [-3.85,-3.55,-3.25,-2.95,-2.65,-2.35]: beam(Vector3(x,4.15,-24.45),Vector3(x,4.75,-24.45),.035,.035,"978473")
	box("CribTop",Vector3(-3.1,4.77,-24.45),Vector3(1.95,.06,.07),"978473")
	box("ClockCase",Vector3(3.35,4.8,-26.25),Vector3(.95,2.6,.75),"524130",true,"wood")
	ball(Vector3(3.35,5.48,-25.85),Vector3(.61,.61,.035),"a89c79")
	beam(Vector3(3.35,5.48,-25.82),Vector3(3.17,5.66,-25.82),.025,.025,"1c2027")
	beam(Vector3(3.35,5.48,-25.81),Vector3(3.52,5.53,-25.81),.025,.025,"1c2027")
	pendulum = Node3D.new()
	pendulum.position = Vector3(3.35,5.1,-25.82)
	add_child(pendulum)
	var g = preload("res://world/places/amusement_park/ParkGeometry.gd").new()
	pendulum.add_child(g)
	g.beam(Vector3.ZERO,Vector3(0,-.90,0),.025,.025,"aa905a","metal")
	g.ball(Vector3(0,-.92,0),Vector3(.24,.24,.045),"aa905a","metal")
	g.flush()
	for side in [-1,1]:
		box("CryptCoffin",Vector3(side*6,.5,-24.5),Vector3(1.6,1.0,2.8),"4a3935",true,"wood")
		for z in [-23.7,-25.3]: box("CoffinBand",Vector3(side*6,1.01,z),Vector3(1.65,.07,.14),"8b7650",false,"metal")
		# Frames and cracked faces on the stairwell wall.
		for z in [-10,-15,-20]:
			box("PortraitFrame",Vector3(side*8.48,2.0,z),Vector3(.18,1.5,1.05),"8a714d",false,"wood")
			box("PortraitCanvas",Vector3(side*8.37,2.0,z),Vector3(.035,1.23,.80),"292c32",false,"cloth")
			ball(Vector3(side*8.33,2.15,z),Vector3(.03,.47,.31),"847b67")
	# Cobweb fans and their cross-strands sit overhead, outside body clearance.
	for origin in [Vector3(-8.5,6.8,-26.9),Vector3(8.5,6.8,-26.9),Vector3(-8.5,6.8,-8)]:
		for i in 7:
			var end: Vector3 = origin+Vector3(-signf(origin.x)*(i*.25+.2),-.25-i*.10,1.4-i*.12)
			beam(origin,end,.009,.009,"747a79")
			if i>0:
				var prev: Vector3 = origin+Vector3(-signf(origin.x)*((i-1)*.25+.2),-.25-(i-1)*.10,1.4-(i-1)*.12)
				for f in [.35,.65,1.0]: beam(origin.lerp(prev,f),origin.lerp(end,f),.007,.007,"747a79")

func _stations() -> void:
	_station("BanquetWraith","wraith",Vector3(0,.35,-17.15),Vector3(0,0,-11),4.0)
	_station("CradleDoll","doll",Vector3(-3.1,4.4,-25.1),Vector3(-3.1,3.5,-23),2.4)
	_station("ClockKeeper","skeleton",Vector3(5.1,3.5,-26.4),Vector3(5.5,3.5,-23),2.6)
	_station("CryptWatcher","wraith",Vector3(0,0,-26.2),Vector3(0,0,-22.4),3.0)
	# Full display enclosures keep mechanical motion outside visitor routes.
	box("BanquetPlinth",Vector3(0,.45,-17.35),Vector3(1.5,.9,1.5),"33302f",true,"wood")
	box("KeeperPlinth",Vector3(5.1,3.9,-26.3),Vector3(1.5,.8,1.5),"33302f",true,"wood")
	box("CryptPlinth",Vector3(0,.45,-26.2),Vector3(1.7,.9,1.7),"33302f",true,"crypt")

func _station(id: String,type: String,at: Vector3,trigger: Vector3,radius: float) -> void:
	var creature := CREATURE.new()
	creature.name = id
	creature.kind = type
	creature.position = at
	add_child(creature)
	var sound := AudioStreamPlayer3D.new()
	sound.name = "MechanicalCreak"
	sound.stream = _creak()
	sound.position = at+Vector3.UP
	sound.volume_db = -17
	sound.max_distance = 13
	sound.unit_size = 2
	sound.pitch_scale = .72+scares.size()*.13
	add_child(sound)
	scares.append({"rig":creature,"trigger":trigger,"radius":radius,"time":-1.0,"cooldown":0.0,"armed":true,"count":0,"audio":sound})

func update_visitor(point: Vector3,delta: float) -> void:
	clock += maxf(delta,0)
	pendulum.rotation.z = sin(clock*1.8)*.17
	for station in scares:
		station.cooldown = maxf(0,station.cooldown-delta)
		var distance: float = point.distance_to(station.trigger)
		if distance>station.radius+1.5 and station.cooldown<=0: station.armed = true
		if station.armed and station.time<0 and distance<station.radius:
			station.armed = false
			station.time = 0.0
			station.cooldown = 12.0
			station.count += 1
			station.audio.play()
		var amount := 0.0
		if station.time>=0:
			station.time += delta
			var t: float = station.time
			if t<.24: amount = smoothstep(0,.24,t)
			elif t<1.15: amount = 1.0
			elif t<3.0: amount = 1.0-smoothstep(1.15,3.0,t)
			else: station.time = -1.0
		station.rig.animate(clock,amount,point)

static func _creak() -> AudioStreamWAV:
	if _sound!=null: return _sound
	var bytes := PackedByteArray()
	var rate := 22050
	bytes.resize(rate*2)
	for i in rate:
		var t := float(i)/rate
		var envelope := sin(PI*t)*exp(-t*2.5)
		var wave := sin(TAU*(83*t+16*t*t))* .45+sin(TAU*173*t+sin(t*31)*2)*.25+sin(TAU*947*t)*.05
		bytes.encode_s16(i*2,int(clampf(wave*envelope,-1,1)*20000))
	_sound = AudioStreamWAV.new()
	_sound.format = AudioStreamWAV.FORMAT_16_BITS
	_sound.mix_rate = rate
	_sound.data = bytes
	return _sound
