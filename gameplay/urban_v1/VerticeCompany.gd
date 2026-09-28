extends Node3D
## Continuous, physical company: opening hours, resident staff and durable finds.
const ORIGIN := Vector3(-340,0,-80)
const FOOTPRINT := Rect2(-392,-112,108,112)
const ACTOR := preload("res://scripts/Actor.gd")
var session
var building: Node3D
var solids: Array[StaticBody3D] = []
var staff: Array[Dictionary] = []
var desk_staff: Array[Node3D] = []
var forklifts: Node
var clutter: Node3D
var secrets: Array[Dictionary] = []
var materials := {}
var gate: Node3D
var gate_amount := 0.0
var office_amount := 0.0
var dock_amounts: Array[float] = [0.0,0.0,0.0]
var scan := 0.0
var occupied := false
var _previous_shelter := false
var interior_camera: Camera3D
var movers: Array[Node3D] = []
var spreaders: Array[Node3D] = []
var lift_cylinders: Array[Node3D] = []
var booms: Array[Node3D] = []
var lamps: Array[OmniLight3D] = []
var region_active := true
var dressing: Node3D
var hatch: Node3D
var hatch_marker: Node2D
var hatch_busy := false
const HATCH_POINT := Vector3(-24,0,-15.7)

func _ready() -> void:
	name = "Vertice"
	position = ORIGIN
	building = preload("res://gameplay/urban_v1/PortDepotBuilding.gd").new()
	add_child(building)
	_build_yard()
	_build_staff()
	_build_secrets()
	dressing = load("res://gameplay/urban_v1/VerticeSiteDressing.gd").new()
	add_child(dressing)
	clutter = load("res://gameplay/urban_v1/VerticeOfficeClutter.gd").new()
	add_child(clutter)
	forklifts = load("res://gameplay/urban_v1/VerticeYardForklifts.gd").new()
	forklifts.company = self
	add_child(forklifts)
	_build_hatch()
	interior_camera = Camera3D.new()
	interior_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	interior_camera.size = 24
	interior_camera.far = 150
	add_child(interior_camera)
	set_physics_process(session != null)

func business_open() -> bool:
	if session == null or session.weather == null: return true
	var hour := fposmod(float(session.weather.time_of_day),1.0)*24.0
	return hour >= 8.0 and hour < 18.0

func set_region_active(active: bool) -> void:
	if region_active == active: return
	region_active = active
	visible = active
	for body in solids: body.collision_layer = 1 if active else 0
	for body in building.solids: body.collision_layer = 1 if active else 0
	dressing.set_region_active(active)
	clutter.set_region_active(active)
	forklifts.set_region_active(active)
	for entry in staff: entry.actor.collision_layer = 2 if active else 0

func inside(point: Vector3) -> bool:
	var p := point-ORIGIN
	return Rect2(-27.7,-19.7,55.9,37.5).has_point(Vector2(p.x,p.z)) or Rect2(27.8,0,13.9,29.8).has_point(Vector2(p.x,p.z))

