extends RefCounted
## Sparse colonies, with world-cell ownership so streaming never moves a plant.
const G := preload("res://world/desert/expansion/DesertEcologyGeometry.gd")
const FLORA := preload("res://assets/urban_detail/FloraSurfaces.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const CANYON := preload("res://world/desert/DesertTerrainRelief.gd")
const CELL := 54.0
const ANIMAL_PATCHES := [Vector2(-440,-420),Vector2(-930,-560),Vector2(-1000,-690),Vector2(-290,-850),Vector2(100,-600),Vector2(-410,-420),Vector2(-300,-450),Vector2(10,-870)]
const WIND_PATCHES := [Vector2(-815,-600),Vector2(-840,-450),Vector2(80,-450)]
static var _buildings: Array[Rect2]=[]

static func build_chunk(parent: Node3D,rect: Rect2,world_seed: int,height_callable: Callable,clearance_callable := Callable()) -> int:
	if not height_callable.is_valid(): return 0
	var data := G.buffer()
	var body := StaticBody3D.new()
	body.name="DesertEcologyTreeSolids"
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("vehicle_surface","hard")
	var count := 0
	var species: Dictionary={}
	var positions := PackedVector3Array()
	for item in placements(rect,world_seed,clearance_callable):
		var p: Vector2=item.point
		var y := float(height_callable.call(p))
		# Footprint samples reject steep support, rather than burying an entire plant.
		var supported := true
		for offset in [Vector2(.65,0),Vector2(-.65,0),Vector2(0,.65),Vector2(0,-.65)]:
			if absf(float(height_callable.call(p+offset))-y)>.22: supported=false
		if not supported: continue
		var at := Vector3(p.x,y-.035,p.y)
		var pose := Transform3D(Basis(Vector3.UP,float(item.yaw)).scaled(Vector3.ONE*float(item.scale)),at)
		match int(item.kind):
			0: _barrel(data,pose)
			1: _prickly(data,pose)
			2: _agave(data,pose)
			3:
				var tree_data := G.buffer()
				var tree_body := StaticBody3D.new()
				tree_body.collision_layer=1
				tree_body.collision_mask=0
				_tree(tree_data,tree_body,Transform3D(pose.basis,Vector3.ZERO))
				var tree := MeshInstance3D.new()
				tree.name="DesertBreakableTree"
				tree.mesh=G.mesh(tree_data)
				tree.material_override=FLORA.bark()
				tree.position=at
				tree.add_child(tree_body)
				parent.add_child(tree)
				preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("desert_tree",tree,parent)
			_: _creosote(data,pose)
		var label: String=["barrel_cactus","prickly_pear","agave","dead_tree","creosote"][int(item.kind)]
		species[label]=int(species.get(label,0))+1
		positions.append(at)
		count+=1
	if count==0:
		body.free()
		return 0
	var node := MeshInstance3D.new()
	node.name="DesertEcologyFloraBatch"
	node.mesh=G.mesh(data)
	node.material_override=FLORA.cactus()
	node.set_meta("flora_species",species)
	node.set_meta("flora_positions",positions)
	parent.add_child(node)
	if body.get_child_count()>0: parent.add_child(body)
	else: body.free()
	return count

static func placements(rect: Rect2,world_seed: int,clearance_callable := Callable()) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var area := rect.intersection(LAYOUT.BOUNDS.grow(-40))
	if not area.has_area(): return result
	for x in range(floori(area.position.x/CELL)-1,ceili(area.end.x/CELL)+1):
		for z in range(floori(area.position.y/CELL)-1,ceili(area.end.y/CELL)+1):
			var rng := RandomNumberGenerator.new()
			rng.seed=absi(world_seed+x*9157+z*6679+28031)
			if rng.randf()>.43: continue
			var center := Vector2((float(x)+rng.randf_range(.25,.75))*CELL,(float(z)+rng.randf_range(.25,.75))*CELL)
			var family := rng.randi_range(0,3)
			for member in rng.randi_range(3,6):
				var p := center+Vector2(rng.randf_range(-5.5,5.5),rng.randf_range(-4.5,4.5))
				var kind := family if member<2 else rng.randi_range(0,4)
				if kind==3 and member>0: kind=4
				var scale := rng.randf_range(.75,1.20)
				var yaw := rng.randf_range(0,TAU)
				var radius := (2.0 if kind==3 else .9)*scale
				if not rect.has_point(p) or not clear(p,radius): continue
				if clearance_callable.is_valid() and not bool(clearance_callable.call(p,radius)): continue
				result.append({"point":p,"kind":kind,"scale":scale,"yaw":yaw})
	return result

static func clear(p: Vector2,radius: float) -> bool:
	if not LAYOUT.BOUNDS.grow(-40.0-radius).has_point(p): return false
	if CANYON.BOUNDS.grow(18.0+radius).has_point(p): return false
	if not LAYOUT.road_clear(p,radius+2.0): return false
	if Rect2(205,-542,135,102).grow(radius).has_point(p): return false
	if Rect2(-1050,-780,1060,60).grow(radius).has_point(p): return false
	if Rect2(-1275,-515,1030,140).grow(radius).has_point(p): return false
	for reserve in [Vector3(-1260,65,-1080),Vector3(-30,105,-448),Vector3(149,125,-1090),Vector3(150,100,-680),Vector3(-650,55,-690)]:
		if p.distance_to(Vector2(reserve.x,reserve.z))<reserve.y+radius: return false
	for territory: Vector2 in ANIMAL_PATCHES:
		if territory.distance_to(p)<9.0+radius: return false
	for territory: Vector2 in WIND_PATCHES:
		if territory.distance_to(p)<18.0+radius: return false
	if _buildings.is_empty():
		for building in LAYOUT.buildings():
			var at: Vector3=building.position
			var size: Vector3=building.size
			_buildings.append(Rect2(Vector2(at.x,at.z)-Vector2(size.x,size.z)*.5,Vector2(size.x,size.z)))
	for footprint in _buildings:
		if footprint.grow(radius+7.0).has_point(p): return false
	return true

static func _barrel(data: Dictionary,pose: Transform3D) -> void:
	var green := Color("6c7350")
	G.ellipsoid(data,pose.translated_local(Vector3(0,.32,0)),Vector3(.29,.35,.29),green,16,7,true)
	for i in 9:
		var angle := float(i)*TAU/9.0
		var at := Vector3(cos(angle)*.12,.642,sin(angle)*.12)
		G.branch(data,pose*at,pose*(at+Vector3(cos(angle)*.025,.036,sin(angle)*.025)),.016,.007,Color("b8a06a"),4)
	for side in 8:
		var angle := float(side)*TAU/8.0
		for h in 3:
			var at := Vector3(cos(angle)*.278,.20+float(h)*.14,sin(angle)*.278)
			var tip := at+Vector3(cos(angle)*.035,.022,sin(angle)*.035)
			G.branch(data,pose*at,pose*tip,.006,.001,Color("cbb384"),3)

static func _prickly(data: Dictionary,pose: Transform3D) -> void:
	var green := Color("647357")
	var pads := [Vector3(0,.29,0),Vector3(-.22,.60,.012),Vector3(.24,.70,-.025),Vector3(.37,1.00,0),Vector3(-.36,.84,-.018)]
	for i in pads.size():
		var tilt := -.20 if i%2==0 else .25
		var pad := Transform3D(pose.basis*Basis(Vector3.FORWARD,tilt),pose*pads[i])
		G.ellipsoid(data,pad,Vector3(.19,.28,.054) if i<3 else Vector3(.145,.205,.045),green.lightened(float(i%3)*.035),8,5)
		for mark in 4:
			var at := Vector3(-.07+float(mark%2)*.14,-.08+float(floori(float(mark)/2.0))*.15,.052)
			G.branch(data,pad*at,pad*(at+Vector3(.01,.014,.012)),.011,.003,Color("c2b280"),3)
	G.ellipsoid(data,pose.translated_local(Vector3(.40,1.195,0)),Vector3(.045,.055,.041),Color("94624c"),6,3)

static func _agave(data: Dictionary,pose: Transform3D) -> void:
	for i in 13:
		var angle := float(i)*2.399963
		var radius := .63 if i<8 else .40
		var radial := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-sin(angle),0,cos(angle))
		var middle := radial*radius*.62+Vector3.UP*(.20 if i<8 else .34)
		var tip := radial*radius+Vector3.UP*(.36 if i<8 else .67)
		var color := Color("747d65") if i%3 else Color("9a9d7a")
		G.leaf(data,pose*Vector3(0,.04,0),pose*(middle+side*.064),pose*tip,color)
		G.leaf(data,pose*Vector3(0,.04,0),pose*tip,pose*(middle-side*.064),color.darkened(.12))

