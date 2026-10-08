extends Node3D
## Three authored actors, admitted incrementally and never replenished on a kill.
## Combat uses Gameplay's moving projectile, cover, damage protection and loot.
signal cleared
const CAMP := preload("res://world/desert/DesertBanditCamp.gd")
const MAX_BANDITS := 3
const SPAWN_DISTANCE := 80.0
const DESPAWN_DISTANCE := 115.0
const AGGRO_DISTANCE := 24.0
const LEASH_DISTANCE := 38.0
const STATE_KEY := "desert_bandits"
var session
var actors: Dictionary = {}
var camp: Node3D
var _clock := 0.0
var _admission_wait := 0.0
var _paused := false
var _engaged := false
var _state_error_reported := false
var _known_mask := 0

static func default_state() -> Dictionary:
	return {"version":1,"defeated_mask":0}

static func valid_state(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=2 or not value.has("version") or not value.has("defeated_mask"): return false
	for key in ["version","defeated_mask"]:
		if not (value[key] is int or value[key] is float) or not is_finite(float(value[key])) or float(value[key])!=floorf(float(value[key])): return false
	return int(value.version)==1 and int(value.defeated_mask)>=0 and int(value.defeated_mask)<=7

func configure(owner_session) -> void:
	session=owner_session
	name="DesertBanditEncounter"
	if not session.state.world_state.has(STATE_KEY): session.state.world_state[STATE_KEY]=default_state()
	if valid_state(session.state.world_state[STATE_KEY]): _known_mask=int(session.state.world_state[STATE_KEY].defeated_mask)

func operational() -> bool:
	return is_instance_valid(session) and session.ready_for_play and session.state.region_id=="desert" and session.state.place_id.is_empty() and session.world.gameplay.health>0 and not session.modal and not session.world.player.input_locked and not session.has_position_transition() and not session.desert.busy()

func save_block_reason() -> String:
	return "Afaste-se do acampamento e encerre o combate antes de salvar." if _engaged and live_count()>0 else ""

func cancel_attempt() -> void:
	_release()
	_admission_wait=.5

func live_count() -> int:
	var result := 0
	for actor in actors.values():
		if is_instance_valid(actor) and not actor.dead: result+=1
	return result

func snapshot() -> Dictionary:
	return {"alive":live_count(),"resident":actors.size(),"engaged":_engaged,"paused":_paused,"camp_resident":is_instance_valid(camp),"defeated_mask":int(session.state.world_state.get(STATE_KEY,default_state()).get("defeated_mask",0))}

func _process(delta: float) -> void:
	_clock+=delta
	if _clock<.25 or not is_instance_valid(session) or not session.ready_for_play: return
	var elapsed := _clock
	_clock=0
	_admission_wait=maxf(0,_admission_wait-elapsed)
	if not session.state.world_state.has(STATE_KEY): session.state.world_state[STATE_KEY]=default_state()
	var saved: Variant=session.state.world_state[STATE_KEY]
	if not valid_state(saved):
		if not _state_error_reported: push_error("Invalid desert_bandits state; encounter suspended"); _state_error_reported=true
		_release(); return
	if int(saved.defeated_mask)!=_known_mask:
		# A restored save changes encounter ownership, never revives a corpse in
		# place or leaves an actor alive whose persistent slot is defeated.
		_release()
		_known_mask=int(saved.defeated_mask)
		_admission_wait=.5
	var world=session.world
	var outside: bool=session.state.region_id=="desert" and session.state.place_id.is_empty()
	var distance: float=world.player.global_position.distance_to(CAMP.CENTER)
	if not outside or world.gameplay.health<=0 or distance>DESPAWN_DISTANCE:
		_release(); return
	_paused=not operational()
	for actor in actors.values():
		if is_instance_valid(actor): actor.set_physics_process(not _paused and not actor.dead)
	if _paused: return
	var region: Node3D=session.controller.regions.get("desert")
	if not is_instance_valid(region): return
	if not is_instance_valid(camp):
		if distance>SPAWN_DISTANCE or not region.is_streaming_idle(): return
		region.prepare_collision_at(CAMP.CENTER)
		camp=CAMP.build()
		add_child(camp)
		# Physics synchronizes the shelter before capsule admission next tick.
		return
	var mask := int(saved.defeated_mask)
	for index in MAX_BANDITS:
		var actor=actors.get(index)
		if is_instance_valid(actor): continue
		actors.erase(index)
		if distance>SPAWN_DISTANCE or (mask&(1<<index))!=0 or _admission_wait>0: continue
		if get_tree().get_nodes_in_group("desert_bandits").size()>=MAX_BANDITS: break
		_admission_wait=.5
		_admit(index,region)
		break
	var target: Node3D=world.gameplay.pursuit_target()
	if CAMP.CENTER.distance_to(target.global_position)>LEASH_DISTANCE:
		_engaged=false
	elif not _engaged:
		for actor in actors.values():
			if is_instance_valid(actor) and not actor.dead and actor.global_position.distance_to(target.global_position)<=AGGRO_DISTANCE and world.gameplay.police_can_see(actor):
				_engaged=true
				break
	for actor in actors.values():
		if is_instance_valid(actor) and not actor.dead: actor.engaged=_engaged

func _admit(index: int, region: Node3D) -> void:
	var desired: Vector3=CAMP.ground(CAMP.CENTER+CAMP.POSTS[index])
	if not region.prepare_collision_at(desired): return
	var space: PhysicsDirectSpaceState3D=session.world.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(desired+Vector3.UP*2,desired-Vector3.UP,1)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or absf(float(hit.position.y)-desired.y)>.15 or float(hit.normal.y)<.95: return
	var point: Vector3=hit.position+Vector3.UP*.06
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new(); capsule.radius=.31; capsule.height=1.7
	query.shape=capsule; query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.86); query.collision_mask=7
	if not space.intersect_shape(query,1).is_empty(): return
	var actor := Bandit.new()
	actor.encounter=self
	actor.slot=index
	actor.configure(session.world.gameplay,index)
	actor.weapon_id="pistol"
	actor.position=point
	actor.died.connect(_actor_died.bind(index))
	add_child(actor)
	actors[index]=actor

