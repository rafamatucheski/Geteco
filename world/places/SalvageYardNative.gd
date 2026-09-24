extends Node3D
## Original SalvageYard3D geometry extracted; crane/press share native world.
const PICKUP := Vector3(-1,0,6)
const PRESS := Vector3(7.2,0,-1.5)
var stage: Node3D
var hook: Node3D
var boom: Node3D
var beam: MeshInstance3D
var cable: MeshInstance3D
var plate: Node3D
var press: Node3D
var _materials := {}
var solids: Array[Dictionary] = []
func _ready() -> void:
	stage = self
	_build()
	_update_crane()
	for entry in solids:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for point in entry.polygon:
			points.append(Vector3(point.x,0,point.y))
			points.append(Vector3(point.x,2.4,point.y))
		shape.points = points
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
	for label in find_children("*","Label3D",true,false): label.hide()
func projected(point: Vector3) -> Vector2: return Vector2(point.x,point.z)
func npc_point() -> Vector3: return global_position+Vector3(-6,0,8.7)
func dock_point() -> Vector3: return global_position+PICKUP

func _solid_group(id: String, nodes: Array) -> void:
	var points := PackedVector2Array()
	for node in nodes: _mesh_points(node, points)
	if points.size() >= 3:
		solids.append({"id":id,"polygon":Geometry2D.convex_hull(points)})

func _mesh_points(node: Node, points: PackedVector2Array) -> void:
	if node is MeshInstance3D:
		var bounds: AABB = node.mesh.get_aabb()
		for i in 8:
			# Include visible height: a car cannot draw over the north face/roof.
			points.append(Vector2((global_transform.affine_inverse()*node.global_transform*bounds.get_endpoint(i)).x,(global_transform.affine_inverse()*node.global_transform*bounds.get_endpoint(i)).z))
	for child in node.get_children(): _mesh_points(child, points)

func _solid_since(id: String, first: int) -> void:
	_solid_group(id, stage.get_children().slice(first))

func _mat(hex: String, metal := 0.0) -> StandardMaterial3D:
	if _materials.has(hex): return _materials[hex]
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(hex)
	result.metallic = metal
	result.roughness = 0.88
	# Shared mipmapped tiles, projected in model space, preserve all solid geometry.
	var kind := "gravel" if hex=="706a56" else ("concrete" if hex=="888c7f" else "metal")
	result.albedo_texture = preload("res://assets/regions/source/world/harbor/UrbanGround.gd").texture(kind)
	result.uv1_triplanar = true
	result.uv1_scale = Vector3.ONE*(.6 if kind=="gravel" else .35)
	_materials[hex] = result
	return result

