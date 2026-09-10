extends "res://PoliceOfficer.gd"
var post: Node
var home := Vector2.ZERO
var responding := false

func _configure_tier() -> void:
	tier=UnitTier.PATROL
	max_health=50
	speed=175
	dropped_weapon=&"pistol"

func _ready() -> void:
	local_security=true
	set_meta("quiet_patrol",true)
	super._ready()
	var camera := viewport_3d.get_camera_3d()
	var pixels := camera.unproject_position(Vector3.UP*1.45).distance_to(camera.unproject_position(Vector3.ZERO))
	sprite_3d_display.scale=Vector2.ONE*(20.0/maxf(1.0,pixels))
	sprite_3d_display.position=-(camera.unproject_position(Vector3.ZERO)-Vector2(viewport_3d.size)*.5)*sprite_3d_display.scale

func _physics_process(delta: float) -> void:
	if is_dead or is_flying:
		super._physics_process(delta)
		return
	if responding:
		if not is_instance_valid(target) or target.get("is_dead")==true or target.get("is_arrested")==true or target.global_position.distance_to(home)>650:
			responding=false
			security_alert=0
		else:
			super._physics_process(delta)
			return
	velocity=global_position.direction_to(home)*speed*.65 if global_position.distance_to(home)>5 else Vector2.ZERO
	move_and_slide()
	if not is_instance_valid(post) and global_position.distance_to(home)<=5: queue_free()

func respond(actor: Node2D) -> void:
	if is_dead: return
	target=actor
	security_alert=1
	responding=true