func _build_yard() -> void:
	box("YardSurface",Vector3(0,-.10,24),Vector3(100,.20,108),"656b65")
	box("YardFinish",Vector3(0,.014,24),Vector3(100,.022,108),"656b65")
	# Solid fence panels use thin bars, with one simple collision each.
	_fence(Vector3(-50,0,-30),Vector3(50,0,-30))
	_fence(Vector3(-50,0,-30),Vector3(-50,0,78))
	_fence(Vector3(50,0,-30),Vector3(50,0,78))
	_fence(Vector3(-50,0,78),Vector3(-7,0,78))
	_fence(Vector3(7,0,78),Vector3(50,0,78))
	gate = Node3D.new()
	gate.name = "SlidingGate"
	gate.position = Vector3(0,0,78)
	add_child(gate)
	_fence(Vector3(-7,0,0),Vector3(7,0,0),gate)
	for x in [-7.4,7.4]: box("GatePost",Vector3(x,1.6,78),Vector3(.5,3.2,.6),"b4b4a2",true)
	# Glazed guard booth, walkable opening facing the truck gate.
	box("BoothRear",Vector3(14,1.4,70),Vector3(6,2.8,.2),"c2bda9",true)
	box("BoothSide",Vector3(17,1.4,73),Vector3(.2,2.8,6),"c2bda9",true)
	box("BoothFront",Vector3(14,1.4,76),Vector3(6,2.8,.2),"55686a",true)
	box("BoothRoof",Vector3(14,2.9,73),Vector3(6.6,.22,6.6),"34464b")
	box("BoothDesk",Vector3(15.8,.55,73),Vector3(1.2,1.1,2.4),"79664b",true)
	for x in [-40,-34,-28]:
		box("ParkingLine",Vector3(x,.04,66),Vector3(.1,.025,9),"c6c2a4")
	for x in [-18,0,18]:
		for side in [-1,1]: box("DockApproachStripe",Vector3(x+side*4.5,.04,27),Vector3(.10,.025,13),"d2b767")
	for z in range(-28,77,8): box("ConcreteJoint",Vector3(0,.028,z),Vector3(100,.004,.025),"5e655f")
	for x in range(-48,49,8): box("ConcreteJoint",Vector3(x,.028,24),Vector3(.025,.004,108),"5e655f")
	for z in range(36,51,2): box("PedestrianStripe",Vector3(35,.04,z),Vector3(2.8,.015,.4),"c6c2a4")
	for index in 3: _build_handler(index)
	for at in [Vector3(-42,5,58),Vector3(42,5,56)]:
		box("YardLightPole",Vector3(at.x,2.5,at.z),Vector3(.13,5,.13),"36454b",true)
		var light := OmniLight3D.new()
		light.position = at
		light.omni_range = 18
		light.light_energy = 1.3
		light.light_color = Color("f4d3a1")
		light.shadow_enabled = false
		add_child(light)
		lamps.append(light)
	# Wall/ceiling fittings use the shared nearby-light pool, not extra permanent
	# Light3D nodes. They leave the truck lanes and walking floor unchanged.
	for at in [Vector3(-18,4.3,19.1),Vector3(0,4.3,19.1),Vector3(18,4.3,19.1),Vector3(14,2.7,74.8),Vector3(31,3.1,71)]:
		var fitting := Node3D.new()
		fitting.name = "ExteriorTaskLight"
		fitting.position = at
		add_child(fitting)
		fitting.add_to_group(&"city_local_light_source")
		fitting.set_meta("local_light",{"range":18.0 if at.z<30 else 12.0,"energy":1.8,"color":Color("ffe0ad")})
		box("TaskLightHousing",at+Vector3(0,.06,0),Vector3(.8,.13,.32),"36454b")
		var lens := box("TaskLightLens",at,Vector3(.66,.05,.26),"f4dfb6")
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color("f4dfb6")
		glow.emission_enabled = true
		glow.emission = glow.albedo_color
		glow.emission_energy_multiplier = .65
		lens.material_override = glow

func _fence(a: Vector3,b: Vector3,parent: Node3D = self) -> void:
	var length := a.distance_to(b)
	var root := Node3D.new()
	root.position = (a+b)*.5
	root.rotation.y = atan2(-(b-a).z,(b-a).x)
	parent.add_child(root)
	var bars := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.035,2.5,.045)
	mesh.material = material("435454")
	multi.mesh = mesh
	multi.instance_count = ceili(length/.22)+1
	for i in multi.instance_count: multi.set_instance_transform(i,Transform3D(Basis(),Vector3(-length*.5+length*i/maxi(1,multi.instance_count-1),1.25,0)))
	bars.multimesh = multi
	root.add_child(bars)
	for y in [.3,2.2]: box("FenceRail",Vector3(0,y,0),Vector3(length,.065,.075),"435454",false,root)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length,2.5,.12)
	collision.shape = shape
	collision.position.y = 1.25
	body.add_child(collision)
	root.add_child(body)
	solids.append(body)

