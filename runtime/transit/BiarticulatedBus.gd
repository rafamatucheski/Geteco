extends "res://scripts/Vehicle.gd"
const TRANSIT_WORK := preload("res://runtime/StallWorkTrace.gd")
## Three physical bodies joined by drawbars. All bodies must admit a step before
## any moves; rear sections cannot tunnel through street furniture during turns.
const MODEL := preload("res://runtime/transit/BiarticulatedModel.gd")
const SECTION := preload("res://runtime/transit/TransitSection.gd")
const LENGTHS := [7.8,6.8,6.8]
const JOINT_GAP := .65
const TOTAL_LENGTH := 22.7
var sections: Array[CharacterBody3D] = []
var presentations: Array[Dictionary] = []
var hulls: Array[BoxShape3D] = []
var exclude_bodies: Array[RID] = []
var bellows: Array[Node3D] = []
var door_amount := 0.0
var service_stop := -1
var dwell := 0.0
var stop_offset := 0.0
var passengers: Array = []
var player_aboard := false
var active := false
var stolen := false
var driver_shift := false
var work_state: Dictionary = {}
var _saved_articulation: Array = [0.0,0.0]
var blocked_by := ""
var total_travelled := 0.0
var lap := 0
var service_state := "approach"
var junction_tokens: Dictionary = {}
var _junctions: Array = []
var _query := PhysicsShapeQueryParameters3D.new()
var path_poses: RefCounted
var headlights: Array[SpotLight3D] = []

func _ready() -> void:
	var stall_began := TRANSIT_WORK.begin()
	_stall_ready()
	if stall_began != 0: TRANSIT_WORK.finish("urban.bus.ready", stall_began, {"name":str(name),"sections":sections.size()})

func _stall_ready() -> void:
	archetype = "biarticulated_510"
	if vehicle_id.is_empty(): vehicle_id = "biarticulated_510_%d" % get_instance_id()
	set_meta("biarticulated",true)
	if not has_meta("region_id"): set_meta("region_id","harbor")
	add_to_group("drivable")
	set_meta("gameplay_role","vehicle")
	set_meta("transit_service",true)
	add_to_group("public_transport_vehicle")
	health = 700; max_health = 700
	half_width = 1.28; half_length = LENGTHS[0]*.5; body_height = 3.1
	sections.append(self)
	for index in 3:
		var body: CharacterBody3D = self
		if index > 0:
			body = SECTION.new(); body.bus = self
			body.name = "Section%d" % index
			add_child(body)
			body.top_level = true
			sections.append(body)
		body.collision_layer = 4; body.collision_mask = 7
		var col := CollisionShape3D.new()
		var hull := BoxShape3D.new()
		hull.size = Vector3(2.56,2.86,LENGTHS[index])
		if index > 0:
			body.half_length = hull.size.z * .5
			body.half_width = hull.size.x * .5
		col.shape = hull; col.position.y = 1.65
		body.add_child(col)
		if index==0: shape = col
		hulls.append(hull)
		exclude_bodies.append(body.get_rid())
		var model_began := TRANSIT_WORK.begin()
		presentations.append(MODEL.build(body,LENGTHS[index],index))
		if model_began != 0: TRANSIT_WORK.finish("urban.bus.section_model",model_began,{"name":str(name),"section":index})
	for body in sections:
		for other in sections:
			if body != other: body.add_collision_exception_with(other)
	visual = presentations[0].model
	visual.set_meta("vehicle_interior_spec",{"kind":"bus","sx":-.51,"sz":-2.85,"floor":.42,"roof":2.82,"belt":1.6,"wz0":-3.9,"wz1":-3.9,"rear":-2.2,"rear_top":-2.2,"hw":1.17})
	_query.collision_mask = 7
	_query.exclude = exclude_bodies
	for index in 2:
		var joint := Node3D.new()
		joint.name = "Bellows%d" % index
		add_child(joint); joint.top_level = true
		for rib in 9: MODEL.box(joint,Vector3(0,0,0),Vector3(2.39,2.58,.045),"rubber" if rib%2 else "metal")
		bellows.append(joint)
	set_active(stolen)
	for side in [-1,1]:
		var beam := SpotLight3D.new()
		beam.position=Vector3(side*.87,1.05,-half_length-.1)
		beam.rotation.x=deg_to_rad(-5)
		beam.spot_range=20; beam.spot_angle=32; beam.light_energy=1.4
		beam.light_color=Color("fff0d7"); beam.shadow_enabled=true
		add_child(beam); headlights.append(beam)