func box(parent: Node3D, at: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = _mat(color)
	part.position = at
	parent.add_child(part)
	return part

func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	part.mesh = mesh
	part.material_override = _mat(color)
	part.position = at
	parent.add_child(part)
	return part

func _build() -> void:
	box(stage,Vector3(0,-.14,0),Vector3(32,.22,23),"706a56")
	box(stage,Vector3(2,-.01,3),Vector3(16,.08,17),"888c7f")
	# Wheel tracks, cracks, oil spills and a marked delivery pad.
	for x in [-2.0,0.0]:
		box(stage,Vector3(x,.04,8),Vector3(.14,.012,6),"5b5c52")
	for p in [Vector3(-6,.03,-4),Vector3(10,.04,-7),Vector3(-11,.04,1)]:
		var oil := cylinder(stage,p,1.0,.016,"3b413b")
		oil.scale.z = .6
	for x in [-2.5,.5]:
		box(stage,Vector3(x,.06,6),Vector3(.12,.015,5.1),"e8c86f")
	for z in [3.5,8.5]:
		box(stage,Vector3(-1,.06,z),Vector3(3.1,.015,.12),"e8c86f")
	# Text and pictograms live on readable boards in the world canvas.
	# Workshop office with corrugated roof, reception awning, window and benches.
	var first := stage.get_child_count()
	box(stage,Vector3(-10,1.1,5),Vector3(6,2.2,3.6),"456258")
	box(stage,Vector3(-10,2.3,5),Vector3(6.5,.17,4.1),"a1a99a")
	for x in range(-13,-6):
		box(stage,Vector3(x,2.42,5),Vector3(.065,.07,4.1),"c1c1a4")
	box(stage,Vector3(-10,1.3,6.84),Vector3(2.6,.7,.04),"1c3439")
	box(stage,Vector3(-12,1,6.84),Vector3(.9,1.9,.06),"b99b69")
	box(stage,Vector3(-10,2.16,7.55),Vector3(6.5,.12,1.5),"b97740")
	for x in [-13.0,-7.0]: box(stage,Vector3(x,1.08,8.2),Vector3(.09,2.2,.09),"6e7261")
	_solid_since("Office", first)
	# Containers, sorted engines and rusty barrels; they stay outside the bay.
	for x in [-10.0,-4.0]:
		first = stage.get_child_count()
		box(stage,Vector3(x,1,-8.5),Vector3(4.7,2,2.6),"80503c" if x < -5 else "536c78")
		for rib in 12:
			box(stage,Vector3(x-2.2+rib*.4,1,-7.16),Vector3(.055,1.8,.08),"c19265" if x < -5 else "829496")
		_solid_since("Container%d" % int(x), first)
	first = stage.get_child_count()
	for i in 9:
		var p := Vector3(12+(i%3)*.65,.5,3+(i/3)*.7)
		cylinder(stage,p,.28,1,"a65a35" if i%3 == 0 else "3d686b" if i%3 == 1 else "b8a265")
		for y in [-.28,.28]: cylinder(stage,p+Vector3(0,y,0),.29,.04,"4a4c41")
	_solid_since("Barrels", first)
	# Recognisable stripped bodies: hollow passenger cells, missing doors,
	# bent hoods, independent wheels and mismatched metal panels.
	for i in 8:
		var colors := ["9a3d32","527e86","c4a44b","b9b7a0","5d7152","604d7f","33546b","bf7750"]
		var p := Vector3(-12+(i%3)*4.0,.22+(i/3)*.15,-3+(i/3)*2.8)
		if i >= 6: p = Vector3(11,.25+(i-6)*.95,-6)
		_wreck(p,colors[i],float(i)*.19-.6)
	first = stage.get_child_count()
	for i in 12:
		var p := Vector3(13+(i%2)*.8,.20+(i/4)*.3,7+(i%4)*.5)
		var tire := TorusMesh.new()
		tire.inner_radius=.19
		tire.outer_radius=.38
		tire.rings=12
		tire.ring_segments=8
		var part := MeshInstance3D.new()
		part.mesh=tire
		part.position=p
		part.material_override=_mat("252d2c")
		stage.add_child(part)
	_solid_since("Tires", first)
	first = stage.get_child_count()
	for i in 6:
		box(stage,Vector3(-14,.22,6-i*.8),Vector3(.55,.45,.55),"64706c")
	_solid_since("Engines", first)
	# Two-sided fence with a wide southern vehicle gate.
	for x in range(-16,17,2):
		_fence_post(Vector3(x,0,-11.5))
		if abs(x)>3: _fence_post(Vector3(x,0,11.5))
	for z in range(-10,12,2):
		_fence_post(Vector3(-16,0,z))
		_fence_post(Vector3(16,0,z))
	for y in [.6,1.3]:
		box(stage,Vector3(0,y,-11.5),Vector3(32,.05,.05),"797565")
		for x in [-16,16]: box(stage,Vector3(x,y,0),Vector3(.05,.05,23),"797565")
		for x in [-10,10]: box(stage,Vector3(x,y,11.5),Vector3(12,.05,.05),"797565")
	for x in [-3.9,3.9]: box(stage,Vector3(x,1.45,11.5),Vector3(.17,2.9,.17),"7a6c4d")
	# Same endpoints drive the fence meshes and the continuous physical walls.
	for rect in [Rect2(-16.12,-11.62,32.24,.24),Rect2(-16.12,-11.62,.24,23.24),Rect2(15.88,-11.62,.24,23.24),Rect2(-16.12,11.38,12.24,.24),Rect2(3.88,11.38,12.24,.24)]:
		var points := PackedVector2Array()
		for p in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
			points.append(projected(Vector3(p.x,0,p.y)))
			points.append(projected(Vector3(p.x,1.6,p.y)))
		solids.append({"id":"Fence%d" % solids.size(),"polygon":Geometry2D.convex_hull(points)})
	_build_crane()
	_build_press()
	# Loose panels, oily engine blocks and scrap beams break up clean surfaces.
	var rng:=RandomNumberGenerator.new()
	rng.seed=144
	for i in 48:
		var p:=Vector3(rng.randf_range(-14,-3),.07,rng.randf_range(-6,2))
		var mark:=cylinder(stage,p,rng.randf_range(.12,.45),.014,"4c4d3d")
		mark.scale.z=rng.randf_range(.3,.8)
	first = stage.get_child_count()
	for i in 18:
		var p:=Vector3(11+rng.randf_range(-1,1),.1+(i%3)*.13,-9+rng.randf_range(-.7,.7))
		box(stage,p,Vector3(rng.randf_range(1,2.8),.12,.15),"83523b" if i%2==0 else "6c7569").rotation.y=rng.randf_range(-1,1)
	_solid_since("ScrapBeams", first)

func _fence_post(p: Vector3) -> void:
	box(stage,p+Vector3(0,.8,0),Vector3(.11,1.6,.11),"777562")

func _wreck(p: Vector3, color: String, angle: float) -> void:
	var car := Node3D.new()
	car.position=p
	car.rotation.y=angle
	stage.add_child(car)
	box(car,Vector3(0,.25,0),Vector3(1.7,.24,3.4),"4c4a3f")
	box(car,Vector3(0,.52,-1.25),Vector3(1.75,.40,.85),color).rotation.x=.14
	box(car,Vector3(0,.5,1.35),Vector3(1.7,.40,.65),color)
	for x in [-.8,.8]:
		box(car,Vector3(x,.5,0),Vector3(.09,.32,2.2),color)
		for z in [-.85,.8]: box(car,Vector3(x,.95,z),Vector3(.08,.95,.08),color)
	# Partially cut roofs leave the cabin visibly hollow from the game camera.
	box(car,Vector3(0,1.40,.55),Vector3(1.75,.09,.6),color).rotation.z=.15
	box(car,Vector3(-.75,1.3,-.3),Vector3(.12,.1,1.35),color).rotation.x=.15
	box(car,Vector3(.7,1.35,-.3),Vector3(.1,.1,1.35),color).rotation.z=-.25
	box(car,Vector3(.4,.79,-1.15),Vector3(.9,.05,.65),"8a5b3e").rotation.z=.35
	box(car,Vector3(-1.1,.2,.2),Vector3(.08,.6,1.0),color).rotation.z=.8
	box(car,Vector3(0,.45,.4),Vector3(1.2,.18,1.1),"483c30")
	for z in [-1,1]:
		var wheel := cylinder(car,Vector3(.86,.2,z),.31,.19,"232a29")
		wheel.rotation.z=PI*.5
	_solid_group("Wreck%d" % solids.size(), [car])

func _label(parent: Node3D, text: String, p: Vector3, size: int, color: Color, flat := false) -> void:
	var label := Label3D.new()
	label.text=text
	label.font_size=size
	label.pixel_size=.007
	label.modulate=color
	label.outline_size=5
	label.position=p
	if flat: label.rotation_degrees.x=-90
	parent.add_child(label)

func _build_crane() -> void:
	var first := stage.get_child_count()
	box(stage,Vector3(-5,.25,-1),Vector3(3.3,.5,3.3),"535c52")
	for x in [-5.8,-4.2]:
		for z in [-1.8,-.2]: box(stage,Vector3(x,3,z),Vector3(.23,6,.23),"c18b39")
	for y in range(1,6):
		box(stage,Vector3(-5,y,-1.8),Vector3(1.8,.14,.14),"e5b65a")
		box(stage,Vector3(-5.8,y,-1),Vector3(.14,.14,1.8),"e5b65a")
	box(stage,Vector3(-5,4.9,-1),Vector3(2.2,1.5,2.0),"ae7b32")
	box(stage,Vector3(-5,5.1,.02),Vector3(1.7,.75,.06),"28464c")
	_solid_since("CraneTower", first)
	boom=Node3D.new()
	boom.position=Vector3(-5,6,-1)
	stage.add_child(boom)
	beam=box(boom,Vector3(4,0,0),Vector3(8,.5,.45),"d6a344")
	box(boom,Vector3(-1.3,-.1,0),Vector3(2,1.0,1.0),"46514b")
	hook=Node3D.new()
	hook.position=PICKUP+Vector3(0,4,0)
	stage.add_child(hook)
	cylinder(hook,Vector3.ZERO,.65,.23,"4e5b53")
	cylinder(hook,Vector3(0,.12,0),.38,.20,"b1843f")
	cable=cylinder(stage,Vector3.ZERO,.035,1,"343d38")

func _build_press() -> void:
	press = preload("res://world/neco_press/NecoPressFactory.gd").create_press_at_salvage_yard()
	stage.add_child(press)
	# Compatibility reference only; no old static press or broad Press hull remains.
	plate = press.get_node("RamAssembly")


func _update_crane() -> void:
	var direction := Vector2(hook.position.x+5,hook.position.z+1)
	boom.rotation.y=-direction.angle()
	beam.scale.x=direction.length()/8.0
	beam.position.x=direction.length()*.5
	var height := maxf(.1,6-hook.position.y)
	cable.scale.y=height
	cable.position=Vector3(hook.position.x,hook.position.y+height*.5,hook.position.z)

