extends "res://prototypes/living_cast/CoupeDamageModel.gd"

## Native fleet art in metres, front = -Z. No textures, external models or per
## frame mesh generation. Fork/fender rotate with steering; tires spin alone.
var style := "urban"
var _leg_parts: Array[Dictionary] = []
var _arm_parts: Array[Dictionary] = []
var rider: Node3D
var dante_rider: Node3D
var dante_helmet_state: Node
var left_leg: Node3D
var right_leg: Node3D
var stand: Node3D
var rider_jacket: StandardMaterial3D
var rider_helmet: StandardMaterial3D
var lean := 0.0
var _foot_down := 0.0
var _front_z := -0.80
var _rear_z := 0.76
var _radius := 0.31
var _handle_y := 0.98
var _handle_z := -0.48
var _seat_y := 0.78

func _ready() -> void:
	super._ready()
	for part in originals.keys():
		if part.has_meta("wheel_center"): originals.erase(part)
	for part in lamp_sources:
		if is_zero_approx(float(lamp_sources[part].position.x)):
			lamp_sources[part].index = 0

func build() -> void:
	set_meta("vehicle_kind", "motorcycle")
	paint = mat("paint", "c7313a", 0.45, 0.24)
	var rubber := mat("rubber", "161b20", 0.0, 0.92)
	var chrome := mat("chrome", "b5c4ce", 0.8, 0.22)
	var alloy := mat("alloy", "56606b", 0.7, 0.35)
	var black := mat("engine", "292e33", 0.55, 0.56)
	var leather := mat("leather", "29292c", 0.0, 0.85)
	if style == "cruiser":
		_front_z = -1.03
		_rear_z = 0.82
		_radius = 0.34
		_seat_y = 0.70
		_handle_y = 1.10
		_handle_z = -0.28
	elif style == "sport":
		_front_z = -0.85
		_rear_z = 0.78
		_handle_y = 0.96
		_handle_z = -0.48
	else:
		_front_z = -0.76
		_rear_z = 0.73
		_radius = 0.30
		_handle_z = -0.36
	set_meta("steering_axis_position", Vector3(0,.88,-.48))
	# Tubular frame, swingarm, footpegs and rear suspension.
	for side in [-1.0, 1.0]:
		tube([Vector3(side*.13,.42,.58),Vector3(side*.17,.44,-.24),Vector3(side*.11,.89,-.48),Vector3(side*.17,.77,.38)],.028,black)
		tube([Vector3(side*.15,.40,.17),Vector3(side*.15,_radius,_rear_z)],.035,alloy)
		tube([Vector3(side*.17,.45,.12),Vector3(side*.29,.45,.12)],.023,chrome)
		var peg := cylinder(Vector3(side*.29,.45,.12),.035,.13,rubber)
		peg.rotation.z = PI/2
		tube([Vector3(side*.14,.76,.38),Vector3(side*.14,_radius+.06,_rear_z-.08)],.038,chrome)
		for coil in 7:
			var z := lerpf(.4,_rear_z-.1,coil/7.0)
			var y := lerpf(.74,_radius+.09,coil/7.0)
			var ring := _ring(Vector3(side*.14,y,z),.045,.028,mat("spring","d7b643",.6,.32))
			ring.rotation.x = -.65
	_engine(black, chrome, alloy)
	if style == "sport":
		_loft([Vector3(.18,.53,-.40),Vector3(.30,.61,-.26),Vector3(.25,.57,.13),Vector3(.14,.51,.34)],[.09,.25,.22,.07],paint)
		_loft([Vector3(.14,1.00,-.74),Vector3(.28,.99,-.57),Vector3(.21,.98,-.35)],[.08,.16,.08],paint)
		var screen := box(Vector3(0,1.16,-.48),Vector3(.32,.25,.025),mat("screen","294350",.3,.2))
		screen.rotation.x = -.55
		for side in [-1.0,1.0]:
			for vent in 3:
				var slot := box(Vector3(side*.286,.63+vent*.07,-.27),Vector3(.012,.026,.23),rubber)
				slot.rotation.x = -.30
			box(Vector3(side*.20,.87,-.70),Vector3(.14,.045,.035),mat("headlight","eefaff",.2,.15,.85))
			box(Vector3(side*.305,.72,-.27),Vector3(.014,.03,.33),mat("stripe","f1ede5",.1,.4))
	elif style == "cruiser":
		_loft([Vector3(.09,.77,-.47),Vector3(.23,.85,-.12),Vector3(.20,.79,.20)],[.08,.15,.10],paint)
		_loft([Vector3(.14,.80,.53),Vector3(.19,.80,.94)],[.10,.07],paint)
		for side in [-1.0,1.0]:
			var bag := box(Vector3(side*.25,.49,.60),Vector3(.20,.30,.42),leather)
			box(Vector3(side*.357,.55,.59),Vector3(.013,.045,.12),chrome)
			box(Vector3(side*.357,.42,.59),Vector3(.013,.08,.045),chrome)
		_round_lamp(Vector3(0,1.04,-.77),.13)
	else:
		_loft([Vector3(.10,.82,-.36),Vector3(.19,.87,-.12),Vector3(.15,.79,.16)],[.06,.12,.07],paint)
		for side in [-1.0,1.0]:
			box(Vector3(side*.14,.60,.22),Vector3(.045,.19,.35),paint)
			box(Vector3(side*.166,.65,.20),Vector3(.012,.04,.19),mat("stripe","d4dce0",.15,.45))
		_round_lamp(Vector3(0,1.01,-.61),.105)
	# Tank and filler cap, contoured saddle, tail light and registration plate.
	if style == "sport":
		_loft([Vector3(.11,.90,-.35),Vector3(.23,.97,-.07),Vector3(.15,.87,.20)],[.07,.14,.06],paint)
	var cap := cylinder(Vector3(0,1.10 if style == "sport" else .98, -.08),.046,.008,chrome)
	_loft([Vector3(.12,_seat_y,.12),Vector3(.18,_seat_y+.025,.40),Vector3(.13,_seat_y+.07,.65)],[.033,.045,.028],leather)
	box(Vector3(0,_seat_y+.025,.73),Vector3(.22,.045,.035),mat("taillight","bd2530",.3,.23,.55))
	var plate := box(Vector3(0,_seat_y-.14,.82),Vector3(.19,.12,.014),mat("plate","d6d9d2",.0,.75))
	plate.rotation.x = -.23
	for mark in 4: box(Vector3(-.061+mark*.038,_seat_y-.13,.832),Vector3(.022,.012,.003),black)
	for side in [-1.0,1.0]:
		box(Vector3(side*.18,_seat_y-.04,.71),Vector3(.045,.032,.04),mat("indicator","ee9c25",.15,.2,.35))
	# Exhaust pipes have dark open tips; cruiser has stacked chrome pipes.
	var exhaust_count := 2 if style == "cruiser" else 1
	for pipe in exhaust_count:
		var y := .30+pipe*.105
		tube([Vector3(.12,.50,-.23+pipe*.22),Vector3(.25,y,-.05),Vector3(.26,y,.74)],.035,chrome)
		var silencer := cylinder(Vector3(.26,y,.55),.063,.43,chrome if style == "cruiser" else alloy)
		silencer.rotation.x = PI/2
		var opening := cylinder(Vector3(.26,y,.773),.047,.012,rubber)
		opening.rotation.x = PI/2
	_wheel(_front_z, true)
	_wheel(_rear_z, false)
	# Side stand is shown only when unoccupied.
	stand = Node3D.new()
	add_child(stand)
	var start := get_child_count()
	tube([Vector3(-.12,.36,.16),Vector3(-.34,.025,.28)],.018,alloy)
	_move_new_parts(start,stand)
	_build_rider()
	set_rider_state(true, false)

