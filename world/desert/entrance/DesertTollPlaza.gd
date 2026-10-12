extends Node3D
## A closed exterior booth. Static details are batched; only moving arms tick.
const BATCH := preload("res://world/mining/MiningBatch.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
const POSITION := Vector3(342.5,0,-474)
const GROUP := &"desert_toll_plaza"
const RESERVATION := Rect2(330,-494,25,40)
var arms: Array[AnimatableBody3D]=[]
var targets: Array[float]=[0.0,0.0]

func _ready() -> void:
	name="DesertTollPlaza"
	position=POSITION
	add_to_group(GROUP)
	var art:=BATCH.new(self,"TollArchitecture")
	# A narrow protected island leaves 4.2m of clear road on each side.
	art.box("Island",Vector3(0,.11,0),Vector3(1.4,.22,12),"concrete",true)
	art.box("BoothBase",Vector3(0,.65,0),Vector3(1.3,1.1,3.4),"cream",true)
	art.box("Booth",Vector3(0,1.8,0),Vector3(1.22,1.3,3.25),"glass",true)
	for x in [-.66,.66]:
		for z in [-1.7,1.7]: art.box("BoothFrame",Vector3(x,1.38,z),Vector3(.08,2.6,.08),"steel")
		art.box("WindowRail",Vector3(x,1.25,0),Vector3(.08,.09,3.45),"steel")
		art.box("Counter",Vector3(x*1.14,1.19,.2),Vector3(.22,.10,1.6),"steel")
	art.box("BoothRoof",Vector3(0,2.78,0),Vector3(1.85,.2,4),"blue")
	for x in [-6,6]:
		for z in [-2.5,2.5]:
			art.box("Footing",Vector3(x,.22,z),Vector3(.85,.44,.85),"concrete",true)
			art.box("CanopyColumn",Vector3(x,2.75,z),Vector3(.24,5.5,.24),"steel",true)
			art.box("Reflector",Vector3(x,.9,z+.15),Vector3(.18,.28,.025),"yellow")
	# Thin, raised canopy; the vehicle clears beneath it even in a coach.
	art.box("Canopy",Vector3(0,5.65,0),Vector3(13.2,.24,6.4),"blue",true)
	for z in [-3.25,3.25]:
		art.box("CanopyFascia",Vector3(0,5.46,z),Vector3(13.4,.46,.16),"cream")
		art.box("FasciaTrim",Vector3(0,5.23,z),Vector3(13.4,.08,.20),"steel")
	for x in [-3.8,0,3.8]: art.box("RoofSeam",Vector3(x,5.80,0),Vector3(.05,.04,6.3),"steel")
	for z in [-5.45,5.45]:
		art.cylinder("IslandBollard",Vector3(0,.7,z),.16,1.15,"yellow",true)
		art.box("BollardBand",Vector3(0,.83,z+.17),Vector3(.23,.2,.025),"rubber")
	for side in [-1,1]:
		var x:=float(side)*2.8
		var z:=float(side)*6.7
		art.box("StopLine",Vector3(x,.032,z),Vector3(3.8,.018,.3),"white")
		art.box("DirectionShaft",Vector3(x,.032,z+side*5),Vector3(.2,.018,2.0),"white")
		for wing in [-1,1]:
			art.box("DirectionChevron",Vector3(x+wing*.30,.032,z+side*4.35),Vector3(.16,.018,.95),"white",false,Vector3(0,wing*side*-.7,0))
	# Sparse approach chevrons and side rails lead into the lanes without widening.
	for z in [-18.0,-14.0,14.0,18.0]:
		for x in [-6.5,6.5]:
			art.box("GuidePost",Vector3(x,.65,z),Vector3(.14,1.3,.14),"white",true)
			art.box("GuideBand",Vector3(x,.89,z+.08),Vector3(.15,.22,.018),"rubber")
	art.finish()
	for lane in 2: _arm(lane)
	set_physics_process(false)

func _arm(lane: int) -> void:
	var side:=1.0 if lane==0 else -1.0
	var hinge:=AnimatableBody3D.new()
	hinge.name="EntryBarrier" if lane==0 else "ReturnBarrier"
	hinge.position=Vector3(side*.84,1.05,side*-4.3)
	hinge.collision_layer=1
	hinge.collision_mask=0
	add_child(hinge)
	G.box(self,"BarrierMachine",hinge.position-Vector3(0,.47,0),Vector3(.38,1.1,.5),Color("be9849"),true)
	G.box(hinge,"Arm",Vector3(side*1.97,0,0),Vector3(3.94,.14,.16),Color("e2dcc9"))
	for i in 6:
		G.box(hinge,"WarningBand",Vector3(side*(.28+float(i)*.64),0,.085),Vector3(.26,.15,.015),Color("a94532"))
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(3.94,.14,.16)
	shape.shape=box
	shape.position.x=side*1.97
	hinge.add_child(shape)
	arms.append(hinge)

func set_open(lane: int, opened: bool) -> void:
	var angle:=deg_to_rad(88)*(1 if lane==0 else -1) if opened else 0.0
	if is_equal_approx(targets[lane],angle): return
	targets[lane]=angle
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	var moving:=false
	for i in arms.size():
		arms[i].rotation.z=move_toward(arms[i].rotation.z,targets[i],delta*1.25)
		moving=moving or not is_equal_approx(arms[i].rotation.z,targets[i])
	set_physics_process(moving)
