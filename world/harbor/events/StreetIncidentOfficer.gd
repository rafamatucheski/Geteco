extends "res://police/PoliceOfficer.gd"
## One foot patrol owns this call; it never switches to the player's pursuit.
var responding := false
var walking_home := false
var home_point := Vector2.ZERO

func _configure_tier() -> void:
	tier = UnitTier.PATROL
	max_health = 50
	speed = 112
	dropped_weapon = &"pistol"

func _ready() -> void:
	set_meta("quiet_patrol",true)
	set_meta("ambient_response",true)
	super._ready()
	collision_layer = 4
	collision_mask = 3
	home_point = global_position

func _physics_process(delta: float) -> void:
	if is_dead or is_flying:
		super._physics_process(delta)
		return
	# Damage to this officer may report a real player crime via the base class,
	# but an ambient chase cannot start a firefight against its unarmed suspect.
	response_aggression = 0
	if responding and is_instance_valid(target) and target.get_meta("ambient_crime",false):
		super._physics_process(delta)
		return
	velocity = _navigate_towards(home_point,38,delta) if walking_home and global_position.distance_to(home_point)>10 else Vector2.ZERO
	move_and_slide()
	walk_clock += delta*5
	if velocity.length()>1: model_root.rotation.y = -velocity.angle()-PI*.5
	left_upper_leg.rotation.x = sin(walk_clock)*.3 if velocity.length()>1 else 0
	right_upper_leg.rotation.x = -left_upper_leg.rotation.x
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

func return_home() -> void:
	target = null
	responding = false
	walking_home = true
	_reset_arrest_warning()