func set_active(value: bool) -> void:
	active = value
	traffic = value and health>0 and not stolen and not driver_shift
	visible = value
	for body in sections: body.collision_layer = 4 if value else 0
	if not value: speed = 0; _release_tokens()

func set_route(value: Curve3D, offset: float) -> void:
	_release_tokens()
	route = value
	route_distance = offset
	_junctions = JUNCTIONS.along(route)
	var poses: Array[Transform3D] = []
	var front := _front_pose(offset)
	poses.append(front)
	for index in range(1,3):
		var previous_pose := poses[-1]
		var behind: Vector3 = previous_pose.origin+previous_pose.basis.z*(LENGTHS[index-1]*.5+JOINT_GAP+LENGTHS[index]*.5)
		poses.append(Transform3D(front.basis,behind))
	_apply_poses(poses,false)
	for body in sections: body.reset_physics_interpolation()

func _front_pose(offset: float) -> Transform3D:
	var length := route.get_baked_length()
	var point := route.sample_baked(fposmod(offset,length),true)
	var tangent := route.sample_baked(fposmod(offset+.15,length),true)-route.sample_baked(fposmod(offset-.15,length),true)
	return Transform3D(Basis(Vector3.UP,atan2(-tangent.x,-tangent.z)),point+Vector3.UP*.04)

func proposed_poses(offset: float) -> Array[Transform3D]:
	if path_poses != null: return path_poses.at(offset)
	var result: Array[Transform3D] = [_front_pose(offset)]
	for index in range(1,3):
		var previous_pose := result[-1]
		var hitch: Vector3 = previous_pose.origin+previous_pose.basis.z*(LENGTHS[index-1]*.5+JOINT_GAP*.5)
		var toward: Vector3 = hitch-sections[index].global_position
		toward.y = 0
		var yaw := atan2(-toward.x,-toward.z)
		var local_basis := Basis(Vector3.UP,yaw)
		result.append(Transform3D(local_basis,hitch+local_basis.z*(LENGTHS[index]*.5+JOINT_GAP*.5)))
	return result

func admits(poses: Array[Transform3D], swept := true) -> bool:
	var space := get_world_3d().direct_space_state
	for index in 3:
		var start := sections[index].global_transform
		var target := poses[index]
		_query.shape = hulls[index]
		_query.motion = Vector3.ZERO
		for weight in [.5,1.0]:
			_query.transform = start.interpolate_with(target,weight) if swept else target
			_query.transform.origin += Vector3.UP*1.65
			var hits := space.intersect_shape(_query,1)
			if not hits.is_empty():
				blocked_by = str(hits[0].collider.get_path())+" @ "+str(hits[0].collider.global_position)
				return false
		if swept:
			_query.transform = start
			_query.transform.origin += Vector3.UP*1.65
			_query.motion = target.origin-start.origin
			if space.cast_motion(_query)[0] < .999: blocked_by = "swept obstruction"; return false
	blocked_by = ""
	return true

func _apply_poses(poses: Array[Transform3D], swept := true) -> void:
	# Trailers are top-level: moving the tractor never drags them through a wall.
	for index in 3:
		var body := sections[index]
		if swept: body.move_and_collide(poses[index].origin-body.global_position)
		else: body.global_position = poses[index].origin
		body.global_basis = poses[index].basis
	for index in 2:
		var a: Vector3 = sections[index].global_position+sections[index].global_basis.z*LENGTHS[index]*.5
		var b: Vector3 = sections[index+1].global_position-sections[index+1].global_basis.z*LENGTHS[index+1]*.5
		# Fole em leque: cada nervura gira um pouco mais que a anterior, do fim de uma
		# seção ao início da outra. Um bloco reto só no meio deixava uma cunha aberta no
		# lado externo da curva e atravessava as quinas por dentro (vídeo de 12/10/2026).
		var from_basis := sections[index].global_basis
		var to_basis := sections[index+1].global_basis
		var ribs := bellows[index].get_child_count()
		for rib in ribs:
			var fraction := float(rib)/float(ribs-1)
			var rib_node := bellows[index].get_child(rib) as Node3D
			rib_node.global_transform = Transform3D(from_basis.slerp(to_basis,fraction),a.lerp(b,fraction)+Vector3.UP*1.72)