func _build_handler(index: int) -> void:
	# Yard reach-stacker built as a real machine: twin drive wheels under the
	# boom, steering axle under the counterweight, glazed cab, engine hood,
	# lift cylinder and a spreader with twistlocks. Only the chassis, weight and
	# cab collide; boom and spreader move with the unload cycle.
	var rig := Node3D.new()
	rig.name = "ReachStacker%d"%index
	rig.position = Vector3(-18+index*18,0,24)
	add_child(rig)
	movers.append(rig)
	var paint: String = ["d9a126","c9772b","d9a126"][index]
	box("Chassis",Vector3(0,.95,.3),Vector3(2.7,.7,6.0),paint,true,rig)
	box("FrameRail",Vector3(0,.55,.3),Vector3(2.2,.18,6.2),"2c3233",false,rig)
	box("Counterweight",Vector3(0,1.45,-2.75),Vector3(3.0,1.5,1.25),paint,true,rig)
	for i in 7:
		box("WeightChevron",Vector3(-1.2+i*.4,1.45,-3.385),Vector3(.16,1.35,.02),"1f2324",false,rig).rotation.z = .55
	box("RearBumper",Vector3(0,.72,-3.45),Vector3(3.0,.28,.2),"2c3233",false,rig)
	for x in [-1.2,1.2]: box("TailLamp",Vector3(x,1.95,-3.39),Vector3(.3,.14,.04),"lamp_red",false,rig)
	box("EngineHood",Vector3(.62,1.72,-1.15),Vector3(1.35,.85,2.1),paint,true,rig)
	for i in 5: box("HoodVent",Vector3(1.305,1.72,-1.9+i*.36),Vector3(.02,.5,.14),"1f2324",false,rig)
	_cyl(rig,Vector3(1.1,2.55,-1.85),.09,1.1,"2c3233")
	_cyl(rig,Vector3(1.1,3.12,-1.85),.11,.08,"1f2324")
	# Twin drive wheels up front carry the load; single steer wheels at the rear.
	for side in [-1.0,1.0]:
		for offset in [0.0,.46]:
			_wheel(rig,Vector3(side*(1.42+offset),.82,2.2),.82,.42)
		_wheel(rig,Vector3(side*1.45,.68,-1.95),.68,.4)
		box("Fender",Vector3(side*1.65,1.72,2.2),Vector3(1.0,.08,1.9),"1f2324",false,rig)
		box("Fender",Vector3(side*1.45,1.44,-1.95),Vector3(.55,.08,1.55),"1f2324",false,rig)
		box("SideStripe",Vector3(side*1.355,1.05,.3),Vector3(.02,.12,4.6),"1f2324",false,rig)
	# Cab: dark frame with glass panels, pillars, roof, beacon and access ladder.
	var cab := Vector3(-.78,0,.55)
	box("Cab",cab+Vector3(0,1.95,0),Vector3(1.3,1.45,1.6),"glass",true,rig)
	box("CabBase",cab+Vector3(0,1.3,0),Vector3(1.42,.22,1.72),"2c3233",false,rig)
	for x in [-.66,.66]:
		for z in [-.8,.8]: box("CabPillar",cab+Vector3(x,1.97,z),Vector3(.08,1.45,.08),"2c3233",false,rig)
	box("CabRoof",cab+Vector3(0,2.74,0),Vector3(1.55,.12,1.95),paint,false,rig)
	box("CabSeat",cab+Vector3(.1,1.72,-.25),Vector3(.55,.55,.5),"1f2324",false,rig)
	box("Joystick",cab+Vector3(.42,1.75,.1),Vector3(.06,.28,.06),"1f2324",false,rig)
	_cyl(rig,cab+Vector3(.3,2.9,-.4),.12,.2,"lamp_amber")
	for y in [.45,.8,1.15]: box("LadderRung",cab+Vector3(-.82,y,.25),Vector3(.3,.04,.5),"8d9596",false,rig)
	box("Mirror",cab+Vector3(-.95,2.3,.95),Vector3(.05,.3,.2),"1f2324",false,rig)
	for x in [-.45,.45]: box("WorkLight",cab+Vector3(x,2.83,.95),Vector3(.2,.12,.08),"lamp_white",false,rig)
	# Telescopic boom: outer and inner sections stretch together from the pivot.
	var boom := Node3D.new()
	boom.name = "Boom"
	rig.add_child(boom)
	box("BoomOuter",Vector3(0,0,.2),Vector3(.78,.66,.6),paint,false,boom)
	box("BoomInner",Vector3(0,0,-.2),Vector3(.56,.46,.62),paint,false,boom)
	box("BoomHose",Vector3(-.25,.36,.05),Vector3(.05,.05,.9),"1f2324",false,boom)
	box("BoomStripe",Vector3(.395,0,.2),Vector3(.02,.18,.58),"1f2324",false,boom)
	booms.append(boom)
	box("BoomPivot",Vector3(.4,2.6,-.8),Vector3(.9,.7,.7),"2c3233",false,rig)
	var cylinder := Node3D.new()
	cylinder.name = "LiftCylinder"
	rig.add_child(cylinder)
	box("CylinderBarrel",Vector3(0,0,.2),Vector3(.3,.3,.6),"2c3233",false,cylinder)
	box("CylinderRod",Vector3(0,0,-.2),Vector3(.16,.16,.62),"c8cdcd",false,cylinder)
	lift_cylinders.append(cylinder)
	# Spreader: main beam, telescopic end frames, twistlock corners, rotator.
	var spreader := Node3D.new()
	spreader.name = "Spreader"
	spreader.position = Vector3(0,3.05,5.2)
	rig.add_child(spreader)
	box("SpreaderBeam",Vector3.ZERO,Vector3(5.2,.26,.42),"e0b43a",false,spreader)
	for x in [-2.75,2.75]:
		box("SpreaderEnd",Vector3(x,0,0),Vector3(.32,.24,2.45),"e0b43a",false,spreader)
		box("SpreaderSlide",Vector3(x*.8,.05,0),Vector3(.9,.18,.3),"8d9596",false,spreader)
		for z in [-1.15,1.15]: box("Twistlock",Vector3(x,-.2,z),Vector3(.24,.18,.24),"2c3233",false,spreader)
	box("RotatorHead",Vector3(0,.3,0),Vector3(.9,.36,.9),"2c3233",false,spreader)
	box("RotatorRing",Vector3(0,.12,0),Vector3(1.2,.08,1.2),"8d9596",false,spreader)
	spreaders.append(spreader)
	_align_boom(index)

