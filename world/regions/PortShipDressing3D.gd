extends Node3D
## Static, batched native 3D ship finish. Every piece is visual-only and is
## kept off boarding routes; authored hulls, rails and cranes own collision.
const PAINT := preload("res://world/regions/PortShipMaterials3D.gd")

var _batches: Dictionary = {}

func _box(at: Vector3, size: Vector3, color: String, basis := Basis.IDENTITY) -> void:
	var tool: SurfaceTool = _batches.get(color)
	if tool == null:
		tool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[color] = tool
	var shape := BoxMesh.new()
	shape.size = size
	tool.append_from(shape,0,Transform3D(basis,at))

func _beam(a: Vector3, b: Vector3, width: float, color: String) -> void:
	var up := (b-a).normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	if right.length_squared() < .1: right = up.cross(Vector3.RIGHT).normalized()
	_box((a+b)*.5,Vector3(width,a.distance_to(b),width),color,Basis(right,up,right.cross(up)).orthonormalized())

func _edge(a: Vector2, b: Vector2, height: float, size: Vector2, color: String) -> void:
	var delta := b-a
	_box(Vector3((a.x+b.x)*.5,height,(a.y+b.y)*.5),Vector3(size.x,size.y,delta.length()),color,Basis(Vector3.UP,atan2(delta.x,delta.y)))

func _finish() -> void:
	for color in _batches:
		var mesh := MeshInstance3D.new()
		mesh.name = "BatchedSteel_"+str(color)
		mesh.mesh = (_batches[color] as SurfaceTool).commit()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = .72
		material.metallic = .22
		if color == "344c54": mesh.material_override = PAINT.material("hull")
		elif color in ["c1a051","d8b765","d3ae53","e0b54d","b48d45"]: mesh.material_override = PAINT.material("crane")
		else: mesh.material_override = material
		add_child(mesh)
	_batches.clear()

func _deck(hull: PackedVector2Array) -> void:
	var points := PackedVector2Array()
	for point in hull: points.append(point/16.0)
	var indices := Geometry2D.triangulate_polygon(points)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,indices.size(),3):
		var a := Vector3(points[indices[i]].x,.02,points[indices[i]].y)
		var b := Vector3(points[indices[i+1]].x,.02,points[indices[i+1]].y)
		var c := Vector3(points[indices[i+2]].x,.02,points[indices[i+2]].y)
		surface.set_normal(Vector3.UP)
		surface.add_vertex(a)
		if (b-a).cross(c-a).y > 0:
			surface.add_vertex(c)
			surface.add_vertex(b)
		else:
			surface.add_vertex(b)
			surface.add_vertex(c)
	var deck := MeshInstance3D.new()
	deck.name = "SantaMarePaintedDeck"
	deck.mesh = surface.commit()
	deck.material_override = PAINT.material("deck")
	add_child(deck)

func build_northstar(outline: PackedVector2Array) -> void:
	name = "NorthstarShipDetail3D"
	for i in outline.size():
		_edge(outline[i],outline[(i+1)%outline.size()],-.25,Vector2(.08,.12),"b8b9a9")
		_edge(outline[i],outline[(i+1)%outline.size()],-1.5,Vector2(.12,2.6),"344c54")
	for z in [66.0,74.0,82.0,90.0,98.0,106.0]:
		_box(Vector3(235.65,-.75,z),Vector3(.13,.28,.45),"1d343d")
		_box(Vector3(235.73,-.75,z),Vector3(.035,.17,.29),"8da9a9")
	for z in [60.0,84.0,109.0,124.0]:
		_box(Vector3(210.7,-.55,z),Vector3(.58,1.0,.44),"28383a")
	_beam(Vector3(211.0,.55,58.0),Vector3(201.0,.36,55.0),.055,"9a927c")
	_beam(Vector3(211.0,.55,124.0),Vector3(201.0,.36,127.0),.055,"9a927c")
	# Glazing and roof gear give the aft superstructure a legible profile.
	for z in [114.0,118.0,122.0]:
		_box(Vector3(231.30,2.30,z),Vector3(.08,.58,2.1),"263f49")
	for z in [113.0,116.1,119.2]:
		_box(Vector3(228.12,3.58,z),Vector3(.08,.48,1.75),"264b55")
	_box(Vector3(223.1,4.23,118.1),Vector3(13.0,.12,8.7),"52656a")
	for z in [115.0,123.5]:
		_box(Vector3(231.4,2.25,z),Vector3(.46,.82,1.3),"ca7d4b")
	_box(Vector3(224.7,5.32,113.5),Vector3(.12,3.0,.12),"c6c2ab")
	_box(Vector3(224.7,6.38,113.5),Vector3(2.3,.08,.10),"c6c2ab")
	_box(Vector3(225.8,6.30,113.5),Vector3(.72,.18,.38),"d4bd81")
	# Maintenance scaffold outside the starboard hull, above the open basin.
	var near_x := 235.75
	var outer_x := 238.15
	var start_z := 74.0
	var end_z := 99.0
	_box(Vector3((near_x+outer_x)*.5,.12,(start_z+end_z)*.5),Vector3(2.55,.18,end_z-start_z),"8a7860")
	for i in 6:
		var z := start_z+i*5.0
		for x in [near_x,outer_x]:
			_box(Vector3(x,.25,z),Vector3(.11,2.9,.11),"c1a051")
		_box(Vector3((near_x+outer_x)*.5,.02,z),Vector3(2.55,.11,.13),"5e6e6d")
		if i < 5:
			_beam(Vector3(outer_x,-.9,z),Vector3(outer_x,1.5,z+5.0),.07,"708484")
			_beam(Vector3(outer_x,1.5,z),Vector3(outer_x,-.9,z+5.0),.07,"708484")
	_box(Vector3(outer_x,1.5,(start_z+end_z)*.5),Vector3(.1,.1,end_z-start_z),"c1a051")
	_box(Vector3(outer_x,.65,(start_z+end_z)*.5),Vector3(.07,.07,end_z-start_z),"c1a051")
	_finish()