func _physics_process(delta: float) -> void:
	if not (stolen or driver_shift) or not active: return # Service owns only the scheduled fleet.
	if health<=0 or input_locked or engine_disabled or not (controlled or external_input):
		speed = 0; horizontal_velocity = Vector3.ZERO; return
	if not external_input:
		var axis: Vector2 = get_node("/root/GameInput").vehicle_input()
		throttle_input = axis.y; steer_input = -axis.x
		brake_input = Input.is_action_pressed("handbrake")
	if door_amount>0:
		if driver_shift: speed=0; horizontal_velocity=Vector3.ZERO; return
		set_doors(move_toward(door_amount,0,delta*2))
		if door_amount>0: speed=0; return
	if brake_input: speed=move_toward(speed,0,5.5*delta)
	elif absf(throttle_input)>.01: speed=clampf(speed+throttle_input*2.0*delta,-3.5,13.0)
	else: speed=move_toward(speed,0,1.0*delta)
	steering = move_toward(steering,steer_input*.38,delta*.75)
	var step := speed*delta
	if absf(step)<.0001: return
	var front := global_transform
	front.basis = Basis(Vector3.UP,rotation.y+speed/4.75*tan(steering)*delta)
	front.origin -= front.basis.z*step
	var poses := manual_poses(front)
	for index in range(1,3):
		if absf(angle_difference(poses[index-1].basis.get_euler().y,poses[index].basis.get_euler().y))>deg_to_rad(55): speed=0; return
	var space := get_world_3d().direct_space_state
	for index in 3:
		var point := poses[index].origin
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.8,point-Vector3.UP*1.5,1,exclude_bodies))
		if floor_hit.is_empty(): speed=0; return
		poses[index].origin.y = floor_hit.position.y+.04
	if not admits(poses): speed=0; blocked=true; return
	blocked=false
	_apply_poses(poses)
	horizontal_velocity=-global_basis.z*speed
	distance_travelled+=absf(step)
	for entry in presentations:
		for wheel in entry.wheels: wheel.rotate_object_local(Vector3.UP,step/.48)

