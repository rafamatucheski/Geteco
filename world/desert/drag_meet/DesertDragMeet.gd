extends RefCounted
## Chunk-owned paddock. Parked cars admit a full driving controller on theft or
## damage; untouched displays have no audio, lamps or per-frame work.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const MATERIALS := preload("res://world/desert/DesertTownMaterials.gd")
const SURFACES := preload("res://world/places/ShopInteriorMaterials.gd")
static var _paddock_material: ShaderMaterial
static var _bay_paint_material: ShaderMaterial
static var _bay_paint_mesh: ArrayMesh
static var _detail_materials: Dictionary = {}
static var _paint_materials: Dictionary = {}
## The same 24 spectators and 12 display cars form more readable groups along
## the whole course. Milestone groups stay outside both the strip and return.
const STRIP_POCKETS := [-899.0,-790.0,-699.0,-598.0,-498.0,-380.0,-245.0,-102.0]

static func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for data in car_spots():
		result.append({"kind":"drag_meet","position":data.position,"type":"car","data":data})
	result.append_array(strip_records())
	for data in [
		{"position":Vector3(-1024,0,-1305),"color":Color("b7613b"),"size":12.0},
		{"position":Vector3(-992,0,-1304),"color":Color("d0b954"),"size":10.0},
		{"position":Vector3(-960,0,-1305),"color":Color("bb663b"),"size":12.0},
		{"position":Vector3(-971,0,-1225),"color":Color("436477"),"size":12.0},
		{"position":Vector3(-498,0,-1337),"color":Color("68734b"),"size":10.0},
		{"position":Vector3(-102,0,-1337),"color":Color("a34b3d"),"size":10.0},
		{"position":Vector3(-899,0,-1336),"color":Color("b16c43"),"size":10.0},
	]:
		result.append({"kind":"drag_meet","position":data.position,"type":"tent","data":data})
	for data in [
		{"position":Vector3(-972,0,-1223),"type":"tables"},
		{"position":Vector3(-102,0,-1338),"type":"tables"},
		{"position":Vector3(-498,0,-1338),"type":"tables"},
		{"position":Vector3(-1000,0,-1299),"type":"pit_tools"},
		{"position":Vector3(-970,0,-1301),"type":"pit_tools"},
		{"position":Vector3(-925,0,-1248),"type":"pit_tools"},
		{"position":Vector3(-976,0,-1249),"type":"pit_tools"},
		{"position":Vector3(-934,0,-1265),"type":"tires"},
		{"position":Vector3(-380,0,-1335),"type":"tires"},
		{"position":Vector3(-901,0,-1250),"type":"tires"},
		{"position":Vector3(-922,0,-1306),"type":"speakers"},
		{"position":Vector3(-1028,0,-1292),"type":"speakers"},
		{"position":Vector3(-904,0,-1268),"type":"speakers"},
		{"position":Vector3(-976,0,-1268),"type":"speakers"},
		{"position":Vector3(-1016,0,-1221),"type":"trailer"},
		{"position":Vector3(-999,0,-1221),"type":"trailer"},
		{"position":Vector3(-699,0,-1337),"type":"team_box"},
		{"position":Vector3(-981,0,-1267),"type":"team_box"},
		{"position":Vector3(-909,0,-1294),"type":"team_box"},
		{"position":Vector3(-899,0,-1337),"type":"pit_tools"},
		{"position":Vector3(-893,0,-1294),"type":"tables"},
		{"position":Vector3(-899,0,-1311),"type":"barrier"},
	]:
		result.append({"kind":"drag_meet","position":data.position,"type":data.type,"data":data})
	# Independent barriers leave the access, staging point and braking runoff open.
	for x in range(-888,-759,9):
		result.append({"kind":"drag_meet","position":Vector3(x,0,-1311),"type":"barrier","data":{}})
	for x in range(-916,-759,9):
		result.append({"kind":"drag_meet","position":Vector3(x,0,-1329),"type":"barrier","data":{}})
	result.append({"kind":"drag_workshop","position":LAYOUT.drag_workshop_point()})
	return result