func _wheel(parent: Node3D,at: Vector3,radius: float,width: float) -> void:
	var tire := _cyl(parent,at,radius,width,"1b1f20")
	tire.rotation.z = PI*.5
	var rim := _cyl(parent,at+Vector3(signf(at.x)*(width*.5+.005),0,0),radius*.52,.03,"b8bcb4")
	rim.rotation.z = PI*.5
	var hub := _cyl(parent,at+Vector3(signf(at.x)*(width*.5+.03),0,0),radius*.18,.06,"2c3233")
	hub.rotation.z = PI*.5

func _cyl(parent: Node3D,at: Vector3,radius: float,height: float,color: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 14
	mesh.mesh = shape
	mesh.material_override = material(color)
	mesh.position = at
	parent.add_child(mesh)
	return mesh

func _align_boom(index: int) -> void:
	var start := movers[index].to_global(Vector3(.4,2.6,-.8))
	var end := spreaders[index].global_position+Vector3.UP*.3
	var boom := booms[index]
	boom.global_position = (start+end)*.5
	boom.look_at(end,Vector3.UP)
	boom.scale.z = start.distance_to(end)
	# Lift cylinder from the front frame to about a third of the boom.
	var base := movers[index].to_global(Vector3(.4,1.3,1.6))
	var joint := start.lerp(end,.36)
	var cylinder := lift_cylinders[index]
	cylinder.global_position = (base+joint)*.5
	cylinder.look_at(joint,Vector3.UP)
	cylinder.scale.z = base.distance_to(joint)

func _build_staff() -> void:
	# Operator routes use free strips: warehouse aisle z-8.5 between rack rows,
	# the documented z12 crossing, and the flanks of the yard cargo islands.
	# Truck lanes (x-37, z34 dock row, exit diagonal) and forklift bays stay clear.
	var specs := [
		{"point":Vector3(10,.1,73),"route":[Vector3(10,0,73),Vector3(10,0,66)],"guard":true},
		{"point":Vector3(-43,.1,44),"route":[Vector3(-43,0,44),Vector3(-43,0,-24),Vector3(44,0,-24),Vector3(44,0,44),Vector3(44,0,56),Vector3(-43,0,56)],"guard":true},
		{"point":Vector3(24,.1,45),"route":[Vector3(24,0,45),Vector3(38,0,45)],"guard":false},
		{"point":Vector3(0,.1,3),"route":[Vector3(0,0,3),Vector3(0,0,-12)],"guard":false},
		{"point":Vector3(35,.1,20),"route":[Vector3(35,0,20),Vector3(35,0,8),Vector3(30.5,0,8)],"guard":false,"office":true},
		{"point":Vector3(-13,.1,-8.5),"route":[Vector3(-13,0,-8.5),Vector3(13,0,-8.5)],"guard":false},
		{"point":Vector3(20,.1,12),"route":[Vector3(20,0,12),Vector3(-22,0,12)],"guard":false},
		{"point":Vector3(-27,.1,41),"route":[Vector3(-27,0,41),Vector3(-27,0,51),Vector3(-12,0,51),Vector3(-27,0,51)],"guard":false},
		{"point":Vector3(12.5,.1,42),"route":[Vector3(12.5,0,42),Vector3(12.5,0,52)],"guard":false},
		{"point":Vector3(38.5,.1,6),"route":[Vector3(38.5,0,6),Vector3(31,0,6),Vector3(31,0,11.5)],"guard":false,"office":true}]
	for i in specs.size():
		var npc = ACTOR.new()
		var office: bool = specs[i].get("office",false)
		npc.name = "VerticeGuard%d"%i if specs[i].guard else ("VerticeOfficeClerk%d"%i if office else "VerticeOperator%d"%i)
		npc.identity = 800+i
		npc.controlled_automatically = true
		npc.position = specs[i].point
		npc.speed = 1.15
		add_child(npc)
		npc.set_physics_process(false)
		for old in npc.visual.get_children():
			npc.visual.remove_child(old)
			old.queue_free()
		var model: Node3D
		if specs[i].guard:
			model = preload("res://assets/CivilianModel.gd").new()
			model.appearance_locked = true
			model.coat_color = Color("283c4a")
			model.pants_color = Color("23313a")
			model.wardrobe_overrides = {"top":1,"bottom":0,"shoe":1,"hat":1,"backpack":false,"bag":0}
		elif office:
			model = preload("res://assets/CivilianModel.gd").new()
			model.appearance_locked = true
			model.appearance_variant = 60+i*7
			model.coat_color = Color("d9d4c4") if i%2 == 0 else Color("5d7186")
			model.pants_color = Color("2f3440")
			model.wardrobe_overrides = {"top":0,"bottom":0,"shoe":0,"hat":0,"backpack":false,"bag":0}
		else:
			model = preload("res://gameplay/routines_v1/DockWorkerModel.gd").new()
			model.worker_index = i
		npc.visual.add_child(model)
		# Actor turns `visual` so its -Z follows the walk; CivilianModel's chest
		# faces +Z. Without this half turn every staff member walked backwards.
		model.rotation.y = PI
		model.set_process(false)
		npc.set_meta("vertice_staff",true)
		staff.append({"actor":npc,"model":model,"route":specs[i].route,"waypoint":0,"guard":specs[i].guard,"office":office,"pause":2.0+i*.7})
	# Desk staff sit still and type; plain models, no walking body to push around.
	for z in [14.0,21.0]:
		var seated := preload("res://assets/CivilianModel.gd").new()
		seated.name = "VerticeDeskClerk"
		seated.appearance_locked = true
		seated.appearance_variant = 90+int(z)
		seated.coat_color = Color("8a4f4a") if z < 15 else Color("e3ddcc")
		seated.pants_color = Color("2b3140")
		seated.wardrobe_overrides = {"top":0,"bottom":0,"shoe":0,"hat":0,"backpack":false,"bag":0}
		seated.sit_amount = 1.0
		seated.seat_height = .5
		seated.position = Vector3(39.3,0,z+1.05)
		seated.rotation.y = PI
		add_child(seated)
		var keys := Vector3(39.3,.9,z+.22)
		seated.hand_provider = func() -> Array: return [to_global(keys+Vector3(-.16,0,0)),to_global(keys+Vector3(.16,0,0))]
		seated.set_process(false)
		desk_staff.append(seated)

func _build_secrets() -> void:
	# Collections are ordinary physical objects; the hidden office envelope and
	# rear-rack cash tin have independent, durable economy receipts.
	for spec in [{"id":"vertice_office_envelope","point":Vector3(35,.05,3),"amount":700}, {"id":"vertice_rear_cash","point":Vector3(0,.05,-16),"amount":1800}]:
		var object := box("HiddenFind",spec.point+Vector3(0,.12,0),Vector3(.35,.24,.25),"9a7850")
		secrets.append({"id":spec.id,"point":spec.point,"amount":spec.amount,"visual":object})

func _build_hatch() -> void:
	hatch = Node3D.new()
	hatch.name = "HiddenFloorHatch"
	hatch.position = HATCH_POINT
	add_child(hatch)
	box("HatchFrame",Vector3(0,.055,0),Vector3(1.7,.045,1.7),"343d3d",false,hatch)
	box("SteelHatch",Vector3(0,.085,0),Vector3(1.5,.04,1.5),"606b65",false,hatch)
	for x in [-.55,.55]:
		box("HatchHinge",Vector3(x,.12,-.65),Vector3(.2,.06,.12),"938c72",false,hatch)
		for z in [-.55,.55]: box("RecessedBolt",Vector3(x,.113,z),Vector3(.045,.015,.045),"252f30",false,hatch)
	box("HatchHandle",Vector3(0,.135,.45),Vector3(.32,.04,.09),"283536",false,hatch)
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	hatch_marker = preload("res://ui/DoorAccessMarker.gd").new()
	layer.add_child(hatch_marker)
	hatch_marker.hide()
	hatch_marker.update_position = _update_hatch_marker

func _hatch_reachable() -> bool:
	if session == null or not session.ready_for_play or not session.state.place_id.is_empty() or session.state.region_id != "harbor": return false
	var player = session.world.player
	return not hatch_busy and not player.dead and not player.input_locked and not session.world.driving.occupied and not session.is_transition_blocked() and player.global_position.distance_to(ORIGIN+HATCH_POINT)<1.65

func _update_hatch_marker() -> void:
	hatch_marker.visible = _hatch_reachable() and not session.modal
	if not hatch_marker.visible: return
	var camera := get_viewport().get_camera_3d()
	var point := ORIGIN+HATCH_POINT+Vector3.UP*.15
	hatch_marker.visible = is_instance_valid(camera) and not camera.is_position_behind(point)
	if hatch_marker.visible: hatch_marker.position = camera.unproject_position(point)

func _enter_hideout() -> void:
	hatch_busy = true
	_set_inside(false)
	await session.enter_place("vertice_undercroft",true,"vertice_undercroft")
	hatch_busy = false

func _physics_process(delta: float) -> void:
	if session == null or not session.ready_for_play: return
	var player = session.world.player
	if not is_instance_valid(player): return
	var harbor: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
	var near: bool = harbor and player.global_position.distance_to(ORIGIN+Vector3(0,0,24)) < 150
	var truck_near := false
	if harbor:
		for truck in get_tree().get_nodes_in_group("port_logistics_truck"):
			if is_instance_valid(truck) and truck.health>0 and truck.global_position.distance_to(ORIGIN+Vector3(0,0,50))<60: truck_near = true
	visible = harbor
	if not near and not truck_near:
		building.set_lights_active(false)
		for entry in staff:
			entry.actor.set_physics_process(false)
			entry.model.set_process(false)
		for seated in desk_staff: seated.set_process(false)
		forklifts.tick(false)
		_set_inside(false)
		for light in lamps: light.visible = false
		return
	var p: Vector3 = player.global_position-ORIGIN
	building.set_lights_active(near)
	var open := business_open()
	# Exit and an occupied threshold remain clear even after the business closes.
	var exiting := p.x > -50 and p.x < 50 and p.z < 78 and p.z > -30
	var gate_clearance := absf(p.x)<9 and absf(p.z-78)<4 and gate_amount>.1
	var target := 1.0 if open or exiting or gate_clearance else 0.0
	for truck in get_tree().get_nodes_in_group("port_logistics_truck"):
		if is_instance_valid(truck) and truck.health>0 and truck.global_position.distance_to(ORIGIN+Vector3(0,0,78))<15: target = 1.0
	gate_amount = move_toward(gate_amount,target,delta*.7)
	gate.position.x = -14.5*gate_amount
	var interior := inside(player.global_position)
	_set_inside(interior)
	var at_door := p.distance_to(Vector3(35,0,30))<3
	var threshold_occupied := absf(p.x-35)<1.7 and absf(p.z-30)<1.3 and office_amount>.4
	office_amount = move_toward(office_amount,1.0 if (at_door and (open or interior)) or threshold_occupied else 0.0,delta*2)
	building.set_office_open(office_amount)
	for i in 3:
		var keep_open := open or (dock_amounts[i]>.01 and dock_occupied(i))
		dock_amounts[i] = move_toward(dock_amounts[i],1.0 if keep_open else 0.0,delta*.65)
		building.set_dock_open(i,dock_amounts[i])
	if occupied:
		var focus := Vector3(clampf(p.x,-18,37),0,clampf(p.z,-12,24))
		interior_camera.position = focus+Vector3(0,20,17)
		interior_camera.look_at(to_global(focus+Vector3.UP*.8))
	forklifts.tick(near)
	for seated in desk_staff:
		seated.visible = open
		seated.set_process(near and open)
	for entry in staff:
		var npc = entry.actor
		entry.model.set_process(near)
		if npc.dead: continue
		npc.set_physics_process(near)
		if not near: continue
		var region = session.controller.regions.get("harbor")
		if not is_instance_valid(region) or not region.prepare_collision_at(npc.global_position):
			npc.set_physics_process(false)
			continue
		if not entry.guard and not open:
			npc.automatic_direction = Vector3.ZERO
			continue
		entry.pause = maxf(0,entry.pause-delta)
		var goal: Vector3 = ORIGIN+entry.route[entry.waypoint]
		var offset: Vector3 = goal-npc.global_position
		offset.y = 0
		if offset.length()<.6:
			entry.waypoint = (entry.waypoint+1)%entry.route.size()
			entry.pause = 3.5
		npc.automatic_direction = offset.normalized() if entry.pause<=0 else Vector3.ZERO
	scan -= delta
	if scan>0: return
	scan = .25
	for light in lamps: light.visible = session.weather.time_of_day<.25 or session.weather.time_of_day>.75
	if not occupied or player.dead: return
	for secret in secrets:
		var found: bool = session.state.economy.snapshot().transactions.has("reward:"+secret.id)
		secret.visual.visible = not found
		if not found and p.distance_to(secret.point)<1.0:
			var receipt: Dictionary = session.state.economy.grant_world_reward({"id":secret.id,"kind":"cash","amount":secret.amount})
			if receipt.ok:
				secret.visual.hide()
				session.save_game()
				session.show_message("Encontrou R$ %d."%secret.amount)

func dock_occupied(index: int) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var volume := BoxShape3D.new()
	volume.size = Vector3(8.6,5.7,1.8)
	query.shape = volume
	query.transform.origin = ORIGIN+Vector3(-18+index*18,2.8,18)
	query.collision_mask = 6
	return not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _set_inside(value: bool) -> void:
	if occupied == value: return
	occupied = value
	building.set_cutaway(value)
	if is_instance_valid(dressing): dressing.set_cutaway(value)
	if value:
		_previous_shelter = session.world.player.get_meta("mountain_shelter",false)
		# Shared native weather uses this legacy-named shelter flag in Harbor too.
		session.world.player.set_meta("mountain_shelter",true)
		interior_camera.make_current()
		session.world.player.camera = interior_camera
	elif session != null and is_instance_valid(session.world.camera):
		session.world.player.set_meta("mountain_shelter",_previous_shelter)
		session.world.camera.make_current()
		session.world.player.camera = session.world.camera
	if session != null and session.weather != null: session.weather._update()

func nearest_action() -> Dictionary:
	if session == null or session.state.region_id != "harbor" or session.world.driving.occupied: return {}
	if _hatch_reachable(): return {"id":"urban_v1","target":"vertice_hatch","label":"","silent":true,"position":ORIGIN+HATCH_POINT}
	if not session.state.place_id.is_empty(): return {}
	for entry in staff:
		if not entry.actor.dead and session.world.player.global_position.distance_to(entry.actor.global_position)<2:
			return {"id":"urban_v1","target":"vertice_staff","label":"Conversar","position":entry.actor.global_position}
	return {}

func perform(target: String) -> bool:
	if target == "vertice_hatch":
		if not _hatch_reachable() or session.modal: return false
		_enter_hideout()
		return true
	if target != "vertice_staff" or nearest_action().is_empty(): return false
	var speaker := "GUARDA"
	for entry in staff:
		if not entry.actor.dead and session.world.player.global_position.distance_to(entry.actor.global_position)<2:
			speaker = "GUARDA" if entry.guard else ("FUNCIONÁRIO" if entry.office else "OPERADOR")
			break
	session.show_message(speaker+": O expediente é das 8h às 18h. Mantenha a passagem dos caminhões livre." if business_open() else speaker+": Estamos fechados. Abrimos às 8h.")
	return true

func unload_pose(index: int,cargo: Node3D,from: Vector3,fraction: float) -> void:
	var target := ORIGIN+Vector3(-18+index*18,.18,28.5)
	var raised := Vector3(from.x,4.7,from.z)
	if fraction<.3: cargo.global_position = from.lerp(raised,smoothstep(0,.3,fraction))
	elif fraction<.7: cargo.global_position = raised.lerp(Vector3(target.x,4.7,target.z),smoothstep(.3,.7,fraction))
	else: cargo.global_position = Vector3(target.x,4.7,target.z).lerp(target,smoothstep(.7,1,fraction))
	cargo.global_rotation.y = 0
	spreaders[index].global_position = cargo.global_position+Vector3.UP*2.55
	_align_boom(index)

func material(color: String) -> Material:
	if not materials.has(color):
		var result := StandardMaterial3D.new()
		match color:
			"glass":
				result.albedo_color = Color(.36,.5,.54,.55)
				result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				result.roughness = .12
				result.metallic = .3
			"lamp_red", "lamp_amber", "lamp_white":
				result.albedo_color = {"lamp_red":Color("c8231c"),"lamp_amber":Color("f29a1d"),"lamp_white":Color("f4ead0")}[color]
				result.emission_enabled = true
				result.emission = result.albedo_color
				result.emission_energy_multiplier = .8
			_:
				result.albedo_color = Color(color)
				result.roughness = .8
		materials[color] = result
	return materials[color]

func box(id: String,at: Vector3,size: Vector3,color: String,solid := false,parent: Node3D = self) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = id
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material(color)
	mesh.position = at
	parent.add_child(mesh)
	if solid:
		mesh.set_meta("interior_solid_id",id)
		var body := StaticBody3D.new()
		body.name = id+"Solid"
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var volume := BoxShape3D.new()
		volume.size = size
		collision.shape = volume
		body.add_child(collision)
		mesh.add_child(body)
		solids.append(body)
	return mesh
