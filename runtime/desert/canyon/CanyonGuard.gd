extends "res://gameplay/CobraAgent.gd"
## Authored foot soldiers. No city routing across the canyon's missing ground.
const LAYOUT := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const AUDIO := preload("res://gameplay/CombatAudio.gd")
const LOADOUT := ["ak47","smg","ak47","m4a1","smg","ak47","m4a1","ak47"]
var encounter: Node3D
var slot := 0
var home := Vector3.ZERO
var aim_time := 0.0
var shots_fired := 0
var patrol_clock := 0.0

func _ready() -> void:
	super._ready()
	set_meta("region_id","desert")
	set_meta("character_name","Contrabandista")
	set_meta("smuggler_slot",slot)
	add_to_group("desert_smugglers")
	weapon_id=LOADOUT[slot]
	max_health=200.0 if slot==7 else 150.0
	health=max_health
	var previous: Node3D=visual.weapon
	visual.equip(weapon_id)
	previous.queue_free()
	home=global_position
	engaged=false
	sensor=float(slot)*.04
	cooldown=.8+float(slot)*.12

func _physics_process(delta: float) -> void:
	if dead or not is_instance_valid(encounter) or not encounter.operational(): return
	cooldown=maxf(0,cooldown-delta)
	sensor-=delta
	patrol_clock+=delta
	var target: Node3D=gameplay.pursuit_target()
	if sensor<=0:
		sensor=.22
		sees_target=engaged and gameplay.police_can_see(self)
	var direction := target.global_position-global_position
	direction.y=0
	aim_time=aim_time+delta if sees_target else 0.0
	var destination := home+Vector3(sin(patrol_clock*.19+slot)*1.0,0,0)
	if engaged:
		destination=global_position
		if sees_target and direction.length()>11 and home.distance_to(target.global_position)<24:
			destination=target.global_position
		elif not sees_target: destination=home
	var move := destination-global_position
	move.y=0
	move=Vector3.ZERO if move.length()<.25 else _steering.steer(self,move.normalized(),delta)*(2.5 if engaged else .55)
	var next := global_position+move*.6
	if not LAYOUT.CAMP_BOUNDS.grow(-2.0).has_point(Vector2(next.x,next.z)) or LAYOUT.analytic_height(Vector2(next.x,next.z))<-.08: move=Vector3.ZERO
	velocity.x=move.x; velocity.z=move.z
	velocity.y=-1.0 if is_on_floor() else maxf(-18,velocity.y-20*delta)
	move_and_slide()
	gait+=Vector2(velocity.x,velocity.z).length()*delta*3.4
	var facing := direction if engaged else move
	if facing.length_squared()>.01: visual.rotation.y=lerp_angle(visual.rotation.y,atan2(-facing.x,-facing.z),1-exp(-8*delta))
	visual.update_pose(delta,sees_target,false,0.0,gait)
	if sees_target and aim_time>=.6 and cooldown<=0 and direction.length()<26:
		_shoot(target)

func _shoot(target: Node3D) -> void:
	if not gameplay.state.weapons_allowed() or gameplay._police_rounds.size()>=128: return
	# Share the production moving rounds, body-to-muzzle cover check and damage
	# protection without inheriting the police-only surrender ceasefire.
	var origin: Vector3=visual.muzzle_position()
	var direction := origin.direction_to(target.global_position+Vector3.UP).rotated(Vector3.UP,gameplay._rng.randf_range(-.085,.085))
	var data: Dictionary=CATALOG.get_weapon(weapon_id)
	var token: Dictionary=gameplay.effects.police_tracer(origin,direction,42.0) if is_instance_valid(gameplay.effects) else {}
	if is_instance_valid(gameplay.effects): gameplay.effects.muzzle_smoke(origin,direction)
	var ray := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*1.1,origin,7,[get_rid()])
	var blocked := get_world_3d().direct_space_state.intersect_ray(ray)
	gameplay._police_rounds.append({"point":origin,"direction":direction,"speed":42.0,"distance":0.0,"range":float(data.max_range)/16.0,"damage":22.0 if weapon_id!="smg" else 17.0,"data":data,"source":weakref(self),"rid":get_rid(),"visual":token,"blocked":blocked})
	visual.attack()
	gameplay.npc_gunfire.emit(origin,direction,self)
	gameplay._play_stream(AUDIO.gunfire_take(weapon_id,gameplay._rng),origin,gameplay.NPC_GUNFIRE_DB,1.0,gameplay.HEARING_GUNFIRE)
	shots_fired+=1
	burst=(burst+1)%3
	cooldown=float(data.fire_interval) if burst!=0 else 1.0+float(slot%3)*.13

func receive_damage(amount: float, source: Node=null) -> void:
	if dead or not is_finite(amount) or amount<=0: return
	if is_instance_valid(encounter): encounter.provoke(source)
	var previous_loot: int=gameplay._loot.size()
	super.receive_damage(amount,source)
	if dead and is_instance_valid(encounter):
		for index in range(previous_loot,gameplay._loot.size()): encounter.track_loot(gameplay._loot[index])