func build_santa_mare(hull: PackedVector2Array) -> void:
	name = "SantaMareShipDetail3D"
	_deck(hull)
	var scale := 1.0/16.0
	for i in hull.size():
		var a := hull[i]*scale
		var b := hull[(i+1)%hull.size()]*scale
		_edge(a,b,-1.35,Vector2(.24,2.7),"344c54")
		_edge(a,b,-.16,Vector2(.27,.10),"c6c2ab")
		_edge(a,b,-2.58,Vector2(.27,.08),"8a5147")
	# The bridge sits above the original deckhouse; glazed faces, wings and
	# radar make the pilot station visible from the normal game camera.
	_box(Vector3(255.9,5.15,181.7),Vector3(10.4,1.0,9.2),"bec8c1")
	_box(Vector3(255.9,5.72,181.7),Vector3(11.1,.18,9.8),"52656a")
	for x in [252.0,254.0,256.0,258.0,260.0]:
		_box(Vector3(x,5.24,186.34),Vector3(1.55,.54,.08),"263f49")
	for z in [179.0,181.5,184.0]:
		_box(Vector3(250.63,5.24,z),Vector3(.08,.54,1.65),"263f49")
		_box(Vector3(261.17,5.24,z),Vector3(.08,.54,1.65),"263f49")
	_box(Vector3(254.5,6.55,177.8),Vector3(.82,1.7,.82),"5a6b69")
	_box(Vector3(254.5,7.48,177.8),Vector3(1.0,.22,1.0),"303d42")
	_box(Vector3(259.0,7.2,181.7),Vector3(.12,2.8,.12),"d3d0b8")
	_box(Vector3(259.0,8.3,181.7),Vector3(2.4,.09,.12),"d3d0b8")
	_box(Vector3(255.9,5.84,181.7),Vector3(6.8,.08,5.4),"425960")
	_box(Vector3(257.2,5.98,181.7),Vector3(1.0,.24,1.0),"b7b5a1")
	for side in [-1.0,1.0]:
		var boat_z: float = 181.7+float(side)*7.2
		_box(Vector3(255.8,2.75,boat_z),Vector3(4.2,.52,1.38),"db8049")
		_box(Vector3(255.8,3.07,boat_z),Vector3(3.8,.14,1.16),"e8dfc8")
		for boat_x in [253.8,257.8]:
			_beam(Vector3(boat_x,3.25,boat_z),Vector3(boat_x,4.25,boat_z-side*.55),.07,"b9b59c")
	for x in [268.0,286.0,304.0,322.0,340.0]:
		_box(Vector3(x,-.85,194.94),Vector3(.48,1.2,.20),"182d33")
		_box(Vector3(x,-.7,195.06),Vector3(.25,.25,.04),"93a9a4")
	# Boarding hatch is in the clear lane between wheelhouse and cargo.
	_box(Vector3(265.65,.055,186.25),Vector3(1.48,.11,1.48),"697a78")
	_box(Vector3(264.9,.62,186.25),Vector3(.12,1.12,1.62),"b7a252")
	_box(Vector3(265.65,.08,185.43),Vector3(1.65,.16,.12),"d2b458")
	_box(Vector3(265.65,.08,187.07),Vector3(1.65,.16,.12),"d2b458")
	# Quay equipment and stained service bays keep the berth readable in motion.
	for x in [258.0,295.0,332.0]:
		_box(Vector3(x,.22,202.9),Vector3(.9,.42,.45),"a1a07e")
		_box(Vector3(x,.08,203.8),Vector3(.16,.04,3.1),"d2af56")
		_box(Vector3(x,.08,211.4),Vector3(.16,.04,3.1),"d2af56")
		for j in 3:
			_box(Vector3(x-2.0+j*1.9,.035,207.3),Vector3(.9,.025,.06),"b8a27b")
	for x in [250.0,280.0,310.0,338.0]:
		_box(Vector3(x,-.55,195.1),Vector3(.48,1.0,.56),"28383a")
	_beam(Vector3(251.0,.55,194.8),Vector3(248.5,.36,202.5),.055,"9a927c")
	_beam(Vector3(347.0,.55,192.6),Vector3(351.0,.36,202.0),.055,"9a927c")
	for z in [171.7,194.2]:
		_box(Vector3(297.0,.045,z),Vector3(91.0,.018,.11),"b5a570")
	for x in [271.0,320.0]:
		_box(Vector3(x,.045,183.1),Vector3(.11,.018,19.0),"b5a570")
	# A low side access platform below the sheer line, outside the north rail.
	var start_x := 279.0
	var end_x := 309.0
	var inner_z := 170.35
	var outer_z := 168.65
	_box(Vector3((start_x+end_x)*.5,.12,(inner_z+outer_z)*.5),Vector3(end_x-start_x,.18,1.85),"8a7860")
	for i in 7:
		var x := start_x+i*5.0
		for z in [inner_z,outer_z]:
			_box(Vector3(x,.2,z),Vector3(.11,2.8,.11),"c1a051")
		_box(Vector3(x,.02,(inner_z+outer_z)*.5),Vector3(.12,.12,1.85),"5e6e6d")
		if i < 6:
			_beam(Vector3(x,-1.1,outer_z),Vector3(x+5.0,1.45,outer_z),.07,"708484")
			_beam(Vector3(x,1.45,outer_z),Vector3(x+5.0,-1.1,outer_z),.07,"708484")
	_box(Vector3((start_x+end_x)*.5,1.52,outer_z),Vector3(end_x-start_x,.1,.1),"c1a051")
	_box(Vector3((start_x+end_x)*.5,.65,outer_z),Vector3(end_x-start_x,.07,.07),"c1a051")
	_finish()