## Eight finite spectator pockets follow the race, independently of the paddock's
## proximity-controlled population. Streaming owns every car, person and barrier.
static func strip_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var models := ["desert_mirage_gt","monaliza","desert_coyote_drag","ranch_pickup","station_wagon","metro_hatch"]
	var paints := [Color("8d4936"),Color("acb3b9"),Color("314b62"),Color("727545")]
	for pocket in STRIP_POCKETS.size():
		var x: float=STRIP_POCKETS[pocket]
		# The far shoulder remains readable above the HUD in the side camera.
		# One 7.6 m solid barrier protects the three-person group without adding
		# another row of scenery or blocking the service lane at z=-1350.
		# The first two pockets already have the continuous starting barrier.
		if pocket>=2: result.append({"kind":"drag_meet","position":Vector3(x,0,-1328.3),"type":"barrier","data":{}})
		for slot in 3:
			var point := Vector3(x-2.4+float(slot)*2.4,.03,-1331)
			var data := {"team":"strip","point":point,"walk_end":point,"focus":Vector3(x,0,-1320),
				"coat":paints[(pocket+slot)%paints.size()],"roamer":false,"identity":11000+pocket*3+slot}
			result.append({"kind":"drag_meet","position":point,"type":"strip_spectator","data":data})
		for slot in (2 if pocket%2==0 else 1):
			var offset := -10.0 if slot==0 else 10.0
			var car := _car("strip_%d_%d"%[pocket,slot],Vector3(x+offset,0,-1334.3),models[(pocket+slot)%models.size()],PI*.5)
			car.paint=paints[(pocket+slot)%paints.size()]
			result.append({"kind":"drag_meet","position":car.position,"type":"strip_car","data":car})
	return result

static func car_spots() -> Array[Dictionary]:
	# The actual rival models are landmarks for their social islands. Digo's Gol
	# stays inside his working garage; these four match DesertDrag.RIVALS exactly.
	var result: Array[Dictionary] = [
		_car("livia_faisca",Vector3(-964,0,-1296.8),"desert_faisca_rally",.04),
		_car("raul_coyote",Vector3(-1008,0,-1298),"desert_coyote_drag",PI),
		_car("jessica_jetta",Vector3(-908.5,0,-1260),"jessica_jetta_gli",PI*.5),
		_car("nadir_mirage",Vector3(-960.5,0,-1241),"desert_mirage_gt",-.12),
		_car("vicente_drag",Vector3(-945,0,-1259.5),"desert_coyote_drag",PI),
		_car("gang_coupe",Vector3(-952,0,-1253),"desert_mirage",PI),
		_car("gang_sedan",Vector3(-938,0,-1253),"desert_siroco",PI),
		_car("service_pickup",Vector3(-1032,0,-1268),"desert_bison",PI*.5),
	]
	# Closely parked rows leave the 8m access corridor and each conversational
	# pocket intact. Slight offsets/yaws make separate arriving groups legible.
	var rows := [
		{"z":-1305.0,"x":[-1032,-1024,-1016,-1008,-1000,-984,-976,-968,-960,-952,-944]},
		{"z":-1297.0,"x":[-1032,-1024,-1016,-992,-981,-974,-952,-944]},
		{"z":-1289.0,"x":[-1032,-1024,-1016,-988,-980,-956,-948]},
		{"z":-1218.0,"x":[-981,-969,-957,-945,-933,-921,-909,-897]},
	]
	var models := ["desert_coyote_drag","monaliza","desert_faisca_rally","station_wagon","desert_mirage","muscle_classic","metro_hatch","ranch_pickup","nordic_estate"]
	var colors := [Color("c45e32"),Color("b4b8b0"),Color("30567b"),Color("b89834"),Color("744055"),Color("334942"),Color("c6c4b6")]
	var index := 0
	for row in rows:
		for x in row.x:
			var point := Vector3(float(x),0,float(row.z)+float(index%3-1)*.22)
			var spot := _car("display_%02d"%index,point,models[index%models.size()],float(index%5-2)*.035+(PI if index%2 else 0.0))
			spot.paint=colors[index%colors.size()]
			result.append(spot)
			index+=1
	for point in [Vector3(-1033,0,-1259),Vector3(-1033,0,-1243),Vector3(-1033,0,-1227),Vector3(-980,0,-1230),Vector3(-950,0,-1230),Vector3(-925,0,-1230),Vector3(-908,0,-1237),Vector3(-898,0,-1243),Vector3(-898,0,-1257),Vector3(-898,0,-1271)]:
		var spot := _car("display_%02d"%index,point,models[index%models.size()],PI*.5 if point.x>-900 else -.06)
		spot.paint=colors[index%colors.size()]
		result.append(spot)
		index+=1
	return result

