extends RefCounted
## A reserved seat is approached and left through its clear front, using physics.
var actor: CharacterBody2D
var seat: Node2D
var bench_body: PhysicsBody2D
var state := "idle"
var rest_left := 0.0
var state_time := 0.0
var sit_amount := 0.0
var completed_rests := 0
var interrupted := false
var cooldown := 0.0
var _navigation := preload("res://emergency/ResponderNavigation.gd").new()
var _last_position := Vector2.INF
var _stuck := 0.0
var _entry_route := PackedVector2Array()
var _approach_route := PackedVector2Array()
var _departure_route := PackedVector2Array()
var _route_index := 0
var _original_sprite_z := 0

func configure(owner_actor: CharacterBody2D) -> void:
	actor = owner_actor
	cooldown = 3.0 + posmod(actor.appearance_variant, 8)
	_navigation.search_budget = 96

func request(max_distance := 230.0, scope := "") -> bool:
	if state != "idle" or actor.is_dead or actor.panic_timer > 0.0: return false
	var candidates: Array[Node2D] = []
	for candidate in actor.get_tree().get_nodes_in_group("mountain_bench_seat"):
		if not candidate is Node2D or candidate.global_position.distance_to(actor.global_position) > max_distance: continue
		if not scope.is_empty() and String(candidate.get_meta("scope",candidate.get_meta("bench_group",""))) != scope: continue
		var occupied_by := int(candidate.get_meta("bench_occupant_id",0))
		if occupied_by != 0 and is_instance_id_valid(occupied_by): continue
		if not _point_clear(candidate.to_global(candidate.get_meta("approach_offset",Vector2(0,28))),null): continue
		candidates.append(candidate)
	candidates.sort_custom(func(a:Node2D,b:Node2D)->bool:return actor.global_position.distance_squared_to(a.global_position)<actor.global_position.distance_squared_to(b.global_position))
	if candidates.is_empty(): cooldown=5.0;return false
	for candidate in candidates:
		var support:=candidate.get_meta("bench_body",null) as PhysicsBody2D
		if support!=null and _point_clear(candidate.global_position,support):
			seat=candidate
			bench_body=support
			break
	if seat==null:cooldown=5.0;return false
	seat.set_meta("bench_occupant_id",actor.get_instance_id())
	_original_sprite_z=actor.presentation_sprite.z_index
	_entry_route.clear()
	for point in seat.get_meta("route_hint",[]):_entry_route.append(seat.to_global(point))
	if _entry_route.is_empty():
		_entry_route.append(seat.to_global(seat.get_meta("approach_offset",Vector2(0,28))))
	if _entry_route[-1].distance_to(seat.global_position)>0.1:_entry_route.append(seat.global_position)
	_approach_route.clear()
	for point in seat.get_meta("access_route",[]):_approach_route.append(seat.to_global(point))
	_approach_route.append(_entry_route[0])
	_route_index=0
	state="approaching"
	state_time=0.0
	interrupted=false
	_stuck=0.0
	_last_position=actor.global_position
	rest_left=7.0+posmod(actor.appearance_variant*3+completed_rests*5,10)
	return true