func provoke(source: Node) -> void:
	if not operational(): return
	var world=session.world
	if source==world.player or (world.driving.occupied and source==world.driving.car): _engaged=true

func _actor_died(index: int) -> void:
	var saved: Dictionary=session.state.world_state[STATE_KEY]
	saved.defeated_mask=int(saved.defeated_mask)|(1<<index)
	_known_mask=int(saved.defeated_mask)
	if int(saved.defeated_mask)==7:
		_engaged=false
		cleared.emit()

func _release() -> void:
	_engaged=false
	_paused=false
	for actor in actors.values():
		if is_instance_valid(actor):
			actor.set_physics_process(false)
			actor.collision_layer=0
			actor.collision_mask=0
			actor.queue_free()
	actors.clear()
	if is_instance_valid(camp): camp.queue_free()
	camp=null

func _exit_tree() -> void:
	_release()

class Bandit extends "res://gameplay/CobraAgent.gd":
	var encounter: Node3D
	var slot := 0
	var home := Vector3.ZERO
	var shots_fired := 0
	var patrol_clock := 0.0
	var aim_time := 0.0

	func _ready() -> void:
		collision_layer=2; collision_mask=7; floor_snap_length=.4
		set_meta("gameplay_role","cobra")
		set_meta("region_id","desert")
		set_meta("character_name",["Lauro","Juca","Galo"][slot])
		set_meta("desert_bandit_slot",slot)
		add_to_group("iron_cobras"); add_to_group("v2_damageable"); add_to_group("desert_bandits")
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new(); capsule.radius=.3; capsule.height=1.7
		shape.shape=capsule; shape.position.y=.86; add_child(shape)
		visual=MODEL.new(); visual.tier=slot; visual.cobra_uniform=false; add_child(visual)
		if visual.weapon_id!="pistol":
			var old_weapon: Node3D=visual.weapon
			visual.equip("pistol")
			old_weapon.queue_free()
		visual.body.wardrobe.top_color=[Color("7f6950"),Color("59665d"),Color("925f46")][slot]
		visual.body.wardrobe.bottom_color=Color("423e35")
		visual.body._apply_colors()
		home=global_position
		engaged=false
		sensor=float(slot)*.07
		cooldown=1.2+float(slot)*.35

	func _physics_process(delta: float) -> void:
		if dead or not is_instance_valid(encounter) or not encounter.operational(): return
		cooldown=maxf(0,cooldown-delta)
		sensor-=delta
		patrol_clock+=delta
		var target: Node3D=gameplay.pursuit_target()
		if sensor<=0:
			sensor=.2
			sees_target=engaged and gameplay.police_can_see(self)
		var direction := target.global_position-global_position
		direction.y=0
		aim_time=aim_time+delta if sees_target else 0.0
		var destination := home
		if engaged:
			if direction.length()>9.0 and sees_target and home.distance_to(target.global_position)<30:
				destination=target.global_position
			else: destination=global_position
		else:
			# A short walk inside the clear front apron; never pathfind on city roads.
			destination=home+Vector3(sin(patrol_clock*.18+float(slot))*1.5,0,0)
		var move := destination-global_position; move.y=0
		move=Vector3.ZERO if move.length()<.2 else _steering.steer(self,move.normalized(),delta)*(1.8 if engaged else .55)
		velocity.x=move.x; velocity.z=move.z
		velocity.y=-1.0 if is_on_floor() else maxf(-18,velocity.y-20*delta)
		move_and_slide()
		gait+=Vector2(velocity.x,velocity.z).length()*delta*3.4
		var facing := direction if engaged else move
		if facing.length_squared()>.01: visual.rotation.y=lerp_angle(visual.rotation.y,atan2(-facing.x,-facing.z),1-exp(-8*delta))
		visual.update_pose(delta,sees_target,false,0.0,gait)
		if sees_target and aim_time>=.65 and cooldown<=0 and direction.length()<24:
			_shoot(target)

	func _shoot(_target: Node3D) -> void:
		# Production moving rounds raycast each advance; cover and god mode are
		# resolved by Gameplay, including the bridge from body to muzzle.
		if gameplay.civilian_shoot(self,visual.muzzle_position(),8.0):
			visual.attack()
			shots_fired+=1
			cooldown=1.35+float(slot)*.12

	func receive_damage(amount: float, source: Node = null) -> void:
		if dead or not is_finite(amount) or amount<=0: return
		if is_instance_valid(encounter): encounter.provoke(source)
		super.receive_damage(amount,source)
