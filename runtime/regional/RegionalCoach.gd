extends "res://scripts/Vehicle.gd"
## Um serviço programado admitido. O dono do transporte avança o motorista nativo;
## os ocupantes sentados são rigs 3D reais que dividem o buffer de profundidade do mundo.
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const PASSENGER_FOOT := Vector3(.70,.60,-1.65)
const WINDOW_EYE := Vector3(.12,2.05,2.85)
var passengers: Array[Node3D] = []
var driver: Node3D
var doors := 0.0
var _door: MeshInstance3D
var _materials: Dictionary = {}

func _ready() -> void:
	archetype="route_city"
	vehicle_id="regional_coach"
	health=500; max_health=500
	half_width=1.18; half_length=3.85; body_height=2.9
	collision_layer=4; collision_mask=7; floor_snap_length=.5
	shape=CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size=Vector3(half_width*2,body_height,half_length*2)
	shape.shape=hull; shape.position.y=body_height*.5
	add_child(shape)
	rotation_shape.size=hull.size-Vector3(0,.15,0)
	sensor_shape.size=Vector3(hull.size.x+.07,1.2,1)
	set_meta("gameplay_role","vehicle")
	set_meta("regional_coach",true)
	add_to_group("public_transport_vehicle")
	visual=Node3D.new(); visual.name="CoachCabin"; add_child(visual)
	_build_body()
	_build_occupants()
	# Existing bus light profile, day/night control and bounded beam selection.
	ensure_equipment(get_parent())
	equipment.input_enabled=false

func _physics_process(_delta: float) -> void:
	pass # O RegionalCoachTransit é o único agendador de física.

func set_service_route(value: Curve3D) -> void:
	_release_junction()
	route=value
	route.set_meta("traffic_open",true)
	route_distance=0.0
	speed=0.0
	horizontal_velocity=Vector3.ZERO
	traffic=true

func advance(delta: float) -> void:
	if route==null or doors>0: return
	super._physics_process(delta)

func arrived() -> bool:
	if route==null or absf(speed)>=.35: return false
	# A porta/frente chega a uma baia antes do centro do chassi. Um veículo na fila
	# além da baia não pode impedir a atracação quando este ônibus já está lá.
	var length := route.get_baked_length()
	var docking_distance := half_length+1.5
	if route_distance<length-docking_distance: return false
	var separation := global_position-route.sample_baked(length,true)
	separation.y=0.0
	return separation.length()<=docking_distance

func set_doors(value: float) -> void:
	doors=clampf(value,0,1)
	if is_instance_valid(_door): _door.position.z=-2.85+doors*.80

func seat_player(actor) -> void:
	actor.visual.rotation=Vector3.ZERO
	var pelvis: Vector3 = actor.pose_seated_base(.05)
	actor.visual.position=Vector3(0,.47,0)-pelvis
	actor.pose_seated_limbs({"Left":Vector3(-.16,.04,-.52),"Right":Vector3(.16,.04,-.52)},
		{"Left":Transform3D(Basis.IDENTITY,Vector3(-.24,.79,-.25)),"Right":Transform3D(Basis.IDENTITY,Vector3(.24,.79,-.25))})
	follow_player(actor)

func follow_player(actor) -> void:
	actor.global_transform=global_transform
	actor.global_position=to_global(PASSENGER_FOOT)
	actor.velocity=Vector3.ZERO
	actor.last_position=actor.global_position
	actor.show()

func _material(key: String, color: Color, roughness := .65) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color=color; result.roughness=roughness
	if color.a<1:
		result.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		result.cull_mode=BaseMaterial3D.CULL_DISABLED
	_materials[key]=result
	return result