static func _tree(data: Dictionary,body: StaticBody3D,pose: Transform3D) -> void:
	var wood := Color("817b68")
	var points := [Vector3(0,-.02,0),Vector3(.12,.82,.06),Vector3(-.10,1.53,.13),Vector3(.08,2.25,.10),Vector3(-.05,2.85,.20)]
	for i in 4:
		var prism := G.branch(data,pose*points[i],pose*points[i+1],.13-float(i)*.023,.105-float(i)*.023,wood,6)
		G.solid(body,prism)
	for branch in [Vector3(-1.15,2.15,.23),Vector3(.90,2.35,-.37),Vector3(.32,2.10,1.03)]:
		var start: Vector3=points[2]
		var elbow := start.lerp(branch,.62)+Vector3(0,-.14,0)
		var prism := G.branch(data,pose*start,pose*elbow,.065,.039,wood,5)
		G.solid(body,prism)
		G.branch(data,pose*elbow,pose*branch,.040,.008,wood.lightened(.04),5)
		G.branch(data,pose*elbow,pose*(branch+Vector3(.16,.42,-.18)),.022,.004,wood,4)

static func _creosote(data: Dictionary,pose: Transform3D) -> void:
	for i in 6:
		var angle := float(i)*2.399963
		var radial := Vector3(cos(angle),0,sin(angle))
		var fork := radial*.26+Vector3.UP*.34
		var tip := radial*.51+Vector3.UP*(.50+float(i%3)*.07)
		G.branch(data,pose*Vector3(0,-.015,0),pose*fork,.021,.010,Color("897858"),4)
		G.branch(data,pose*fork,pose*tip,.011,.003,Color("948262"),3)
		G.ellipsoid(data,pose.translated_local(tip),Vector3(.14,.055,.105),Color("8c8b61") if i%2 else Color("787d51"),5,3)
