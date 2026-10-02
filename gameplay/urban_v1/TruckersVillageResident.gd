extends CharacterBody3D
## Local resident: deliberate strolling with physical swept movement, bounded
## pursuit, and line-of-sight combat only after the village conflict is active.
signal attacked(actor,source)
signal died(actor)
var definition: Dictionary = {}
var gameplay: Node
var model: Node3D
var visual: Node3D:
	get: return model
var health := 90.0
var dead := false
var hostile := false
var target: Node3D
var home := Vector3.ZERO
var patrol_points := PackedVector3Array()
var point_index := 0
var walk_speed := 1.2
var stationary := false
var _pause := 1.0
var _blocked := 0.0
var _shot_left := 1.4
var shots_fired := 0
var active := true
var weapon_id := "pistol"
var last_pellet_hits := 0
var reinforcement_entry := Vector3.INF
var _reinforcement_home := Vector3.INF

func respond_to_house(entry: Vector3) -> void:
	if not stationary:
		reinforcement_entry=entry
		_reinforcement_home=entry

func configure(spec: Dictionary,controller: Node = null) -> void:
	definition = spec.duplicate(true)
	gameplay = controller
	name = str(spec.get("id","VillageResident"))
	position = spec.get("position",Vector3.ZERO)
	stationary = bool(spec.get("stationary",false))
	weapon_id = "shotgun" if spec.get("weapon","pistol") == "shotgun" else "pistol"
	walk_speed = 1.08+float(int(spec.get("variant",0))%3)*.12
	for point in spec.get("route",[]): patrol_points.append(point)
	_pause = .5+float(int(spec.get("variant",0))%3)*1.7
	set_meta("gameplay_role","civilian")
	set_meta("persistent_id",name)

func _ready() -> void:
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .3
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.75
	collider.shape = capsule
	collider.position.y = .88
	add_child(collider)
	model = preload("res://gameplay/urban_v1/TruckersVillageResidentModel.gd").new()
	model.resident_variant = int(definition.get("variant",0))
	model.weapon_id = weapon_id
	add_child(model)
	home = global_position
	add_to_group("v2_damageable")
	set_meta("truckers_village_resident",true)

func set_active(value: bool) -> void:
	if active == value and visible == value: return
	active = value
	visible = value
	collision_layer = 2 if value and not dead else 0
	set_physics_process(value and not dead)
	model.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if value: model.teleported()
	else: velocity = Vector3.ZERO

func set_hostile(value: bool,source: Node3D = null) -> void:
	if dead: return
	if hostile == value and target == source: return
	hostile = value
	target = source if value else null
	_shot_left = 1.4
	model.set_armed(value)
	if not value:
		reinforcement_entry=Vector3.INF
		_reinforcement_home=Vector3.INF
		_pause = 2.0
		# Rejoin the closest authored node; never teleport into a home/prop.
		var closest := INF
		for i in patrol_points.size():
			var distance := global_position.distance_squared_to(patrol_points[i])
			if distance<closest: closest=distance; point_index=i

func _physics_process(delta: float) -> void:
	if dead or not active: return
	var wanted := Vector3.ZERO
	var facing := Vector3.ZERO
	_shot_left = maxf(0,_shot_left-delta)
	if hostile and is_instance_valid(target):
		var offset := target.global_position-global_position
		offset.y = 0
		facing = offset
		# The conflict belongs to this settlement; no pursuit across Harbor.
		# Tonico defends his service point; roaming neighbours may pursue.
		if _reinforcement_home.is_finite() and _reinforcement_home.distance_to(target.global_position)>24:
			reinforcement_entry=Vector3.INF
			_reinforcement_home=Vector3.INF
		if not stationary and _reinforcement_home.is_finite():
			var approach := reinforcement_entry-global_position if reinforcement_entry.is_finite() else offset
			approach.y=0
			if reinforcement_entry.is_finite() and approach.length()<1.0: reinforcement_entry=Vector3.INF
			if approach.length()>(.5 if reinforcement_entry.is_finite() else 5.0):
				wanted=approach.normalized()*1.7
				facing=approach
		elif not stationary and offset.length()>7 and offset.length()<25 and home.distance_to(target.global_position)<32:
			wanted = offset.normalized()*1.7
		_try_shoot()
	elif not stationary and not patrol_points.is_empty():
		_pause = maxf(0,_pause-delta)
		if _pause<=0:
			var offset := patrol_points[point_index]-global_position
			offset.y = 0
			if offset.length()<.24:
				point_index = (point_index+1)%patrol_points.size()
				_pause = 2.2+float(point_index%3)*1.3
			else:
				wanted = offset.normalized()*minf(walk_speed,maxf(.35,offset.length()*1.4))
				facing = offset
	velocity.x = move_toward(velocity.x,wanted.x,delta*2.8)
	velocity.z = move_toward(velocity.z,wanted.z,delta*2.8)
	velocity.y = -1.0 if is_on_floor() else maxf(-18,velocity.y-20*delta)
	var before := global_position
	move_and_slide()
	var travelled := Vector2(global_position.x-before.x,global_position.z-before.z).length()
	if wanted.length_squared()>.05 and travelled<delta*.12:
		_blocked += delta
		if _blocked>1.5 and not hostile and not patrol_points.is_empty():
			point_index = (point_index+1)%patrol_points.size()
			_pause = 2
			_blocked = 0
	else: _blocked = 0
	if facing.length_squared()>.01:
		model.rotation.y = lerp_angle(model.rotation.y,atan2(facing.x,facing.z),1-exp(-6*delta))
	model.walking = travelled>delta*.12
	model.activity = "walk" if model.walking else "talk"