func _box(label: String, point: Vector3, size: Vector3, key: String, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name=label; mesh.position=point
	var box := BoxMesh.new(); box.size=size
	mesh.mesh=box; mesh.material_override=_material(key,color)
	visual.add_child(mesh)
	return mesh

func _build_body() -> void:
	var ivory := Color("e6e4db")
	var paint := Color("286b79")
	var dark := Color("28373d")
	var glass := Color(.27,.46,.52,.17)
	_box("Floor",Vector3(0,.49,0),Vector3(2.36,.22,7.70),"floor",dark)
	_box("Roof",Vector3(0,2.81,0),Vector3(2.36,.18,7.70),"ivory",ivory)
	_box("Rear",Vector3(0,1.36,3.76),Vector3(2.36,1.55,.16),"paint",paint)
	_box("RearGlass",Vector3(0,2.22,3.77),Vector3(2.18,.91,.04),"glass",glass)
	_box("Nose",Vector3(0,.95,-3.76),Vector3(2.36,.98,.16),"paint",paint)
	_box("Windshield",Vector3(0,2.02,-3.78),Vector3(2.18,1.24,.04),"glass",glass)
	_box("Dash",Vector3(0,1.15,-3.40),Vector3(2.10,.32,.43),"trim",dark)
	for side in [-1.0,1.0]:
		_box("SideLower",Vector3(side*1.14,.98,0),Vector3(.08,.81,7.54),"paint",paint)
		_box("WindowSill",Vector3(side*1.14,1.39,0),Vector3(.10,.09,7.54),"ivory",ivory)
		_box("SideGlazing",Vector3(side*1.145,2.06,0),Vector3(.025,1.27,7.48),"glass",glass)
		for z in [-3.70,-2.25,-.78,.78,2.25,3.70]:
			_box("Pillar",Vector3(side*1.15,2.07,z),Vector3(.10,1.29,.075),"ivory",ivory)
		for z in [-2.60,2.45]:
			var pivot := Node3D.new(); pivot.position=Vector3(side*1.14,.43,z)
			pivot.set_meta("front",z<0); visual.add_child(pivot); wheels.append(pivot)
			var wheel := MeshInstance3D.new()
			var tire := CylinderMesh.new(); tire.top_radius=.43; tire.bottom_radius=.43; tire.height=.20; tire.radial_segments=16
			wheel.mesh=tire; wheel.rotation.z=PI*.5
			wheel.material_override=_material("rubber",Color("1d2225")); pivot.add_child(wheel)
	_door=_box("BoardingDoor",Vector3(1.19,1.39,-2.85),Vector3(.04,1.56,.78),"glass",glass)
	for z in [-1.65,-.20,1.25,2.65]:
		for side in [-1.0,1.0]: _seat(Vector3(side*.70,.60,z))
	_seat(Vector3(-.65,.60,-2.85))
	for side in [-1.0,1.0]:
		var lamp := _box("Headlamp",Vector3(side*.82,.95,-3.86),Vector3(.38,.18,.035),"lamp",Color("efe6be"))
		lamp.set_meta("coupe_damage_material_key","headlight")
		var tail := _box("Tail",Vector3(side*.91,1.00,3.86),Vector3(.20,.33,.035),"tail",Color("ad3932"))
		tail.set_meta("coupe_damage_material_key","tail")

func _seat(foot: Vector3) -> void:
	_box("SeatBase",foot+Vector3(0,.24,.06),Vector3(.32,.48,.32),"trim",Color("28373d"))
	_box("SeatCushion",foot+Vector3(0,.43,0),Vector3(.62,.12,.66),"cloth",Color("35576d"))
	_box("SeatBack",foot+Vector3(0,.85,.32),Vector3(.62,.83,.13),"cloth",Color("35576d"))

func _occupant(foot: Vector3, identity: int) -> Node3D:
	var person := CIVILIAN.new()
	person.appearance_locked=true; person.appearance_variant=identity
	person.coat_color=[Color("846149"),Color("526886"),Color("8a5267"),Color("71816b")][identity%4]
	person.position=foot; person.rotation.y=PI
	person.sit_amount=1.0; person.seat_height=.48
	visual.add_child(person)
	person._pose(0.0)
	person.set_process(false)
	return person

func _build_occupants() -> void:
	driver=_occupant(Vector3(-.65,.60,-2.85),820)
	driver.name="CoachDriver"
	for index in 6:
		var row: int = floori(float(index)/2.0)
		var foot := Vector3(-.70 if index%2==0 else .70,.60,[-.20,1.25,2.65][row])
		var person := _occupant(foot,821+index)
		person.name="Passenger%d" % index
		passengers.append(person)