func _ring(pos: Vector3, outside: float, inside: float, material: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inside
	mesh.outer_radius = outside
	mesh.rings = 32
	mesh.ring_segments = 10
	return mesh_node(mesh,pos,material)

func _loft(sections: Array, heights: Array, material: Material) -> void:
	var shape := [Vector2(-.65,-1),Vector2(.65,-1),Vector2(1,-.5),Vector2(1,.5),Vector2(.6,1),Vector2(-.6,1),Vector2(-1,.5),Vector2(-1,-.5)]
	var rings: Array = []
	for i in sections.size():
		var ring: Array[Vector3] = []
		var s: Vector3 = sections[i]
		for p in shape: ring.append(Vector3(p.x*s.x,s.y+p.y*float(heights[i]),s.z))
		rings.append(ring)
	for i in range(rings.size()-1):
		for j in 8:
			var k := (j+1)%8
			surface([rings[i][j],rings[i+1][j],rings[i+1][k],rings[i][k]],material)
	var first: Array[Vector3] = rings[0].duplicate()
	first.reverse()
	surface(first,material)
	surface(rings.back(),material)

func _round_lamp(pos: Vector3, radius: float) -> void:
	var housing := cylinder(pos,radius+.015,.13,materials.chrome)
	housing.rotation.x = PI/2
	var lens := cylinder(pos+Vector3(0,0,-.07),radius,.018,mat("headlight","f6ebd3",.1,.15,.85))
	lens.rotation.x = PI/2

func _engine(black: Material, chrome: Material, alloy: Material) -> void:
	ell(Vector3(0,.47,.02),Vector3(.34,.28,.35),black)
	for side in [-1.0,1.0]:
		var cover := cylinder(Vector3(side*.18,.44,.03),.105,.045,chrome)
		cover.rotation.z = PI/2
	var cylinder_count := 2 if style == "cruiser" else 1
	for block in cylinder_count:
		var z := -.17+block*.27
		for fin in 6:
			var part := box(Vector3(0,.50+fin*.025,z),Vector3(.27,.014,.15),alloy)
			part.rotation.x = -.35 if block == 0 else .35
		box(Vector3(0,.67,z),Vector3(.26,.075,.15),chrome)
	box(Vector3(0,.60,-.36),Vector3(.28,.27,.045),black)
	for fin in 7: box(Vector3(0,.49+fin*.035,-.39),Vector3(.24,.01,.014),alloy)

func _wheel(z: float, front: bool) -> void:
	var center := Vector3(0,_radius,z)
	var start := get_child_count()
	var tire := _ring(center,_radius,_radius*.72,materials.rubber)
	tire.rotation.z = PI/2
	tire.scale.y = 1.35 if front else 1.90
	var rim := _ring(center,_radius*.73,_radius*.64,materials.chrome)
	rim.rotation.z = PI/2
	rim.scale.y = .8
	var spoke_count := 12 if style == "cruiser" else 6
	for spoke in spoke_count:
		var a := TAU*spoke/spoke_count
		tube([center+Vector3(0,cos(a)*.045,sin(a)*.045),center+Vector3(0,cos(a+.10)*_radius*.67,sin(a+.10)*_radius*.67)],.013,materials.alloy)
	for side in [-1.0,1.0]:
		var rotor := _ring(center+Vector3(side*.069,0,0),_radius*.51,_radius*.35,materials.alloy)
		rotor.rotation.z = PI/2
		rotor.scale.y = .17
		var hub := cylinder(center+Vector3(side*.04,0,0),.053,.045,materials.chrome)
		hub.rotation.z = PI/2
	for i in range(start,get_child_count()):
		get_child(i).set_meta("wheel_center",center)
		get_child(i).set_meta("wheel_radius",_radius)
		get_child(i).set_meta("wheel_spins",true)
	start = get_child_count()
	var caliper := box(center+Vector3(.083,.035,.12),Vector3(.04,.095,.065),mat("caliper","b84332",.4,.4))
	# Fender follows the fork, with a real air gap above the tread.
	for step in 9:
		var a := PI*(.10+step*.08)
		var b := PI*(.10+(step+1)*.08)
		var r := _radius+.025
		var width := .095 if front else .12
		surface([center+Vector3(-width,sin(a)*r,cos(a)*r),center+Vector3(-width,sin(b)*r,cos(b)*r),center+Vector3(width,sin(b)*r,cos(b)*r),center+Vector3(width,sin(a)*r,cos(a)*r)],paint)
	if front:
		for side in [-1.0,1.0]:
			tube([center+Vector3(side*.105,0,0),Vector3(side*.105,.88,-.48)],.026,materials.chrome)
			tube([Vector3(side*.10,.89,-.48),Vector3(side*.19,_handle_y,_handle_z),Vector3(side*.34,_handle_y,_handle_z+.055)],.018,materials.alloy)
			var grip := cylinder(Vector3(side*.32,_handle_y,_handle_z+.055),.026,.12,materials.rubber)
			grip.rotation.z = PI/2
			tube([Vector3(side*.23,_handle_y,_handle_z),Vector3(side*.34,_handle_y+.14,_handle_z-.06)],.009,materials.chrome)
			ell(Vector3(side*.35,_handle_y+.15,_handle_z-.06),Vector3(.12,.065,.065),materials.chrome)
		box(Vector3(0,_handle_y-.02,_handle_z+.025),Vector3(.17,.055,.095),materials.engine)
		box(Vector3(0,_handle_y+.011,_handle_z+.025),Vector3(.10,.004,.055),mat("dash","75b3bb",.2,.3,.3))
	for i in range(start,get_child_count()):
		get_child(i).set_meta("wheel_center",center)
		get_child(i).set_meta("wheel_radius",_radius)
		get_child(i).set_meta("wheel_spins",false)

func _move_new_parts(first: int, parent: Node3D) -> void:
	var parts := get_children().slice(first)
	for part in parts:
		if part != parent: part.reparent(parent,true)

func _build_rider() -> void:
	rider = Node3D.new()
	rider.name = "Rider"
	add_child(rider)
	rider_jacket = mat("rider_jacket","333f55",.0,.86)
	rider_helmet = mat("rider_helmet","e1dcd2",.25,.30)
	var jeans := mat("rider_jeans","253043",.0,.95)
	var gloves := mat("rider_gloves","181b20",.0,.84)
	var first := get_child_count()
	var waist := Vector3(0,_seat_y+.18,.28)
	var shoulders := Vector3(0,_seat_y+.48,-.12 if style == "sport" else .12)
	ell(Vector3(0,_seat_y+.12,.30),Vector3(.34,.27,.24),jeans)
	var torso := ell((waist+shoulders)*.5,Vector3(.38,waist.distance_to(shoulders)+.18,.25),rider_jacket)
	torso.quaternion = Quaternion(Vector3.UP,(shoulders-waist).normalized())
	var head := shoulders+Vector3(0,.24,-.06)
	tube([shoulders,head],.073,gloves)
	ell(head,Vector3(.27,.31,.29),rider_helmet)
	ell(head+Vector3(0,.015,-.113),Vector3(.245,.13,.075),mat("visor","101d29",.5,.12))
	box(head+Vector3(0,-.095,-.117),Vector3(.21,.045,.04),rider_helmet)
	for side in [-1.0,1.0]:
		ell(head+Vector3(side*.125,.02,-.05),Vector3(.018,.035,.035),materials.chrome)
	# A subtle suit spine and elbow protectors read clearly from the game camera.
	var spine := box((waist+shoulders)*.5+Vector3(0,0,.132),Vector3(.035,.32,.014),materials.stripe if materials.has("stripe") else materials.chrome)
	spine.quaternion = torso.quaternion
	_move_new_parts(first,rider)
	for side in [-1.0,1.0]:
		var arm := Node3D.new()
		rider.add_child(arm)
		var upper := _limb(arm,.066,rider_jacket)
		var lower := _limb(arm,.051,rider_jacket)
		first = get_child_count()
		var hand := ell(Vector3.ZERO,Vector3(.10,.075,.11),gloves)
		# Hand needs its own transform, preserved by the static mesh batcher.
		var hand_pivot := Node3D.new()
		arm.add_child(hand_pivot)
		_move_new_parts(first,hand_pivot)
		_arm_parts.append({"upper":upper,"lower":lower,"hand":hand_pivot,"shoulder":shoulders+Vector3(side*.17,0,0),"side":side})
		var leg := Node3D.new()
		rider.add_child(leg)
		upper = _limb(leg,.070,jeans)
		lower = _limb(leg,.055,jeans)
		var boot_pivot := Node3D.new()
		leg.add_child(boot_pivot)
		first = get_child_count()
		box(Vector3(0,-.035,-.025),Vector3(.105,.10,.21),gloves)
		_move_new_parts(first,boot_pivot)
		_leg_parts.append({"upper":upper,"lower":lower,"boot":boot_pivot,"side":side})
		if side < 0: left_leg = leg
		else: right_leg = leg
	_pose_limbs(0.0)

func _limb(parent: Node3D, radius: float, material: Material) -> Node3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	var first := get_child_count()
	cylinder(Vector3(0,.5,0),radius,1.0,material)
	_move_new_parts(first,pivot)
	return pivot

func _place_limb(pivot: Node3D, start: Vector3, finish: Vector3) -> void:
	var direction := finish-start
	pivot.position = start
	pivot.basis = Basis(Quaternion(Vector3.UP,direction.normalized())).scaled_local(Vector3(1,direction.length(),1))

func _pose_limbs(steering: float) -> void:
	for data in _arm_parts:
		var shoulder: Vector3 = data.shoulder
		var axis := Vector3(0,.88,-.48)
		var grip := Vector3(data.side*.31,_handle_y+.015,_handle_z+.065)
		var hand := axis+Basis(Vector3.UP,steering)*(grip-axis)
		var elbow := shoulder.lerp(hand,.48)+Vector3(data.side*.08,-.085,.045)
		_place_limb(data.upper,shoulder,elbow)
		_place_limb(data.lower,elbow,hand)
		data.hand.position = hand
	for data in _leg_parts:
		var side: float = data.side
		var hip := Vector3(side*.14,_seat_y+.10,.30)
		var resting := Vector3(side*.28,.49,.18 if style != "cruiser" else -.12)
		var foot := resting.lerp(Vector3(side*.35,.10,.24),_foot_down if side < 0 else 0.0)
		var knee := hip.lerp(foot,.52)+Vector3(side*.09,0,-.20*(1.0-_foot_down if side < 0 else 1.0))
		_place_limb(data.upper,hip,knee)
		_place_limb(data.lower,knee,foot)
		data.boot.position = foot

func set_rider_state(occupied: bool, player_owned: bool) -> void:
	if rider == null: return
	rider.visible = occupied
	for part in rider.get_children():
		if part is Node3D:
			part.visible = (part == dante_rider) if player_owned and is_instance_valid(dante_rider) else part != dante_rider
	stand.visible = not occupied
	rider_jacket.albedo_color = Color("26364d") if player_owned else Color("41454d")
	rider_helmet.albedo_color = Color("e8e6e0") if player_owned else paint.albedo_color.lightened(.15)

func set_dante_rider(actor: CharacterBody2D) -> void:
	if not is_instance_valid(actor): return
	# The seated body is required even when the actor has no helmet controller.
	dante_helmet_state = actor.ensure_motorcycle_helmet() if actor.has_method("ensure_motorcycle_helmet") else null
	if not is_instance_valid(dante_rider):
		dante_rider = preload("res://cars/motorcycles/DanteMotorcycleRider.gd").new()
		dante_rider.name = "DanteRider"
		rider.add_child(dante_rider)
	if dante_rider.source_head_id != actor.head_node.get_instance_id():
		dante_rider.setup(actor)
	dante_rider.pose(self,0.0,_foot_down,dante_helmet_state)

func sync_dante_helmet(state: Node) -> void:
	if is_instance_valid(dante_rider) and dante_rider.visible:
		preload("res://scripts/player/DanteHelmetVisual.gd").apply(dante_rider.head_node,state.worn,state.action,state.action_seconds/state.ACTION_SECONDS)

func char_body() -> void:
	super.char_body()
	rider.hide()
	stand.hide()

func update_riding_pose(delta: float, speed_metres: float, steering: float, occupied: bool) -> bool:
	if get_meta("fallen_motorcycle", false):
		if not occupied: return true
		remove_meta("fallen_motorcycle")
		lean = 0.0
	var previous := lean
	var target := clampf(-atan(speed_metres*speed_metres*tan(steering)/(9.81*(_rear_z-_front_z))),-.38,.38) if occupied else -.10
	lean = lerpf(lean,target,1.0-exp(-delta*8.0))
	rotation.z = lean
	var previous_foot := _foot_down
	_foot_down = move_toward(_foot_down,1.0 if occupied and absf(speed_metres)<.4 else 0.0,delta*4.0)
	_pose_limbs(steering)
	var gesture := false
	if is_instance_valid(dante_rider) and dante_rider.visible:
		dante_rider.pose(self,steering,_foot_down,dante_helmet_state)
		gesture = is_instance_valid(dante_helmet_state) and not dante_helmet_state.action.is_empty()
	return gesture or absf(previous-lean)>.001 or absf(previous_foot-_foot_down)>.001
