extends CharacterBody3D
## Native collision adapter for V1 MountainMonster. The legend never dies/pays loot.
var progression
var home := Vector3.ZERO
var patrol := PackedVector3Array()
var index := 0
var cooldown := 0.0
var retreat := 0.0
var model: Node3D

func _ready() -> void:
	collision_layer=4; collision_mask=7; floor_snap_length=.4
	set_meta("gameplay_role","mountain_shadow")
	add_to_group("v2_damageable")
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius=.45; shape.height=2.8
	collider.shape=shape; collider.position.y=1.4; add_child(collider)
	model=preload("res://activities/MountainShadowModel.gd").new()
	add_child(model)
	home=global_position
	patrol=PackedVector3Array([home,home+Vector3(-260,0,-230)/16,home+Vector3(180,0,-470)/16,home+Vector3(360,0,-160)/16])

func _physics_process(delta: float) -> void:
	if progression==null or progression.session.modal or not progression._outside(): return
	cooldown=maxf(0,cooldown-delta); retreat=maxf(0,retreat-delta)
	var player: CharacterBody3D = progression.session.world.player
	var target: Vector3 = home if retreat>0 else patrol[index]
	var distance := global_position.distance_to(player.global_position)
	var speed := 82.0/16.0
	if distance<430.0/16.0 and retreat<=0:
		target=player.global_position
		speed=(265.0 if progression.skiing else 155.0)/16.0
	if distance<34.0/16.0 and cooldown<=0:
		var ray := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP,player.global_position+Vector3.UP,3,[get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider==player:
			if progression.skiing: progression.crash(24)
			else: progression.session.world.gameplay.damage_player(24)
			cooldown=5; retreat=2.2; target=home
	var direction := target-global_position
	direction.y=0
	if direction.length()<28.0/16.0: index=(index+1)%patrol.size()
	direction=direction.normalized()
	velocity.x=direction.x*speed; velocity.z=direction.z*speed
	velocity.y=-1 if is_on_floor() else velocity.y-20*delta
	move_and_slide()
	model.rotation.y=lerp_angle(model.rotation.y,atan2(-direction.x,-direction.z),minf(1,delta*8))
	model.walking=Vector2(velocity.x,velocity.z).length_squared()>.01
	model.charging=distance<250.0/16.0 and retreat<=0
	model.animate(delta)

func receive_damage(_amount: float, _source: Node = null) -> void:
	retreat=4; index=0
