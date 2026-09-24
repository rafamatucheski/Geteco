extends CharacterBody3D
const RELOAD_SECONDS := 1.691875 # Longest original pistol reload WAV.
var manager
var health := 50.0
var visual: Node3D
var weapon: Node3D
var dead := false
var clip := 12
var reload_remaining := 0.0
var cooldown := 0.0
var burst_pause := 0.0
var burst_shots := 0
var aim_time := 0.0
var response_aggression := 0.0
var repath := 0.0
var path := PackedVector3Array()
var path_index := 0
var gait := 0.0
func _ready() -> void:
	collision_layer=2
	collision_mask=7
	floor_snap_length=.3
	set_meta("gameplay_role","private_security")
	set_meta("local_security",true)
	set_meta("interior_actor",true)
	add_to_group("v2_damageable")
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=.28
	capsule.height=1.7
	collider.shape=capsule
	collider.position.y=.86
	add_child(collider)
	visual=preload("res://gameplay/PoliceModel.gd").new()
	add_child(visual)
	visual.scale*=Vector3(.84,1,.90)
	visual.mat_uniform.albedo_color=Color("454b42")
	weapon=Node3D.new()
	visual.right_lower_arm.add_child(weapon)
	weapon.position=Vector3(0,-.18,0)
	preload("res://gameplay/ArsenalWeapon3D.gd").build(weapon,"pistol")
	if health<=0: _fall()
func receive_damage(amount: float, source: Node=null) -> void:
	if dead or not is_finite(amount) or amount<=0: return
	health=maxf(0,health-amount)
	if health<=0: _fall()
	manager.injured(source)
func _fall() -> void:
	dead=true
	collision_layer=0
	collision_mask=0
	visual.rotation.x=-PI*.5
	weapon.hide()
	set_physics_process(false)
func _physics_process(delta: float) -> void:
	if dead or manager==null or not manager.active(): return
	cooldown=maxf(0,cooldown-delta)
	burst_pause=maxf(0,burst_pause-delta)
	if reload_remaining>0:
		reload_remaining=maxf(0,reload_remaining-delta)
		if reload_remaining==0: clip=12
	if not manager.alerted(): velocity=Vector3.ZERO; return
	response_aggression=12.0
	var target: Node3D=manager.target()
	if not is_instance_valid(target): return
	var direction := target.global_position-global_position
	direction.y=0
	var distance := direction.length()
	var visible_target := distance<=430.0/16.0 and can_see(target)
	aim_time=aim_time+delta if visible_target else 0.0
	visual.rotation.y=lerp_angle(visual.rotation.y,atan2(-direction.x,-direction.z),minf(1,14*delta))
	visual.right_upper_arm.rotation.x=-1.25
	visual.left_upper_arm.rotation.x=-1.1
	visual.left_lower_arm.rotation.z=-.65
	var desired := Vector3.ZERO
	if not visible_target or distance>180.0/16.0:
		repath-=delta
		if repath<=0:
			repath=1.2
			path=manager.gameplay().find_path(global_position,target.global_position)
			path_index=0
		while path_index<path.size() and global_position.distance_to(path[path_index])<.65: path_index+=1
		if path_index<path.size(): desired=(path[path_index]-global_position).normalized()*7.5
	elif distance<100.0/16.0: desired=-direction.normalized()*4.5
	velocity.x=desired.x
	velocity.z=desired.z
	velocity.y=0 if is_on_floor() else velocity.y-20*delta
	move_and_slide()
	gait+=delta*velocity.length()*2.5
	var swing := sin(gait)*.45 if desired.length_squared()>.01 else 0.0
	visual.left_upper_leg.rotation.x=swing
	visual.right_upper_leg.rotation.x=-swing
	if visible_target and distance<=360.0/16.0 and aim_time>=.65 and cooldown<=0 and burst_pause<=0 and reload_remaining<=0: shoot(target)
func can_see(target: Node3D) -> bool:
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*1.25,target.global_position+Vector3.UP,7,[get_rid()]))
	return not hit.is_empty() and hit.collider==target
func shoot(target: Node3D) -> bool:
	if clip<=0 or reload_remaining>0 or not can_see(target): return false
	clip-=1
	cooldown=.85+randf_range(0,.2)
	burst_shots+=1
	if burst_shots>=2: burst_shots=0; burst_pause=randf_range(1.7,2.5)
	var bullet=preload("res://runtime/garage_guards/Shot.gd").new()
	bullet.manager=manager
	bullet.shooter=self
	bullet.position=global_position+Vector3.UP*1.25
	bullet.velocity=(target.global_position+Vector3.UP-bullet.position).normalized().rotated(Vector3.UP,randf_range(-.13,.13))*55
	manager.add_child(bullet)
	manager.gameplay()._sound("pistol",global_position)
	manager.gameplay().npc_gunfire.emit(bullet.position,bullet.velocity.normalized(),self)
	if clip==0: reload_remaining=RELOAD_SECONDS; cooldown=0; burst_pause=0; burst_shots=0
	return true