func _try_shoot() -> void:
	if dead or not active or not hostile or _shot_left>0 or not is_instance_valid(gameplay) or not is_instance_valid(target): return
	if gameplay.get("health") == null or float(gameplay.health)<=0: return
	if target.global_position.distance_to(global_position)>(11.0 if weapon_id=="shotgun" else 16.0): return
	var origin: Vector3 = model.muzzle_position()
	var end := target.global_position+Vector3.UP
	var direction := end-origin
	var forward: Vector3 = model.global_basis.z
	if Vector3(direction.x,0,direction.z).normalized().dot(forward)<.97: return
	var ray := PhysicsRayQueryParameters3D.create(origin,end,7,[get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.collider!=target: return
	_shot_left = 2.4 if weapon_id=="shotgun" else 1.4
	shots_fired += 1
	model.attack()
	if gameplay.has_method("_sound"): gameplay._sound(weapon_id,origin)
	if gameplay.has_signal("npc_gunfire"): gameplay.npc_gunfire.emit(origin,direction.normalized(),self)
	if weapon_id=="shotgun":
		_fire_pellets(origin,end)
	else:
		if gameplay.has_method("_trace"): gameplay._trace(origin,end,.08,.012)
		gameplay.damage_player(6)

func _fire_pellets(origin: Vector3, end: Vector3) -> void:
	var direction := (end-origin).normalized()
	var right := direction.cross(Vector3.UP).normalized()
	var up := right.cross(direction).normalized()
	var spread := origin.distance_to(end)*.035
	last_pellet_hits = 0
	# Every pellet owns a real physics ray: partial cover blocks its own share
	# of the blast instead of applying guaranteed damage through a wall.
	for offset in [Vector2.ZERO,Vector2(-.9,-.1),Vector2(.9,.1),Vector2(-.45,.65),Vector2(.45,.65),Vector2(-.45,-.65),Vector2(.45,-.65)]:
		var tip: Vector3 = end+(right*offset.x+up*offset.y)*spread
		var ray := PhysicsRayQueryParameters3D.create(origin,tip,7,[get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider==target: last_pellet_hits+=1
		if gameplay.has_method("_trace"): gameplay._trace(origin,hit.position if not hit.is_empty() else tip,.08,.008)
	if last_pellet_hits>0: gameplay.damage_player(last_pellet_hits*4)

func receive_damage(amount: float,source: Node = null) -> void:
	if dead or not is_finite(amount) or amount<=0: return
	health = maxf(0,health-amount)
	attacked.emit(self,source)
	var impact: Vector3 = global_position-source.global_position if source is Node3D else Vector3.ZERO
	if health>0:
		model.take_hit(impact,clampf(amount/40,.1,1))
		return
	dead = true
	hostile = false
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	model.set_armed(false)
	model.hand_provider = Callable()
	if has_meta("v2_burning"): preload("res://gameplay/BurningActor.gd").char_body(self)
	preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(self,model,impact)
	died.emit(self)
	if is_instance_valid(gameplay) and gameplay.get("emergency")!=null: gameplay.emergency.report_injury(self,true)