static func _car(id: String, point: Vector3, model: String, yaw: float) -> Dictionary:
	return {"id":id,"position":point,"model":model,"yaw":yaw}

static func build_ground(parent: Node3D, rect: Rect2) -> void:
	var area := LAYOUT.DRAG_MEET_BOUNDS.intersection(rect)
	if not area.has_area(): return
	var corners := PackedVector3Array()
	for point: Vector2 in [area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]:
		corners.append(Vector3(point.x,.012,point.y))
	var ground := G.quad(parent,"DragMeetPaddock",corners,_ground_material(),true)
	ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.set_meta("vehicle_surface","hard")
	for child in ground.get_children():
		if not child is StaticBody3D: continue
		child.set_meta("vehicle_surface","hard")
		# The visual film stays above the sand, but its physical support shares
		# the road datum. A 12 mm vertical face stopped arriving car hulls here.
		for collider in child.get_children():
			if not collider is CollisionShape3D or not collider.shape is ConcavePolygonShape3D: continue
			var faces: PackedVector3Array = collider.shape.get_faces()
			for index in faces.size():
				faces[index].y = LAYOUT.surface_height(Vector2(faces[index].x,faces[index].z))
			collider.shape.set_faces(faces)
	# Concrete expansion joints and individual parking outlines read at driving
	# scale without descriptive signs or a second surface over the access road.
	for data in car_spots():
		var point: Vector3=data.position
		if not rect.has_point(Vector2(point.x,point.z)): continue
		var bay := Node3D.new()
		bay.name="ParkingBay_"+str(data.id)
		bay.position=point
		bay.rotation.y=float(data.yaw)
		parent.add_child(bay)
		var paint := MeshInstance3D.new()
		paint.name="FadedBayPaint"
		paint.mesh=_parking_mesh()
		paint.material_override=_parking_paint()
		paint.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bay.add_child(paint)

static func _parking_mesh() -> ArrayMesh:
	if _bay_paint_mesh!=null: return _bay_paint_mesh
	# Paint is a flat film, not a shallow box whose vertical sides draw a dark
	# outline after the paint fades. All three strokes share one static draw.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for rect in [Rect2(-1.585,-2.95,.07,5.9),Rect2(1.515,-2.95,.07,5.9),Rect2(-1.55,2.865,3.1,.07)]:
		var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
		for index in [0,1,2,0,2,3]:
			var p: Vector2=corners[index]
			vertices.append(Vector3(p.x,.025,p.y))
			normals.append(Vector3.UP)
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	_bay_paint_mesh=ArrayMesh.new()
	_bay_paint_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return _bay_paint_mesh

static func _parking_paint() -> ShaderMaterial:
	if _bay_paint_material==null:
		_bay_paint_material=_ground_material().duplicate()
		_bay_paint_material.set_shader_parameter("parking_paint",true)
	return _bay_paint_material

static func _ground_material() -> ShaderMaterial:
	if _paddock_material!=null: return _paddock_material
	# The opaque surface keeps the same physical support. Its perimeter resolves
	# to the surrounding world-anchored sand, including its fine normal, so neither
	# rectangle boundaries nor streamed chunk boundaries need transparent decals.
	_paddock_material=ShaderMaterial.new()
	_paddock_material.shader=preload("res://world/desert/drag_meet/drag_meet_ground.gdshader")
	var bounds := LAYOUT.DRAG_MEET_BOUNDS
	_paddock_material.set_shader_parameter("court_center",bounds.get_center())
	_paddock_material.set_shader_parameter("court_half_size",bounds.size*.5)
	_paddock_material.set_shader_parameter("sand_tint",Color("b9a079"))
	return _paddock_material

