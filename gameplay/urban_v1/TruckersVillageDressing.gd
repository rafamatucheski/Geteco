extends RefCounted
static var _shade_wood: ArrayMesh
static var _shade_canopy: ArrayMesh
static var _wood_paint: StandardMaterial3D
static var _leaf_paint: StandardMaterial3D

static func dress_common_yard(v: Node3D) -> void:
	# The communal coffee table sits off the vehicle turning area, under shade.
	var at := Vector3(-4,0,-24)
	v._box(at+Vector3(0,.81,0),Vector3(3,.16,1.2),"796347")
	for x in [-1.12,1.12]: v._box(at+Vector3(x,.4,0),Vector3(.15,.8,1.0),"5b5845")
	v._solid("YardTable",at+Vector3(0,.46,0),Vector3(3,.92,1.2))
	for z in [-1.4,1.4]: v._bench(at+Vector3(0,0,z))
	v._cylinder(at+Vector3(.3,1.03,0),.13,.32,"464c40")
	for x in [-.5,-.15]: v._cylinder(at+Vector3(x,.94,.2),.055,.1,"c1b58e")
	# A detached generator, oil drums and tool cart belong beside the workshop.
	at=Vector3(73,0,2)
	v._box(at+Vector3(0,.55,0),Vector3(1.4,1.1,.85),"696f53")
	v._box(at+Vector3(0,.64,.45),Vector3(1.08,.55,.025),"333c34")
	for x in [-.45,-.15,.15,.45]: v._box(at+Vector3(x,.64,.48),Vector3(.05,.53,.04),"8a8368")
	v._solid("WorkshopGenerator",at+Vector3(0,.55,0),Vector3(1.4,1.1,1.0))
	_barrel(v,Vector3(73,0,5),true)
	_barrel(v,Vector3(75,0,5),false)
	# Low, broken stones define yard edges without becoming invisible walls.
	for i in 12:
		v._box(Vector3(-14+i*2.2,.05,-28+sin(i*.8)*.5),Vector3(.42,.1,.31),"77715b",Vector3(0,i*.7,0))

static func pedestrian_entry(v: Node3D) -> void:
	# Visible timber barriers leave human-width openings, not a vehicle lane.
	for x in [39.0,40.8,42.6,44.4,46.2,48.0,49.8]:
		v._cylinder(Vector3(x,.7,-46),.2,1.4,"77674a")
		v._solid("PedestrianBollard",Vector3(x,.7,-46),Vector3(.4,1.4,.4))
	for side in [-1.0,1.0]:
		var x: float = 44.4+side*10
		for z in [-50.0,-45.0]:
			v._box(Vector3(x,.8,z),Vector3(.18,1.6,.18),"6e5d42")
		for y in [.5,1.05]: v._box(Vector3(x,y,-47.5),Vector3(.13,.12,5),"877352")
		v._solid("EntryFence",Vector3(x,.75,-47.5),Vector3(.2,1.5,5))

static func shop_counter(v: Node3D) -> void:
	# Open serving counter under the canopy, reached without entering a facade.
	var at := Vector3(-34,0,-24)
	v._box(at+Vector3(0,.48,-.6),Vector3(3.5,.96,.64),"796141")
	v._box(at+Vector3(0,1.01,-.6),Vector3(3.7,.14,.82),"a5936a")
	v._solid("TonicoCounter",at+Vector3(0,.55,-.6),Vector3(3.7,1.1,.82))
	v._box(at+Vector3(1,1.25,-.6),Vector3(.65,.4,.45),"615e4c")
	v._box(at+Vector3(1,1.47,-.55),Vector3(.38,.08,.24),"363c35",Vector3(.15,0,0))
	for x in [-1.2,-.85,-.5]:
		v._cylinder(at+Vector3(x,1.25,-.6),.075,.33,"586b3e")
		v._cylinder(at+Vector3(x,1.44,-.6),.036,.10,"687847")
		v._cylinder(at+Vector3(x,1.25,-.6),.079,.10,"c0b07e")

static func _shade_tree(v: Node3D,at: Vector3) -> void:
	if _shade_wood==null:
		_shade_wood=preload("res://gameplay/urban_v1/FreightOutskirts.gd")._wood_mesh()
		_shade_canopy=preload("res://gameplay/urban_v1/FreightOutskirts.gd")._canopy_mesh(1)
		_wood_paint=StandardMaterial3D.new()
		_wood_paint.albedo_color=Color("65503b")
		_wood_paint.vertex_color_use_as_albedo=true
		_leaf_paint=StandardMaterial3D.new()
		_leaf_paint.albedo_color=Color("526d43")
		_leaf_paint.vertex_color_use_as_albedo=true
	for entry in [[_shade_wood,_wood_paint,Vector3.ZERO,Vector3(8,9,8)],[_shade_canopy,_leaf_paint,Vector3(0,6.3,0),Vector3(7,4.86,6.58)]]:
		var mesh := MeshInstance3D.new()
		mesh.name="VillageShadeTree"
		mesh.mesh=entry[0]
		mesh.material_override=entry[1]
		mesh.position=at+entry[2]
		mesh.scale=entry[3]
		v.add_child(mesh)
	v._solid("YardTree",at+Vector3(0,3.015,0),Vector3(.64,6.03,.64))
