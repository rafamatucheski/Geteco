extends RefCounted
## One static vertex-colour mesh per populated chunk. No wind shader or frame callbacks.
const FIELD := preload("res://world/desert/DesertTerrainRelief.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const FLORA := preload("res://assets/urban_detail/FloraSurfaces.gd")
const CELL := 26.0

static func build_chunk(parent: Node3D,rect: Rect2,world_seed: int,height_callable: Callable) -> int:
	var area := rect.intersection(FIELD.BOUNDS)
	if not area.has_area() or not height_callable.is_valid(): return 0
	var data := {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}
	var body := StaticBody3D.new()
	body.name="DesertDryFloraSolids"
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("vehicle_surface","hard")
	var count := 0
	# Células globais, com margem suficiente para companheiros deslocados que pertencem a chunks vizinhos.
	for x in range(floori(area.position.x/CELL)-1,ceili(area.end.x/CELL)+1):
		for z in range(floori(area.position.y/CELL)-1,ceili(area.end.y/CELL)+1):
			var rng := RandomNumberGenerator.new()
			rng.seed=absi(world_seed+x*7139+z*3137)
			if rng.randf()>.57: continue
			var anchor := Vector2((float(x)+rng.randf_range(.2,.8))*CELL,(float(z)+rng.randf_range(.2,.8))*CELL)
			for member in 3:
				var p := anchor+Vector2(rng.randf_range(-3.2,3.2),rng.randf_range(-3.2,3.2))
				var kind := rng.randi_range(0,5) if member==0 else 5
				var yaw := rng.randf_range(0,TAU)
				var scale := rng.randf_range(.8,1.2)
				var radius := (1.5 if kind==2 else .9)*scale
				if not rect.has_point(p) or not _clear(p,radius): continue
				var at := Vector3(p.x,float(height_callable.call(p))-.08,p.y)
				var basis := Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale)
				if kind<3: _breakable_plant(parent,at,basis,kind,rng.randf_range(1.4,2.1))
				else: _shrub(data,at,basis,rng)
				count+=1
	if count==0:
		body.free()
		return 0
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=data.vertices
	arrays[Mesh.ARRAY_NORMAL]=data.normals
	arrays[Mesh.ARRAY_COLOR]=data.colors
	var mesh := ArrayMesh.new()
	if not data.vertices.is_empty(): mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.name="DesertDryFloraBatch"
	node.mesh=mesh
	node.material_override=FLORA.material("cactus",Color.WHITE,1.0,1.0,.9,true)
	parent.add_child(node)
	if body.get_child_count()>0: parent.add_child(body)
	else: body.free()
	return count

static func _clear(p: Vector2,radius: float) -> bool:
	return FIELD.BOUNDS.grow(-radius).has_point(p) and not FIELD.passage_clear(p,radius) and LAYOUT.road_clear(p,radius+2.0) and FIELD.normal_at(p).y>.68

static func _breakable_plant(parent: Node3D, at: Vector3, basis: Basis, kind: int, height: float) -> void:
	var data := {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}
	var body := StaticBody3D.new()
	body.collision_layer=1
	body.collision_mask=0
	if kind<2: _cactus(data,body,Vector3.ZERO,basis,height)
	else: _snag(data,body,Vector3.ZERO,basis)
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=data.vertices
	arrays[Mesh.ARRAY_NORMAL]=data.normals
	arrays[Mesh.ARRAY_COLOR]=data.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var plant := MeshInstance3D.new()
	plant.name="DesertBreakableFlora"
	plant.mesh=mesh
	plant.material_override=FLORA.cactus() if kind<2 else FLORA.bark()
	plant.position=at
	plant.add_child(body)
	parent.add_child(plant)
	preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("desert_tree",plant,parent)