static func build_record(parent: Node3D, record: Dictionary) -> void:
	var node := Node3D.new()
	if str(record.type) == "strip_spectator":
		node.free()
		node = preload("res://runtime/desert/drag_meet/TrackSpectatorSlot.gd").new()
		node.specification = record.data
	node.name="DragMeet_"+str(record.type)
	node.position=record.position
	node.set_meta("drag_meet_prop",str(record.type))
	parent.add_child(node)
	match str(record.type):
		"car", "strip_car": _parked_car(node,record.data)
		"strip_spectator": pass # The persistent slot owns admission and recovery.
		"tent": _tent(node,record.data)
		"tables": _tables(node)
		"tires": _tires(node)
		"speakers": _speakers(node)
		"trailer": _trailer(node)
		"barrier": _barrier(node)
		"pit_tools": _pit_tools(node)
		"team_box": _team_box(node)
	if str(record.type) not in ["car","strip_car","strip_spectator"]: _finish_props(node)
	MATERIALS.batch_visuals(node)

static func _parked_car(node: Node3D, data: Dictionary) -> void:
	node.name="DragMeetCar_"+str(data.id)
	node.rotation.y=float(data.yaw)
	node.set_meta("drag_strip_car_id" if str(data.id).begins_with("strip_") else "drag_meet_car_id",str(data.id))
	node.set_meta("desert_car_id",str(data.model))
	var spec := FLEET.spec(str(data.model))
	var dimensions: Array=spec["bounds_size"]
	var body := preload("res://runtime/desert/drag_meet/StealableMeetCar.gd").new()
	body.archetype = str(data.model)
	body.health = float(spec.get("durability",100.0))
	body.half_width = float(dimensions[0])*.5
	body.half_length = float(dimensions[2])*.5
	body.paint = data.get("paint",Color.html(spec.colors[0]) if spec.has("colors") else Color.WHITE)
	var model := FLEET.create(str(data.model))
	if model!=null:
		body.add_child(model)
		if data.has("paint"):
			var finish := preload("res://runtime/VehiclePaint.gd").new()
			finish.bind(model,str(data.model))
			finish.apply(data.paint)
	body.name="ParkedCarBody"
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("vehicle_surface","hard")
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(float(dimensions[0]),float(dimensions[1]),float(dimensions[2]))
	collider.shape=shape
	collider.position=Vector3(0,shape.size.y*.5+.018,0)
	body.add_child(collider)
	node.add_child(body)

static func _tent(node: Node3D, data: Dictionary) -> void:
	var half := float(data.size)*.5
	for x in [-half,half]:
		for z in [-half,half]:
			G.cylinder(node,"CanopyPost",Vector3(x,1.4,z),.055,2.8,Color("8c928d"),true)
	var corners := [Vector3(-half,2.8,-half),Vector3(half,2.8,-half),Vector3(half,2.8,half),Vector3(-half,2.8,half)]
	var peak := Vector3(0,4.0,0)
	for index in 4:
		var a: Vector3=corners[index]
		var b: Vector3=corners[(index+1)%4]
		var vertices := PackedVector3Array([a,peak,b])
		var normal := (b-a).cross(peak-a).normalized()
		if normal.y<0.0:
			vertices=PackedVector3Array([b,peak,a])
			normal=-normal
		var arrays: Array=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([normal,normal,normal])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var panel := MeshInstance3D.new()
		panel.name="CanvasRoofPanel"
		panel.mesh=mesh
		panel.material_override=G.material(data.color if index%2==0 else Color("c6b99a"))
		node.add_child(panel)
		var edge := G.box(node,"CanvasValance",(a+b)*.5-Vector3(0,.14,0),Vector3(float(data.size),.28,.025),data.color)
		if index%2==1: edge.rotation.y=PI*.5
	# Corner feet, tension strips and roof seams replace the former plain cone.
	for x in [-half,half]:
		for z in [-half,half]:
			G.box(node,"CanopyFoot",Vector3(x,.05,z),Vector3(.38,.10,.38),Color("797f79"))
	for side in [-1.0,1.0]:
		G.box(node,"CanvasTrim",Vector3(0,2.60,side*half),Vector3(half*2,.055,.04),Color("ece0bf"))