## Household detail, authored in each home's local frame. Closed walls,
## furniture and yard boundaries use the same transform for visual and physics.
static func dress_home(v: Node3D,index: int) -> void:
	_fence(v,index)
	_facade(v,index)
	_clothesline(v,index)
	if index in [0,3,5]: _water_tank(v,Vector3(7.7,0,-3.2))
	if index in [1,2,4]: _vegetable_bed(v,Vector3(-7.8,0,-4.3))
	if index in [0,2,5]: _woodpile(v,Vector3(-7.8,0,-1.0))
	else: _workbench(v,Vector3(7.7,0,-1.3))
	_barrel(v,Vector3(-5.3,0,-5.8),index%2==0)
	_pot(v,Vector3(5.4,0,5.0),index)
	_pot(v,Vector3(6.1,0,5.8),index+1)
	# Small repairs tell individual stories without text on the homes.
	if index%2 == 0:
		v._box(Vector3(-3.6,1.85,4.77),Vector3(1.65,.13,.075),"7d674d",Vector3(0,0,.17))
	if index in [1,4]:
		v._box(Vector3(4.3,3.62,-1.5),Vector3(2.8,.07,2.5),"635e4c",Vector3(0,0,-.19),true)
	if index in [0,3]:
		v._box(Vector3(4.5,4.08,-2.4),Vector3(.65,1.35,.65),"8e6450",Vector3.ZERO,true)
		v._box(Vector3(4.5,4.78,-2.4),Vector3(.78,.12,.78),"635e4c",Vector3.ZERO,true)
	else:
		v._box(Vector3(-3.8,4.35,-2.2),Vector3(.055,2,.055),"595b4b",Vector3.ZERO,true)
		for y in [4.5,4.8,5.1]: v._box(Vector3(-3.8,y,-2.2),Vector3(1.4,.035,.035),"797d6d",Vector3.ZERO,true)

static func _fence(v: Node3D,index: int) -> void:
	# Rear has a broad opening; every yard is reachable without squeezing.
	var rear := -8.9 if index%2==0 else -9.5
	for x in [-9.5,9.5]:
		_fence_panel(v,Vector3(x,0,(rear+2.0)*.5),Vector3(.13,1.2,2.0-rear))
	for x in [-5.6,5.6]: _fence_panel(v,Vector3(x,0,rear),Vector3(7.8,1.2,.13))
	# The frontage is intentionally open toward the common yard.
	for x in [-9.5,9.5]:
		v._box(Vector3(x,.7,3.0),Vector3(.16,1.4,.16),"73624a")
		v._solid("YardGatePost",Vector3(x,.7,3.0),Vector3(.16,1.4,.16))

static func _fence_panel(v: Node3D,at: Vector3,size: Vector3) -> void:
	var along_x := size.x>size.z
	var length: float = maxf(size.x,size.z)
	var count := ceili(length/1.55)
	for i in count+1:
		var offset := -length*.5+length*float(i)/float(count)
		var p := at+Vector3(offset if along_x else 0,.63,0 if along_x else offset)
		v._box(p,Vector3(.12,1.26,.12),"786c50")
	for y in [.36,.89]:
		v._box(at+Vector3(0,y,0),Vector3(size.x,.12,size.z),"817456")
	v._solid("YardFence",at+Vector3(0,.65,0),Vector3(size.x,1.3,size.z))

static func _facade(v: Node3D,index: int) -> void:
	# Rain gutters, drainpipe, weathered foundation and several exposed bricks.
	v._box(Vector3(6.48,2.92,0),Vector3(.15,.13,9.5),"635e4c")
	v._box(Vector3(6.54,1.52,-4.23),Vector3(.09,2.9,.09),"797d6d")
	for row in 3:
		for col in 4:
			var x := -5.8+col*.43+(row%2)*.18
			v._box(Vector3(x,.29+row*.19,4.59),Vector3(.38,.14,.035),"8e6450")
	for z in [-3.5,-2.7,-1.9]:
		v._box(Vector3(-6.54,.24,z),Vector3(.04,.33,.56),"8e6450")
	# A shallow crate keeps the porch occupied while its centre remains clear.
	if index in [1,3,5]:
		v._box(Vector3(3.0,.23,5.9),Vector3(.9,.46,.65),"8b7556")
		for x in [2.66,3.0,3.34]: v._box(Vector3(x,.47,5.9),Vector3(.12,.04,.65),"73624a")
		v._solid("PorchCrate",Vector3(3.0,.25,5.9),Vector3(.9,.5,.65))