func build_northstar_crane(point: Vector2) -> void:
	name = "NorthstarCraneRigging3D"
	var origin := Vector3(point.x,5.15,point.y)
	var tip := origin+Vector3(18.0,0,0)
	for side in [-1.0,1.0]:
		_beam(origin+Vector3(0,.36,side*.24),tip+Vector3(0,.36,side*.24),.10,"d8b765")
		for i in 8:
			var x := float(i)*2.25
			_beam(origin+Vector3(x,.36,side*.24),origin+Vector3(x+2.25,-.18,side*.24),.08,"b48d45")
	_box(origin+Vector3(-1.0,-.1,0),Vector3(1.1,.9,1.0),"7b6745")
	_box(tip+Vector3(0,-1.8,0),Vector3(.27,.36,.30),"d3ae53")
	_box(tip+Vector3(0,-2.13,0),Vector3(.12,.35,.12),"596665")
	_finish()

func build_south_crane(width: float, depth: float) -> void:
	name = "QuaysideCraneRigging3D"
	var base := Vector3(-width*.4,0,depth*.42)
	var start := base+Vector3(0,7,4)
	var tip := Vector3(width*.48,8,-depth*.42)
	# High catwalk and ladder are above pedestrian and vehicle clearance.
	var mid := start.lerp(tip,.28)
	_beam(start+Vector3(-.62,-.48,0),mid+Vector3(-.62,-.48,0),.18,"73817d")
	_beam(start+Vector3(-.62,.22,0),mid+Vector3(-.62,.22,0),.08,"d8b765")
	for i in 5:
		var y := 1.6+i*.9
		_box(base+Vector3(-.8,y,1.0),Vector3(.08,.08,.62),"d8b765")
	_box(tip+Vector3(0,-.45,0),Vector3(.72,.45,.62),"e0b54d")
	_finish()