static func _tables(node: Node3D) -> void:
	G.box(node,"FoldingTable",Vector3(0,.76,0),Vector3(2.2,.10,.8),Color("b9ac8d"),true)
	for side in [-1.0,1.0]:
		G.box(node,"TableLeg",Vector3(side*.9,.36,0),Vector3(.07,.72,.64),Color("626965"),true)
		G.box(node,"Cooler",Vector3(side*.65,.95,0),Vector3(.52,.31,.42),Color("934b3d") if side<0 else Color("556f7b"),true)
		G.box(node,"CoolerLid",Vector3(side*.65,1.12,0),Vector3(.56,.05,.45),Color("c9c7b8"))
	G.cylinder(node,"WasteBin",Vector3(1.9,.5,0),.34,1.0,Color("686d54"),true)

static func _tires(node: Node3D) -> void:
	for stack in 2:
		for level in 3:
			G.cylinder(node,"SpareTire",Vector3(float(stack)*1.1,.16+float(level)*.3,0),.47,.28,Color("292c2b"),true)
	G.box(node,"PartsCase",Vector3(-1.4,.4,0),Vector3(.8,.8,.62),Color("847861"),true)

static func _speakers(node: Node3D) -> void:
	for side in [-1.0,1.0]:
		G.box(node,"SpeakerCabinet",Vector3(side*.52,.83,0),Vector3(.65,1.66,.52),Color("262b2d"),true)
		for y in [.5,1.15]:
			var speaker := G.cylinder(node,"SpeakerCone",Vector3(side*.52,y,-.275),.23,.035,Color("424b4b"))
			speaker.rotation.x=PI*.5
	G.box(node,"AmplifierCase",Vector3(0,.3,1.0),Vector3(1.45,.6,.65),Color("4a5050"),true)

static func _trailer(node: Node3D) -> void:
	G.box(node,"PaddockTrailer",Vector3(0,1.55,0),Vector3(3.4,2.6,7),Color("b3a990"),true)
	G.box(node,"TrailerRoof",Vector3(0,2.92,0),Vector3(3.55,.14,7.2),Color("cfbf9e"))
	G.box(node,"TrailerStripe",Vector3(1.72,1.32,0),Vector3(.025,.42,6.8),Color("904d3c"))
	for side in [-1.0,1.0]:
		for z in range(-3,4): G.box(node,"TrailerRib",Vector3(side*1.713,1.55,z),Vector3(.035,2.4,.055),Color("8e9389"))
		G.box(node,"TrailerCorner",Vector3(side*1.66,1.57,-3.52),Vector3(.09,2.54,.075),Color("b5b9aa"))
		G.box(node,"TrailerDoor",Vector3(side*.82,1.52,-3.52),Vector3(1.50,2.25,.05),Color("a2aa9b"))
		G.box(node,"TrailerLatch",Vector3(side*.18,1.43,-3.56),Vector3(.075,.75,.06),Color("68746c"))
		G.box(node,"WheelFender",Vector3(side*1.72,.99,0),Vector3(.18,.20,4.3),Color("8c9288"))
	G.box(node,"TrailerTowBar",Vector3(0,.42,4.3),Vector3(.16,.16,1.6),Color("666f69"),true)
	for z in [-1.5,1.5]:
		for x in [-1.65,1.65]:
			var tire := G.cylinder(node,"TrailerWheel",Vector3(x,.48,z),.46,.2,Color("252a29"))
			tire.rotation.z=PI*.5

static func _barrier(node: Node3D) -> void:
	G.box(node,"SpectatorBarrier",Vector3(0,.48,0),Vector3(7.6,.96,.46),Color("a39379"),true)
	G.box(node,"BarrierTop",Vector3(0,.985,0),Vector3(7.6,.06,.5),Color("d0b995"))
	for side in [-1.0,1.0]:
		G.box(node,"BarrierFoot",Vector3(side*2.8,.15,0),Vector3(.8,.3,.9),Color("8c8170"),true)