func manual_poses(front: Transform3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = [front]
	for index in range(1,3):
		var previous_pose := poses[-1]
		var hitch: Vector3 = previous_pose.origin+previous_pose.basis.z*(LENGTHS[index-1]*.5+JOINT_GAP*.5)
		var direction: Vector3 = hitch-sections[index].global_position
		var basis := Basis(Vector3.UP,atan2(-direction.x,-direction.z))
		poses.append(Transform3D(basis,hitch+basis.z*(LENGTHS[index]*.5+JOINT_GAP*.5)))
	return poses

func boarding_class() -> String: return "bus"
func _cab_z() -> float: return float(presentations[0].door_z) if not presentations.is_empty() else -2.7
func animate_driver_door(_side: int, opened: bool, _duration := .28) -> void: set_doors(1.0 if opened else 0.0)

func place(point: Vector3, yaw: float) -> void:
	_apply_poses(placement_poses(point,yaw),false)
	stop_boarding_motion()
	for body in sections: body.reset_physics_interpolation()

func placement_poses(point: Vector3, yaw: float) -> Array[Transform3D]:
	var poses: Array[Transform3D] = [Transform3D(Basis(Vector3.UP,yaw),point)]
	for index in range(1,3):
		var previous_pose := poses[-1]
		var basis := Basis(Vector3.UP,yaw+float(_saved_articulation[index-1]))
		var hitch: Vector3 = previous_pose.origin+previous_pose.basis.z*(LENGTHS[index-1]*.5+JOINT_GAP*.5)
		poses.append(Transform3D(basis,hitch+basis.z*(LENGTHS[index]*.5+JOINT_GAP*.5)))
	return poses

func fleet_snapshot_extras() -> Dictionary:
	var result := {"articulation":[angle_difference(rotation.y,sections[1].rotation.y),angle_difference(rotation.y,sections[2].rotation.y)]}
	if driver_shift and not work_state.is_empty(): result["bus_work"]=work_state.duplicate(true)
	return result

func restore_fleet_extras(saved: Dictionary) -> void:
	_saved_articulation = saved.get("articulation",[0.0,0.0]).duplicate()
	work_state=saved.get("bus_work",{}).duplicate(true)
	if not work_state.is_empty(): driver_shift=true; stolen=false

func drive(delta: float) -> void:
	if not active or route == null or health<=0 or door_amount>0: speed=0; return
	var length := route.get_baked_length()
	var remaining := fposmod(stop_offset-route_distance,length)
	if remaining > length-.1: remaining = 0
	var gap := signal_gap()
	junction_wait = gap<35
	var bend := absf(angle_difference(_front_pose(route_distance).basis.get_euler().y,_front_pose(route_distance+8).basis.get_euler().y))
	var desired: float = min(7.0,lerpf(7.0,2.4,clampf(bend,0,1)),sqrt(2*2.4*maxf(0,remaining)),sqrt(2*3*maxf(0,gap)))
	speed = move_toward(speed,desired,delta*(1.5 if speed<desired else 3.0))
	var step := minf(speed*delta,remaining)
	if step < .0001: return
	var poses := proposed_poses(route_distance+step)
	for index in range(1,3):
		if absf(angle_difference(poses[index-1].basis.get_euler().y,poses[index].basis.get_euler().y)) > deg_to_rad(55): speed=0; blocked_by="articulation limit"; return
	if not admits(poses):
		speed=0; blocked=true; blocked_time+=delta; stall_time=blocked_time
		return
	blocked = false
	blocked_time=0; stall_time=0
	_apply_poses(poses)
	for entry in presentations:
		for wheel in entry.wheels: wheel.rotate_object_local(Vector3.UP,step/.48)
	route_distance = fposmod(route_distance+step,length)
	total_travelled += step
	if route_distance < step: lap += 1
	traffic = true

func junction_collision_bodies() -> Array[CharacterBody3D]:
	return sections

func signal_gap() -> float:
	var gap := INF
	var length := route.get_baked_length()
	for item in _junctions:
		var ahead := fposmod(float(item.offset)-route_distance+length*.5,length)-length*.5
		if junction_tokens.has(item.key) and not JUNCTIONS.has_reservation(item.key, get_instance_id()):
			junction_tokens.erase(item.key)
		if junction_tokens.has(item.key):
			# Keep the crossing occupied until the LAST section clears it.
			if ahead < -(TOTAL_LENGTH-half_length+JUNCTIONS.EXIT) and not JUNCTIONS.occupies(item.key, get_instance_id()):
				JUNCTIONS.release(item.key,get_instance_id()); junction_tokens.erase(item.key)
			continue
		if ahead < -(TOTAL_LENGTH-half_length+JUNCTIONS.EXIT) or ahead > 35: continue
		var stop_gap := ahead-half_length-JUNCTIONS.stop_line(item.key)
		var heading := -_front_pose(float(item.offset)-7).basis.z
		if JUNCTIONS.request(item.key,get_instance_id(),heading,stop_gap,speed): junction_tokens[item.key]=true
		else: gap=minf(gap,stop_gap-.35)
	return gap

func _release_tokens() -> void:
	for key in junction_tokens: JUNCTIONS.release(key,get_instance_id())
	junction_tokens.clear()

func door_point(section := 0, outside := true) -> Vector3:
	return sections[section].to_global(Vector3(1.95 if outside else .85,.2,float(presentations[section].door_z)))

func set_doors(value: float) -> void:
	door_amount = clampf(value,0,1)
	for entry in presentations:
		for index in 2: entry.doors[index].position.z = entry.door_z+(-1 if index==0 else 1)*(.32+door_amount*.58)

func is_servicing_stop() -> bool:
	return active and not stolen and not driver_shift and service_state in ["exchange","closing"]

func receive_damage(amount: float, _source: Node = null) -> void:
	if amount<=0 or health<=0: return
	health = maxf(0,health-amount)
	damaged.emit(amount)
	if health<=0:
		speed=0; traffic=false; controlled=false
		destroyed.emit()

func _exit_tree() -> void: _release_tokens()