static func _clothesline(v: Node3D,index: int) -> void:
	var at := Vector3(0,0,-7.0)
	for x in [-4.3,4.3]:
		v._box(at+Vector3(x,1.35,0),Vector3(.12,2.7,.12),"73624a")
		v._solid("ClotheslinePole",at+Vector3(x,1.35,0),Vector3(.12,2.7,.12))
	for z in [-.3,.3]:
		v._box(at+Vector3(0,2.55,z),Vector3(8.6,.022,.022),"a49673")
	var colors := ["929e94","ac8d72","b4aa87","a49673"]
	for i in 4:
		var x := -2.8+i*1.6
		# Flexible laundry hangs above walking headroom. Only the poles are solid.
		v._box(at+Vector3(x,2.21,.30),Vector3(.84,.64,.035),colors[(i+index)%4],Vector3(0,.08*(i-1),0))
		for pin in [-.26,.26]: v._box(at+Vector3(x+pin,2.57,.30),Vector3(.035,.09,.025),"8b7556")

static func _water_tank(v: Node3D,at: Vector3) -> void:
	for x in [-.48,.48]:
		for z in [-.48,.48]: v._box(at+Vector3(x,.7,z),Vector3(.16,1.4,.16),"8e6450")
	v._box(at+Vector3(0,1.44,0),Vector3(1.42,.18,1.42),"797d6d")
	v._cylinder(at+Vector3(0,2.08,0),.66,1.1,"54665e")
	for y in [1.68,2.1,2.58]: v._cylinder(at+Vector3(0,y,0),.68,.045,"797d6d")
	v._cylinder(at+Vector3(0,2.67,0),.69,.08,"465455")
	v._box(at+Vector3(.7,.9,0),Vector3(.055,1.8,.055),"797d6d")
	v._solid("WaterTankStand",at+Vector3(0,1.38,0),Vector3(1.5,2.76,1.5))

static func _vegetable_bed(v: Node3D,at: Vector3) -> void:
	v._box(at+Vector3(0,.13,0),Vector3(1.5,.26,3.2),"635e4c")
	for x in [-.75,.75]: v._box(at+Vector3(x,.24,0),Vector3(.08,.25,3.3),"8b7556")
	for z in [-1.6,1.6]: v._box(at+Vector3(0,.24,z),Vector3(1.55,.25,.08),"8b7556")
	for x in [-.37,.37]:
		for z in [-1.1,-.35,.35,1.1]:
			v._box(at+Vector3(x,.45,z),Vector3(.1,.4,.1),"54665e")
			v._box(at+Vector3(x,.46,z),Vector3(.42,.09,.21),"54665e",Vector3(0,0,.28))
	v._solid("RaisedVegetableBed",at+Vector3(0,.34,0),Vector3(1.6,.68,3.3))

static func _woodpile(v: Node3D,at: Vector3) -> void:
	for row in 3:
		for z in [-.72,-.24,.24,.72]:
			v._cylinder(at+Vector3(0,.18+row*.30,z),.17,1.35,"73624a",Vector3(0,0,PI*.5))
	v._box(at+Vector3(0,1.02,0),Vector3(1.7,.09,2.0),"635e4c",Vector3(0,0,.08))
	v._solid("CoveredFirewood",at+Vector3(0,.57,0),Vector3(1.75,1.14,2.0))

static func _workbench(v: Node3D,at: Vector3) -> void:
	v._box(at+Vector3(0,.83,0),Vector3(1.3,.13,2.3),"8b7556")
	for x in [-.5,.5]:
		for z in [-.9,.9]: v._box(at+Vector3(x,.4,z),Vector3(.12,.8,.12),"635e4c")
	v._box(at+Vector3(.16,1.02,.46),Vector3(.6,.23,.65),"795b48")
	for z in [-.8,-.5]: v._box(at+Vector3(0,.92,z),Vector3(.75,.055,.10),"797d6d",Vector3(0,.2,0))
	v._solid("BackyardWorkbench",at+Vector3(0,.57,0),Vector3(1.3,1.14,2.3))

static func _barrel(v: Node3D,at: Vector3,rust: bool) -> void:
	v._cylinder(at+Vector3(0,.52,0),.36,1.04,"795b48" if rust else "54665e")
	for y in [.12,.85]: v._cylinder(at+Vector3(0,y,0),.375,.055,"635e4c")
	v._solid("RainBarrel",at+Vector3(0,.53,0),Vector3(.76,1.06,.76))

static func _pot(v: Node3D,at: Vector3,index: int) -> void:
	v._cylinder(at+Vector3(0,.23,0),.28,.46,"8e6450")
	v._cylinder(at+Vector3(0,.46,0),.30,.07,"ac8d72")
	for i in 4:
		var angle := i*PI*.5+index*.2
		v._box(at+Vector3(sin(angle)*.12,.7,cos(angle)*.12),Vector3(.13,.46,.22),"54665e",Vector3(.25,angle,.12))
	v._solid("PorchPlantPot",at+Vector3(0,.42,0),Vector3(.65,.84,.65))