static func _pit_tools(node: Node3D) -> void:
	# Wheels, drawer fronts, a jack saddle and loose engine parts make the work
	# islands readable at pedestrian scale without text or idle simulation.
	G.box(node,"RollingToolCabinet",Vector3(-.7,.49,0),Vector3(.95,.84,.62),Color("a84736"),true)
	for tier in 4:
		G.box(node,"DrawerSeam",Vector3(-.7,.28+float(tier)*.16,-.325),Vector3(.84,.018,.026),Color("493c37"))
		G.box(node,"DrawerPull",Vector3(-.7,.33+float(tier)*.16,-.35),Vector3(.42,.035,.038),Color("a3aaa6"))
	for x in [-1.06,-.34]:
		for z in [-.22,.22]: G.cylinder(node,"CartCaster",Vector3(x,.09,z),.085,.08,Color("282d2b")).rotation.z=PI*.5
	G.box(node,"ToolCartTop",Vector3(-.7,.94,0),Vector3(1.03,.06,.68),Color("6b7470"))
	G.cylinder(node,"SpareTurbo",Vector3(-.86,1.10,0),.14,.18,Color("a7aaa0")).rotation.x=PI*.5
	G.box(node,"JackBase",Vector3(.73,.12,0),Vector3(.42,.23,1.0),Color("8d3930"),true)
	G.box(node,"JackArm",Vector3(.73,.26,-.05),Vector3(.20,.12,.62),Color("737d72")).rotation.x=-.30
	G.cylinder(node,"JackSaddle",Vector3(.73,.39,-.29),.12,.065,Color("262e2a"))
	G.box(node,"JackHandle",Vector3(.73,.54,.41),Vector3(.035,.96,.035),Color("8d9b8d")).rotation.x=-.3
	G.box(node,"PartsCrate",Vector3(1.55,.27,-.08),Vector3(.64,.54,.56),Color("9e8056"),true)
	for z in [-.3,.15]: G.box(node,"CrateBand",Vector3(1.55,.275,z),Vector3(.68,.55,.045),Color("6e624a"))

static func _team_box(node: Node3D) -> void:
	G.box(node,"TeamEquipmentCase",Vector3(0,.52,0),Vector3(2.3,1.04,.88),Color("455769"),true)
	for x in [-1.1,0,1.1]: G.box(node,"FlightcaseEdge",Vector3(x,.52,-.46),Vector3(.07,1.04,.055),Color("a0a9a5"))
	for y in [.03,1.01]: G.box(node,"FlightcaseRim",Vector3(0,y,-.46),Vector3(2.3,.045,.04),Color("adb6b0"))
	for x in [-.6,.6]: G.box(node,"FlightcaseHandle",Vector3(x,.61,-.5),Vector3(.30,.05,.06),Color("bac3bb"))
	G.box(node,"FuelCan",Vector3(1.72,.42,0),Vector3(.48,.84,.34),Color("978f52"),true)
	G.box(node,"FuelCanHandle",Vector3(1.72,.9,0),Vector3(.20,.10,.06),Color("5b624d"))
	G.cylinder(node,"FuelCap",Vector3(1.86,.87,0),.05,.05,Color("595f51"))

static func _paint_model(model: Node3D, color: Color) -> void:
	for child in model.get_children():
		if not child is MeshInstance3D: continue
		var source: Material=child.material_override
		if not source is StandardMaterial3D or source.resource_name!="paint": continue
		var key := str(source.get_rid())+color.to_html()
		if not _paint_materials.has(key):
			var paint := source.duplicate() as StandardMaterial3D
			paint.albedo_color=color
			_paint_materials[key]=paint
		child.material_override=_paint_materials[key]

static func _finish_props(node: Node3D) -> void:
	for child in node.get_children():
		if not child is MeshInstance3D: continue
		var source: Material=child.material_override
		if not source is StandardMaterial3D: continue
		var label := str(child.name).to_lower()
		var kind := "metal"
		if label.contains("canvas") or label.contains("cloth"): kind="cloth"
		elif label.contains("crate") or label.contains("table"): kind="wood"
		elif label.contains("tire") or label.contains("wheel") or label.contains("speaker"): kind="rubber"
		elif label.contains("barrier"): kind="concrete"
		var color: Color=source.albedo_color
		var key := kind+color.to_html()
		if not _detail_materials.has(key):
			var material := SURFACES.material(kind,color).duplicate() as StandardMaterial3D
			material.uv1_world_triplanar=true
			material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			material.roughness=.76 if kind=="metal" else .96
			material.metallic=.28 if kind=="metal" else 0.0
			_detail_materials[key]=material
		child.material_override=_detail_materials[key]
