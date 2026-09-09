extends "res://PoliceOfficer.gd"
var patrol_route := PackedVector2Array()
var patrol_index := 0
var alerted := false
var lost_sight := 0.0

func _ready() -> void:
	set_meta("quiet_patrol",true)
	super._ready()
	collision_layer=4
	collision_mask=3
	add_to_group("foot_patrol")
	get_node("/root/WantedManager").crime_reported.connect(_on_crime)

func _on_crime(_severity: int) -> void:
	if is_dead: return
	var suspect: Node2D = get_node("/root/WantedManager").get_pursuit_target()
	if not is_instance_valid(suspect) or global_position.distance_to(suspect.global_position)>300: return
	target=suspect
	if _has_target_sight():
		alerted=true
		lost_sight=0
	else: target=null

func _physics_process(delta: float) -> void:
	if is_dead or is_flying:
		super._physics_process(delta)
		return
	var wm := get_node("/root/WantedManager")
	if not alerted and wm.current_stars>0: _on_crime(0)
	if alerted:
		if is_instance_valid(target) and _has_target_sight():
			lost_sight=0
			wm.time_hidden=0
		else: lost_sight+=delta
		if wm.current_stars==0 or lost_sight>8:
			alerted=false
			target=null
			_reset_arrest_warning()
		else:
			viewport_3d.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			super._physics_process(delta)
			return
	if patrol_route.size()<2: return
	var goal := patrol_route[patrol_index]
	if global_position.distance_to(goal)<12:
		patrol_index=(patrol_index+1)%patrol_route.size()
		goal=patrol_route[patrol_index]
	velocity=_navigate_towards(goal,34,delta)
	if preload("res://world/harbor/HarborPedestrianRoutes.gd").crossing_wait(self,goal): velocity=Vector2.ZERO
	move_and_slide()
	if velocity.length()>1:
		model_root.rotation.y=-velocity.angle()-PI*.5
		walk_clock+=delta*5
	left_upper_leg.rotation.x=sin(walk_clock)*.3 if velocity.length()>1 else 0.0
	right_upper_leg.rotation.x=-left_upper_leg.rotation.x
	var viewer := get_tree().get_first_node_in_group("player") as Node2D
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_ALWAYS if viewer and viewer.global_position.distance_to(global_position)<900 else SubViewport.UPDATE_DISABLED
