extends Node3D
## Two concrete barriers leave a passable lane with retractable tire spikes.
## The sweep tests wheel trajectories, so even fast cars cannot skip the strip.
const TIRES := preload("res://gameplay/police_response/ground/TirePuncture.gd")
const ART := preload("res://gameplay/police_response/ground/PoliceGroundModels.gd")
var age := 0.0
var width := 8.0
var strip_width := 3.6
var armed := false
var spikes: MultiMeshInstance3D
var _last_target := 0
var _previous_wheels: Array[Vector3] = []

func build(road_width: float) -> void:
	width = clampf(road_width, 6.0, 14.0)
	strip_width = minf(3.8, width * .52)
	var shoulder := (width-strip_width)*.5
	for side in [-1.0,1.0]:
		var center: float = side * (strip_width*.5+shoulder*.5)
		var body := StaticBody3D.new()
		body.name = "ConcreteBarrier"
		body.collision_layer = 1
		body.collision_mask = 7
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(shoulder,.88,.7)
		shape.shape = box
		shape.position = Vector3(center,.44,0)
		body.add_child(shape)
		add_child(body)
		ART._box(body,"Concrete",Vector3(center,.44,0),box.size,Color("a8afb0"))
		ART._box(body,"ReflectiveBand",Vector3(center,.60,-.358),Vector3(shoulder,.13,.016),Color("e0b537"))
		ART._box(self,"WarningLamp",Vector3(center,.95,0),Vector3(.18,.13,.15),Color("e8a027"),"bar_left")
	ART._box(self,"SpikeMat",Vector3(0,.035,0),Vector3(strip_width,.06,.56),Color("272c2c"))
	spikes = MultiMeshInstance3D.new()
	spikes.name = "RetractableSpikes"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var spike := CylinderMesh.new()
	spike.top_radius = 0
	spike.bottom_radius = .045
	spike.height = .20
	spike.radial_segments = 4
	multimesh.mesh = spike
	multimesh.instance_count = int(strip_width/.18)*2
	for index in multimesh.instance_count:
		multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(-strip_width*.5+.12+float(index/2)*.18,.13,-.15 if index%2 == 0 else .15)))
	spikes.multimesh = multimesh
	spikes.material_override = ART._material(Color("b9c4c8"))
	add_child(spikes)
	set_armed(false)

func set_armed(value: bool) -> void:
	armed = value
	if is_instance_valid(spikes): spikes.visible = value

func sample_target(car: CharacterBody3D, may_puncture: bool) -> bool:
	if not is_instance_valid(car):
		_previous_wheels.clear()
		_last_target = 0
		set_armed(false)
		return false
	set_armed(may_puncture and global_position.distance_to(car.global_position) < 22.0)
	var current: Array[Vector3] = []
	for x in [-float(car.half_width)*.78,float(car.half_width)*.78]:
		for z in [-float(car.half_length)*.62,float(car.half_length)*.62]:
			current.append(to_local(car.to_global(Vector3(x,.1,z))))
	if _last_target != car.get_instance_id():
		_previous_wheels.assign(current)
		_last_target = car.get_instance_id()
	var crossed := false
	for index in current.size():
		if wheel_crosses_strip(_previous_wheels[index],current[index],strip_width): crossed = true
	_previous_wheels.assign(current)
	if armed and crossed: return TIRES.puncture(car, 4)
	return false

static func wheel_crosses_strip(previous: Vector3, current: Vector3, span: float) -> bool:
	if minf(previous.y,current.y) > .65 or maxf(previous.y,current.y) < -.35: return false
	if absf(current.z) <= .32 and absf(current.x) <= span*.5: return true
	if previous.z * current.z > 0.0 or is_equal_approx(previous.z,current.z): return false
	var t := -previous.z/(current.z-previous.z)
	return absf(lerpf(previous.x,current.x,t)) <= span*.5
