extends "res://scripts/Actor.gd"
## Uses the normal civilian damage, panic, collision and streaming owners.
var social_activity := "talk"
var social_facing := Vector3.FORWARD
var person: Node3D
var _rest := 0.0
var _previous_waypoint := 0

func _ready() -> void:
	super._ready()
	person=visual.get_child(0)
	visual.rotation.y=atan2(-social_facing.x,-social_facing.z)
	if social_activity=="inspect": person.hand_provider=_work_gesture

func _physics_process(delta: float) -> void:
	# The reaction director owns movement until danger and recovery finish.
	# Keep a home route even for stationary roles so they return after fleeing.
	var normal:=not dead and not controlled_automatically
	var at_home:=not route.is_empty() and global_position.distance_squared_to(route[0])<.64
	if normal and social_activity=="walk":
		if waypoint!=_previous_waypoint: _rest=3.0+float(identity%4)
		_rest=maxf(0.0,_rest-delta)
	_previous_waypoint=waypoint
	var resting:=normal and ((social_activity!="walk" and at_home) or (social_activity=="walk" and _rest>0))
	person.activity="talk" if resting and social_activity=="talk" else ""
	var saved_speed:=speed
	if resting: speed=0.0
	elif normal and social_activity!="walk": speed=maxf(speed,3.5)
	super._physics_process(delta)
	if normal: speed=saved_speed
	if resting:
		if social_activity!="walk": visual.rotation.y=atan2(-social_facing.x,-social_facing.z)

func _work_gesture() -> Array:
	if dead or controlled_automatically or route.is_empty() or global_position.distance_squared_to(route[0])>=.64: return [null,null]
	return [null,person.to_global(Vector3(.19,1.15,.43+.04*sin(person.clock*1.2+identity)))]
