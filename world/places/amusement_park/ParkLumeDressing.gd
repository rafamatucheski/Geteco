extends RefCounted
## Static dressing is appended to the park's material batches and solid inventory.
const VENDING := preload("res://activities/amusement_park/AmusementParkVending.gd")
const TABLES := [Vector3(-18,0,26),Vector3(-9,0,26),Vector3(6,0,24),Vector3(16,0,31),Vector3(11,0,6)]
const STALLS := [Vector3(-21,0,32),Vector3(-12,0,32),Vector3(3,0,-25),Vector3(3,0,3)]
const COLORS := ["873e4a","38625f","d1ab59","63769a"]

static func build(g: Node3D) -> void:
	for i in STALLS.size(): _stall(g,STALLS[i],i)
	for i in TABLES.size(): _table(g,TABLES[i],i)
	for point in [Vector3(-3,0,25),Vector3(20,0,25),Vector3(37.5,0,29),Vector3(6,0,32),Vector3(33,0,-8),Vector3(36,0,3)]:
		g.box("LumeFlowerBed",point+Vector3.UP*.31,Vector3(1.8,.62,1.1),"b59368",true,"stone")
		g.ball(point+Vector3.UP*.74,Vector3(1.65,.62,.98),"506f56")
		for x in [-.52,0,.52]:
			g.ball(point+Vector3(x,1.00,.10),Vector3(.24,.19,.24),"d1ab59")
	for point in [Vector3(38,0,10),Vector3(-4,0,21),Vector3(29,0,33)]:
		g.box("LumeBin",point+Vector3.UP*.48,Vector3(.64,.96,.64),"38625f",true,"metal")
		g.box("BinLid",point+Vector3.UP*.99,Vector3(.71,.10,.71),"d1ab59")
		g.box("BinOpening",point+Vector3(0,.85,.328),Vector3(.39,.17,.014),"272d35")
	_cart(g,Vector3(30,0,4),false)
	_cart(g,Vector3(-1,0,-3),true)
	for point in [Vector3(-2,0,7),Vector3(30,0,10),Vector3(22,0,34)]: _balloons(g,point)
	# Flag supports stay outside the 6 m promenade; strings remain overhead.
	for x in [0,15,35]:
		for z in [10.8,19.4]:
			g.box("BuntingPole",Vector3(x,1.85,z),Vector3(.11,3.7,.11),"d1ab59",true,"metal")
		_bunting(g,Vector3(x,3.65,10.8),Vector3(x,3.65,19.4))
	for id: String in VENDING.MACHINES: _vending(g,id)

static func _stall(g: Node3D, at: Vector3, index: int) -> void:
	var color: String = COLORS[index]
	# All furniture, including the projecting counter, has its full solid volume.
	g.box("LumeStallBody",at+Vector3(0,.72,0),Vector3(4.8,1.44,2.5),color,true,"wood")
	g.box("LumeStallBack",at+Vector3(0,1.95,-1.13),Vector3(4.8,1.1,.24),"e1cfa4",true,"wood")
	g.box("LumeStallCounter",at+Vector3(0,1.20,1.25),Vector3(5.1,.16,.7),"ae8856",true,"wood")
	for x in [-2.28,2.28]: g.box("LumeStallPost",at+Vector3(x,1.48,1.04),Vector3(.15,2.96,.15),"e1cfa4",true,"wood")
	g.box("LumeStallRoof",at+Vector3(0,2.91,0),Vector3(5.35,.18,3.10),color,true)
	for x in [-2.1,-1.05,0,1.05,2.1]: g.box("AwningStripe",at+Vector3(x,3.015,0),Vector3(.40,.03,3.05),"e1cfa4")
	for x in [-1.7,-.85,0,.85,1.7]:
		if index in [0,1]:
			g.cylinder(at+Vector3(x,1.63,.38),.19,.35,"d1ab59")
			g.ball(at+Vector3(x,1.86,.38),Vector3(.37,.20,.37),"e1cfa4")
		else:
			g.cylinder(at+Vector3(x,1.70,-.80),.11,.50,"63769a" if index == 2 else "d1ab59")
			g.ball(at+Vector3(x,2.14,-.91),Vector3(.34,.34,.12),"873e4a")
	if index >= 2:
		for x in [-1.5,0,1.5]:
			g.ball(at+Vector3(x,1.42,1.3),Vector3(.23,.23,.23),"e1cfa4")
	else:
		for x in [-1.5,0,1.5]: g.box("StallPack",at+Vector3(x,1.35,1.3),Vector3(.31,.13,.28),"63769a")

