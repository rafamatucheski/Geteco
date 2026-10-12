extends Node3D
## Five visual animals, no combat/physics agents. Physics poses with 10 Hz terrain samples.
const FIELD := preload("res://world/desert/DesertTerrainRelief.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const COUNT := 5
const TICK := .1
const RANGE := 38.0
var _height := Callable()
var _seed := 6102026
var _focus := Vector3.ZERO
var _elapsed := 0.0
var _clock := 0.0
var _placement_elapsed := 0.0
var _animals: Array[Dictionary]=[]
static var _material: StandardMaterial3D
static var _sphere: SphereMesh
static var _limb: CylinderMesh
static var _floor_route := PackedVector3Array()
static var _access_route := PackedVector3Array()

func configure(height_callable: Callable, world_seed := 6102026) -> void:
	_height=height_callable
	_seed=world_seed
	name="DesertWildlife"
	suspend()

func set_focus(point: Vector3) -> void:
	_focus=point
	if not _height.is_valid() or not FIELD.BOUNDS.grow(22.0).has_point(Vector2(point.x,point.z)):
		suspend()
		return
	visible=true
	set_physics_process(true)

func suspend() -> void:
	visible=false
	set_physics_process(false)
	_elapsed=0
	_placement_elapsed=1.0

func _physics_process(delta: float) -> void:
	if _animals.is_empty():
		for i in COUNT: _animals.append(_create(i))
	_elapsed+=delta
	var sample_ground := _elapsed>=TICK
	if sample_ground: _elapsed=fmod(_elapsed,TICK)
	_clock+=delta
	_placement_elapsed+=delta
	if _placement_elapsed>=1.0:
		_placement_elapsed=0
		for i in _animals.size():
			var animal: Dictionary=_animals[i]
			if not bool(animal.active) or (animal.node as Node3D).global_position.distance_to(_focus)>RANGE:
				_place(animal,i)
	for animal in _animals:
		if not bool(animal.active): continue
		var node: Node3D=animal.node
		var anchor: Vector2=animal.anchor
		var phase: float=animal.phase
		# Pause naturally; a creature never chases the player or leaves its reserved patch.
		var moving := sin(_clock*.29+phase)>-.22
		if moving:
			animal.travel=float(animal.travel)+delta*(.21 if animal.snake else .10)
			animal.animation_time=float(animal.animation_time)+delta
		var travel: float=animal.travel
		var p := anchor+Vector2(sin(travel+phase),cos(travel*.79+phase))*1.05
		# Placement reserves the entire 1.05 m territory plus the animal's body.
		if sample_ground:
			animal.height_previous=animal.height_current
			animal.height_target=float(_height.call(p))
		animal.height_current=lerpf(float(animal.height_previous),float(animal.height_target),clampf(_elapsed/TICK,0,1))
		node.position=Vector3(p.x,float(animal.height_current),p.y)
		if moving: node.rotation.y=atan2(-cos(travel+phase),sin(travel*.79+phase)*.79)
		if animal.snake: _animate_snake(animal,float(animal.animation_time))
		else: _animate_scorpion(animal,float(animal.animation_time))

func _place(animal: Dictionary, index: int) -> void:
	var node: Node3D=animal.node
	# Quantized origin keeps repeated streaming deterministic instead of scattering each frame.
	var cell := Vector2i(floori(_focus.x/24.0),floori(_focus.z/24.0))
	var rng := RandomNumberGenerator.new()
	rng.seed=absi(_seed+cell.x*8171+cell.y*2971+index*157)
	animal.active=false
	node.visible=false
	for attempt in 16:
		var angle := rng.randf_range(0,TAU)
		var p := Vector2(_focus.x,_focus.z)+Vector2(cos(angle),sin(angle))*rng.randf_range(7,27)
		if not _clear(p,1.65): continue
		var y := float(_height.call(p))
		if absf(y-_focus.y)>7.0: continue
		var separate := true
		for other in _animals:
			if other==animal or not other.active: continue
			if p.distance_to(other.anchor)<4.0: separate=false
		if not separate: continue
		animal.anchor=p
		animal.active=true
		animal.height_previous=y
		animal.height_target=y
		animal.height_current=y
		node.position=Vector3(p.x,y,p.y)
		node.reset_physics_interpolation()
		node.visible=true
		return

static func _clear(point: Vector2, radius: float) -> bool:
	if not FIELD.BOUNDS.grow(-radius).has_point(point) or not LAYOUT.road_clear(point,radius+1.0): return false
	if _floor_route.is_empty():
		_floor_route=FIELD.canyon_centerline(8.0)
		_access_route=FIELD.plateau_access(6.0)
	# Tiny harmless animals inhabit the sandy margins, never the ten-metre vehicle core
	# or the entire sixteen-metre ascending road. They do not need to stand on a cliff.
	if _route_distance(point,_floor_route)<5.0+radius: return false
	if _route_distance(point,_access_route)<FIELD.ACCESS_HALF_WIDTH+radius: return false
	return FIELD.normal_at(point).y>.82

static func _route_distance(point: Vector2,route: PackedVector3Array) -> float:
	var distance := INF
	for i in range(1,route.size()):
		var a := Vector2(route[i-1].x,route[i-1].z)
		var b := Vector2(route[i].x,route[i].z)
		distance=minf(distance,Geometry2D.get_closest_point_to_segment(point,a,b).distance_to(point))
	return distance

func _create(index: int) -> Dictionary:
	var node := Node3D.new()
	var snake := index%2==0
	node.name="CanyonSnake" if snake else "CanyonScorpion"
	node.visible=false
	node.set_meta("desert_wildlife",true)
	add_child(node)
	var body := _instances(node,"Body",_sphere_mesh(),18 if snake else 6)
	var part_mesh: Mesh
	if snake:
		part_mesh = _sphere_mesh()
	else:
		part_mesh = _limb_mesh()
	var parts := _instances(node,"Head" if snake else "LegsTailClaws",part_mesh,3 if snake else 25)
	var result := {"node":node,"snake":snake,"body":body,"parts":parts,"active":false,"anchor":Vector2.ZERO,"phase":float(index)*1.79,"travel":0.0,"animation_time":0.0,"height_previous":0.0,"height_target":0.0,"height_current":0.0}
	if snake: _animate_snake(result,0)
	else: _animate_scorpion(result,0)
	return result

static func _animate_snake(animal: Dictionary, time: float) -> void:
	var body: MultiMesh=animal.body
	var parts: MultiMesh=animal.parts
	var phase := time*3.2+float(animal.phase)
	for i in 18:
		var t := float(i)/17.0
		var p := Vector3(sin(t*TAU*1.3-phase)*.115*t,.044,-.49+t*1.05)
		var radius := lerpf(.042,.009,pow(t,2.2))
		body.set_instance_transform(i,Transform3D(Basis.from_scale(Vector3(radius,.029,.048)),p))
		body.set_instance_color(i,Color("524730") if i%4<2 else Color("97804c"))
	parts.set_instance_transform(0,Transform3D(Basis.from_scale(Vector3(.058,.034,.085)),Vector3(0,.044,-.53)))
	parts.set_instance_color(0,Color("665136"))
	for eye in 2:
		parts.set_instance_transform(eye+1,Transform3D(Basis.from_scale(Vector3.ONE*.008),Vector3(-.038+eye*.076,.070,-.56)))
		parts.set_instance_color(eye+1,Color("151413"))

static func _animate_scorpion(animal: Dictionary, time: float) -> void:
	var body: MultiMesh=animal.body
	var limbs: MultiMesh=animal.parts
	var phase := time*5.0+float(animal.phase)
	var shell := Color("68432c")
	body.set_instance_transform(0,Transform3D(Basis.from_scale(Vector3(.067,.040,.115)),Vector3(0,.072,.025)))
	body.set_instance_transform(1,Transform3D(Basis.from_scale(Vector3(.065,.035,.061)),Vector3(0,.075,-.083)))
	for claw in 2:
		var side := -1.0 if claw==0 else 1.0
		body.set_instance_transform(2+claw*2,Transform3D(Basis.from_scale(Vector3(.035,.023,.069)),Vector3(side*.144,.063,-.20)))
		body.set_instance_transform(3+claw*2,Transform3D(Basis.from_scale(Vector3(.018,.016,.052)),Vector3(side*.105,.063,-.21)))
	for i in 6: body.set_instance_color(i,shell)
	var part := 0
	for side in [-1.0,1.0]:
		for leg in 4:
			var z := -.075+float(leg)*.048
			var swing := sin(phase+float(leg)*2.0+side)*.020
			var knee := Vector3(side*(.125+swing),.044,z+.015)
			_segment(limbs,part,Vector3(side*.045,.073,z),knee,.010,shell)
			_segment(limbs,part+1,knee,Vector3(side*.177,.010,z+.045-swing),.006,shell)
			part+=2
		_segment(limbs,part,Vector3(side*.047,.07,-.11),Vector3(side*.11,.076,-.145),.016,shell)
		_segment(limbs,part+1,Vector3(side*.11,.076,-.145),Vector3(side*.144,.063,-.205),.013,shell)
		part+=2
	var tail := [Vector3(0,.07,.115),Vector3(.015,.12,.155),Vector3(.023,.20,.150),Vector3(.018,.27,.105),Vector3(.009,.28,.045),Vector3(0,.245,.005)]
	for i in 5:
		var sway := Vector3(sin(phase*.28)*.016,0,0)*float(i)/5.0
		_segment(limbs,20+i,tail[i]+sway,tail[i+1]+sway,.018-float(i)*.0025,Color("372820") if i==4 else shell)

static func _segment(mesh: MultiMesh,index: int,a: Vector3,b: Vector3,radius: float,color: Color) -> void:
	var up := (b-a).normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	if right.length_squared()<.1: right=Vector3.RIGHT
	var limb_basis := Basis(right*radius,up*a.distance_to(b),right.cross(up)*radius)
	mesh.set_instance_transform(index,Transform3D(limb_basis,(a+b)*.5))
	mesh.set_instance_color(index,color)

static func _instances(parent: Node3D,label: String,mesh: Mesh,count: int) -> MultiMesh:
	var data := MultiMesh.new()
	data.transform_format=MultiMesh.TRANSFORM_3D
	data.use_colors=true
	data.mesh=mesh
	data.instance_count=count
	var node := MultiMeshInstance3D.new()
	node.name=label
	node.multimesh=data
	if _material==null:
		_material=StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo=true
		_material.vertex_color_is_srgb=true
		_material.roughness=.94
	node.material_override=_material
	parent.add_child(node)
	return data

static func _sphere_mesh() -> SphereMesh:
	if _sphere==null:
		_sphere=SphereMesh.new()
		_sphere.radius=1
		_sphere.height=2
		_sphere.radial_segments=8
		_sphere.rings=4
	return _sphere

static func _limb_mesh() -> CylinderMesh:
	if _limb==null:
		_limb=CylinderMesh.new()
		_limb.top_radius=1
		_limb.bottom_radius=1
		_limb.height=1
		_limb.radial_segments=5
	return _limb