static func _cactus(data: Dictionary,body: StaticBody3D,at: Vector3,basis: Basis,height: float) -> void:
	var green := Color("586345")
	var foot := at
	var top := at+basis*Vector3(0,height,0)
	_branch(data,foot,top,.14,green,7)
	_solid(body,foot,top,.14,7)
	for side in [-1.0,1.0]:
		var rise := height*(.45 if side<0 else .62)
		var start := at+basis*Vector3(0,rise,0)
		var elbow := at+basis*Vector3(side*.37,rise+.02,0)
		var tip := at+basis*Vector3(side*.37,rise+height*.27,0)
		_branch(data,start,elbow,.09,green.lightened(.055),6)
		_branch(data,elbow,tip,.075,green,6)
		_solid(body,start,elbow,.09)
		_solid(body,elbow,tip,.075)

static func _snag(data: Dictionary,body: StaticBody3D,at: Vector3,basis: Basis) -> void:
	var wood := Color("76634b")
	var a := at+basis*Vector3(-1.15,.12,0)
	var b := at+basis*Vector3(1.1,.45,.22)
	_branch(data,a,b,.11,wood,6)
	_solid(body,a,b,.11)
	_branch(data,at+basis*Vector3(-.5,.20,.05),at+basis*Vector3(-.15,.70,.55),.050,wood,5)
	_branch(data,at+basis*Vector3(.30,.34,.13),at+basis*Vector3(.75,.62,-.5),.055,wood.lightened(.09),5)

static func _shrub(data: Dictionary,at: Vector3,basis: Basis,rng: RandomNumberGenerator) -> void:
	var straw := Color("94805a")
	for branch in 7:
		var angle := float(branch)*TAU/7.0
		var radial := Vector3(cos(angle),0,sin(angle))
		var middle := radial*rng.randf_range(.14,.26)+Vector3.UP*rng.randf_range(.22,.34)
		var tip := radial*rng.randf_range(.42,.63)+Vector3.UP*rng.randf_range(.45,.83)
		_branch(data,at,at+basis*middle,.022,straw,3)
		_branch(data,at+basis*middle,at+basis*tip,.014,straw.lightened(.08),3)
		var fork := middle+radial*.18+Vector3.UP*.29+Vector3(-radial.z,0,radial.x)*.15
		_branch(data,at+basis*middle,at+basis*fork,.011,straw,3)

static func _branch(data: Dictionary,a: Vector3,b: Vector3,radius: float,color: Color,sides: int) -> void:
	var up := (b-a).normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	if right.length_squared()<.1: right=Vector3.RIGHT
	var forward := right.cross(up)
	for side in sides:
		var angle := float(side)*TAU/float(sides)
		var next := float(side+1)*TAU/float(sides)
		var r0 := (right*cos(angle)+forward*sin(angle))*radius
		var r1 := (right*cos(next)+forward*sin(next))*radius
		_triangle(data,a+r0,a+r1,b+r1,color)
		_triangle(data,a+r0,b+r1,b+r0,color)
		_triangle(data,b+r0,b+r1,b,color.lightened(.04))

static func _triangle(data: Dictionary,a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
	var normal := (c-a).cross(b-a).normalized()
	data.vertices.append_array(PackedVector3Array([a,b,c]))
	data.normals.append_array(PackedVector3Array([normal,normal,normal]))
	data.colors.append_array(PackedColorArray([color,color,color]))

static func _solid(body: StaticBody3D,a: Vector3,b: Vector3,radius: float,sides := 6) -> void:
	# Convex points exactly match the visible prism; no capsule end extends above a cactus.
	var up := (b-a).normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	if right.length_squared()<.1: right=Vector3.RIGHT
	var forward := right.cross(up)
	var points := PackedVector3Array()
	for side in sides:
		var angle := float(side)*TAU/float(sides)
		var radial := (right*cos(angle)+forward*sin(angle))*radius
		points.append(a+radial)
		points.append(b+radial)
	var shape := ConvexPolygonShape3D.new()
	shape.points=points
	var node := CollisionShape3D.new()
	node.shape=shape
	body.add_child(node)