static func _table(g: Node3D, at: Vector3, index: int) -> void:
	g.cylinder(at+Vector3.UP*.78,.82,.12,"ae8856","wood")
	g.collision_box("LumeTable",at+Vector3.UP*.43,Vector3(1.66,.86,1.66))
	g.solid_inventory.append({"id":"LumeTable","bounds":AABB(at+Vector3(-.83,0,-.83),Vector3(1.66,.86,1.66))})
	g.cylinder(at+Vector3.UP*.38,.13,.76,"38625f","metal")
	for side in [-1,1]:
		var seat := at+Vector3(side*1.36,0,0)
		g.box("LumeSeat",seat+Vector3.UP*.46,Vector3(.58,.12,1.12),"ae8856",false,"wood")
		g.box("LumeSeatBack",seat+Vector3(side*.27,.77,0),Vector3(.10,.52,1.12),"ae8856",false,"wood")
		g.collision_box("LumeSeat",seat+Vector3.UP*.515,Vector3(.64,1.03,1.12))
		g.solid_inventory.append({"id":"LumeSeat","bounds":AABB(seat+Vector3(-.32,0,-.56),Vector3(.64,1.03,1.12))})
		for z in [-.37,.37]: g.box("SeatLeg",seat+Vector3(0,.23,z),Vector3(.12,.46,.12),"38625f",false,"metal")
	g.box("UmbrellaPole",at+Vector3.UP*1.50,Vector3(.11,3.0,.11),"d1ab59",true,"metal")
	for i in 12:
		var angle := TAU*i/12.0
		var next := TAU*(i+1)/12.0
		_triangle(g,[at+Vector3.UP*3.05,at+Vector3(cos(angle)*2.0,2.52,sin(angle)*2.0),at+Vector3(cos(next)*2.0,2.52,sin(next)*2.0)],COLORS[index%4] if i%2 else "e1cfa4")

static func _cart(g: Node3D, at: Vector3, sweet: bool) -> void:
	g.box("LumeCart",at+Vector3.UP*.66,Vector3(1.8,1.10,1.10),"873e4a" if sweet else "38625f",true,"wood")
	g.box("CartTop",at+Vector3.UP*1.27,Vector3(2.0,.15,1.30),"d1ab59")
	for x in [-.63,.63]:
		g.cylinder(at+Vector3(x,.31,.55),.27,.13,"272d35","metal",Basis(Vector3.RIGHT,PI*.5))
		g.box("CartCanopyPost",at+Vector3(x,1.87,0),Vector3(.08,1.2,.08),"d1ab59",true,"metal")
	g.box("CartCanopy",at+Vector3.UP*2.47,Vector3(2.10,.15,1.35),"e1cfa4")
	for x in [-.5,0,.5]: g.ball(at+Vector3(x,1.62,0),Vector3(.30,.48,.30),"e1cfa4" if sweet else "d1ab59")

static func _balloons(g: Node3D, at: Vector3) -> void:
	g.box("BalloonStand",at+Vector3.UP*.17,Vector3(.55,.34,.55),"38625f",true,"metal")
	for i in 5:
		var tip := at+Vector3(cos(i*2.1)*.43,2.2+(i%2)*.3,sin(i*2.1)*.34)
		g.beam(at+Vector3.UP*.35,tip,.012,.012,"e1cfa4")
		g.ball(tip,Vector3(.42,.58,.42),COLORS[i%4])

static func _bunting(g: Node3D, a: Vector3, b: Vector3) -> void:
	g.beam(a,b,.020,.020,"e1cfa4")
	var direction := (b-a).normalized()
	for i in 10:
		var at := a.lerp(b,(i+.5)/10.0)
		_triangle(g,[at-direction*.27,at+direction*.27,at-Vector3.UP*.47],COLORS[i%4])
		_triangle(g,[at+direction*.27,at-direction*.27,at-Vector3.UP*.47],COLORS[i%4])

static func _triangle(g: Node3D, vertices: Array, color: String) -> void:
	var st: SurfaceTool = g.batch(color,"paint")
	var normal: Vector3 = (vertices[2]-vertices[0]).cross(vertices[1]-vertices[0]).normalized()
	for point: Vector3 in vertices:
		st.set_normal(normal)
		st.set_uv(Vector2(point.x,point.z))
		st.add_vertex(point)

static func _vending(g: Node3D, id: String) -> void:
	var at: Vector3 = VENDING.MACHINES[id].position
	var basis := Basis(Vector3.UP,PI if id == "snacks" else 0.0)
	var color := "38625f" if id == "drinks" else "873e4a"
	g.box("LumeVending_"+id,at+Vector3.UP*1.08,Vector3(1.30,2.16,.85),color,true,"metal",basis)
	g.box("VendingWindow",at+basis*Vector3(-.15,1.27,.439),Vector3(.81,1.15,.026),"272d35",false,"paint",basis)
	for row in 3:
		for column in 3:
			var point := at+basis*Vector3(-.43+column*.26,.86+row*.34,.46)
			if id == "drinks":
				g.cylinder(point,.060,.21,"63769a" if column%2 else "d1ab59")
				g.cylinder(point+Vector3.UP*.13,.032,.05,"e1cfa4")
			else: g.box("VendingSnack",point,Vector3(.18,.20,.04),"d1ab59" if column%2 else "e1cfa4",false,"paint",basis)
	for y in [.89,1.13,1.37]: g.box("VendingKey",at+basis*Vector3(.48,y,.443),Vector3(.16,.12,.022),"d1ab59",false,"paint",basis)
	g.box("VendingTray",at+basis*Vector3(0,.30,.455),Vector3(.84,.25,.045),"272d35",false,"paint",basis)
	g.sign_text(VENDING.MACHINES[id].name,at+basis*Vector3(0,1.96,.445),28,PI if id == "snacks" else 0.0)