func update(delta:float)->bool:
	cooldown=maxf(0.0,cooldown-delta)
	if state=="idle":return false
	if not is_instance_valid(seat) or not is_instance_valid(bench_body):release(false);return false
	state_time+=delta
	var facing:Vector2=seat.get_meta("facing",Vector2.DOWN)
	actor.model.rotation.y=-facing.angle()+PI*0.5
	actor.velocity=Vector2.ZERO
	actor.model.walking=false
	match state:
		"approaching":
			_move(_approach_route[_route_index],31.0,delta)
			if actor.global_position.distance_to(_approach_route[_route_index])<0.75:
				if _route_index<_approach_route.size()-1:
					_route_index+=1
					return true
				if not _point_clear(seat.global_position,bench_body):release(false);return false
				actor.add_collision_exception_with(bench_body)
				if seat.has_meta("occlusion_z_index"):
					actor.presentation_sprite.z_index=int(seat.get_meta("occlusion_z_index"))-actor.z_index
				state="sitting"
				state_time=0.0
				_route_index=mini(1,_entry_route.size()-1)
		"sitting":
			# Back into the reserved support while knees and hips bend.
			_move(_entry_route[_route_index],24.0,delta)
			if actor.global_position.distance_to(_entry_route[_route_index])<1.2 and _route_index<_entry_route.size()-1:_route_index+=1
			sit_amount=move_toward(sit_amount,1.0 if _route_index==_entry_route.size()-1 else 0.0,delta/1.05)
			actor.model.walking=actor.velocity.length()>1.0 and sit_amount<0.1
			if actor.global_position.distance_to(seat.global_position)<0.7 and sit_amount>=0.999:
				state="resting"
				state_time=0.0
				actor.bench_rest_started.emit(actor,seat)
		"resting":
			rest_left-=delta
			if rest_left<=0.0:state="standing";state_time=0.0
		"standing":
			sit_amount=move_toward(sit_amount,0.0,delta/(0.32 if interrupted else 0.9))
			if sit_amount<=0.001:
				state="leaving"
				state_time=0.0
				_route_index=0
				_departure_route.clear()
				for index in range(_entry_route.size()-2,-1,-1):_departure_route.append(_entry_route[index])
				if not interrupted:
					for index in range(_approach_route.size()-2,-1,-1):_departure_route.append(_approach_route[index])
				if _departure_route.is_empty():_departure_route.append(_entry_route[0])
		"leaving":
			_move(_departure_route[_route_index],78.0 if interrupted else 30.0,delta)
			if actor.global_position.distance_to(_departure_route[_route_index])<0.75:
				if _route_index<_departure_route.size()-1:_route_index+=1
				else:release(not interrupted);return false
	actor.model.set_seat_pose(sit_amount,float(seat.get_meta("seat_height",0.45)),actor.appearance_variant%3)
	if seat.has_meta("visual_seat_offset"):
		actor.align_bench_presentation(sit_amount,seat.get_meta("visual_seat_offset"),float(seat.get_meta("seat_height",0.45)))
	if state in ["approaching","sitting","leaving"]:
		_stuck=_stuck+delta if actor.global_position.distance_to(_last_position)<0.05 else 0.0
		_last_position=actor.global_position
		if _stuck>8.0:
			if state=="approaching":release(false);return false
			interrupt()
	return true

func _move(goal:Vector2,speed:float,delta:float)->void:
	actor.velocity=_navigation.movement(actor,goal,speed,delta)
	actor.move_and_slide()
	actor.model.walking=actor.velocity.length()>1.0
	if state=="approaching" and actor.model.walking:actor.model.rotation.y=-actor.velocity.angle()+PI*0.5

func interrupt()->void:
	if state=="idle":return
	interrupted=true
	if state=="approaching":release(false)
	elif state!="leaving":state="standing";state_time=0.0

func release(completed:bool,notify:bool=true)->void:
	if not is_instance_valid(actor):return
	if is_instance_valid(bench_body):actor.remove_collision_exception_with(bench_body)
	if is_instance_valid(seat) and int(seat.get_meta("bench_occupant_id",0))==actor.get_instance_id():seat.remove_meta("bench_occupant_id")
	var was_active:=state!="idle"
	if was_active and is_instance_valid(actor.presentation_sprite):actor.presentation_sprite.z_index=_original_sprite_z
	state="idle"
	seat=null
	bench_body=null
	sit_amount=0.0
	cooldown=22.0+posmod(actor.appearance_variant+completed_rests,13)
	if completed:completed_rests+=1
	if is_instance_valid(actor.model):actor.model.set_seat_pose(0.0,0.45,0)
	actor.align_bench_presentation(0.0,Vector2.ZERO,0.45)
	if was_active and notify:actor.bench_rest_finished.emit(actor,completed)

func _point_clear(point:Vector2,allowed:PhysicsBody2D)->bool:
	var shape:=CircleShape2D.new()
	shape.radius=7.0
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=shape
	query.transform=Transform2D(0.0,point)
	query.collision_mask=3
	var excluded:Array[RID]=[actor.get_rid()]
	if is_instance_valid(allowed):excluded.append(allowed.get_rid())
	query.exclude=excluded
	return actor.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()
