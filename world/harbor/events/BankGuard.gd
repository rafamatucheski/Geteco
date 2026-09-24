extends "res://police/PoliceOfficer.gd"
var room: Node2D
var uses_shotgun := false
var eyes: Array[MeshInstance3D] = []
var death_presented := false
const PART = preload("res://characters/pedestrians/CitizenDetails.gd")
func _configure_tier() -> void:
	tier=UnitTier.PATROL
	max_health=50
	speed=110
	dropped_weapon=&"shotgun" if uses_shotgun else &"pistol"
func _ready() -> void:
	local_security=true
	set_meta("quiet_patrol",true)
	super._ready()
	remove_from_group("police_officer")
	add_to_group("bank_security")
	_rebuild_uniform()
	model_root.scale = Vector3(.88, .94, .90)
	var rig := get_node("NPCCombatRig")
	rig.combat_pose=preload("res://world/harbor/events/BankGuardCombatPose.gd").new()
	rig.combat_pose.update(rig,1.0,false,false,0.0)
	collision_layer=4
	collision_mask=3
func _clear_parts(parent: Node3D) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D:
			child.hide()
func _rebuild_uniform() -> void:
	var cloth=Color("635544")
	var skin=Color("b98062") if uses_shotgun else Color("d6a582")
	_clear_parts(torso_node)
	_clear_parts(head_node)
	PART.piece(torso_node,Vector3(.37,.40,.25),Vector3.ZERO,cloth)
	PART.piece(torso_node,Vector3(.39,.055,.28),Vector3(0,-.19,0),Color("24282c"))
	for side in [-1,1]:
		PART.piece(torso_node,Vector3(.115,.10,.03),Vector3(side*.105,.07,-.14),cloth.darkened(.18))
		PART.piece(torso_node,Vector3(.09,.04,.15),Vector3(side*.17,.22,0),Color("33363a"))
	PART.piece(torso_node,Vector3(.055,.07,.025),Vector3(-.10,.15,-.16),Color("dabd72"))
	PART.piece(torso_node,Vector3(.06,.11,.055),Vector3(.19,-.15,0),Color("20252c"))
	PART.piece(head_node,Vector3(.26,.28,.245),Vector3(0,-.025,0),skin,true)
	PART.piece(head_node,Vector3(.055,.07,.06),Vector3(0,-.03,-.14),skin)
	for side in [-1,1]:
		eyes.append(PART.piece(head_node,Vector3(.035,.018,.02),Vector3(side*.065,.005,-.13),Color("22252b")))
		PART.piece(head_node,Vector3(.045,.07,.05),Vector3(side*.145,-.025,0),skin,true)
	# Solid crown covers the scalp; the brim is entirely above the face.
	var crown := PART.piece(head_node,Vector3.ONE,Vector3(0,.145,0),cloth)
	var cap := CylinderMesh.new()
	cap.top_radius=.17
	cap.bottom_radius=.155
	cap.height=.11
	cap.radial_segments=12
	crown.mesh=cap
	PART.piece(head_node,Vector3(.34,.035,.20),Vector3(0,.105,-.16),cloth.darkened(.2))
	PART.piece(head_node,Vector3(.06,.05,.018),Vector3(0,.15,-.157),Color("dabd72"))
	for limb in [left_upper_leg,right_upper_leg,left_lower_leg,right_lower_leg]:
		for child in limb.get_children():
			if child is MeshInstance3D and child.mesh is CylinderMesh:
				var shape=BoxMesh.new()
				shape.size=Vector3(.135,child.mesh.height,.15)
				child.mesh=shape
	# Keep the shared articulated arms, mesh arsenal and Dante combat poses.
	for limb in [left_upper_arm, right_upper_arm]:
		for part in limb.get_children():
			if part is MeshInstance3D:
				part.material_override = _make_mat(cloth, .8)
	# Antebraços contínuos até as mãos; pele igual à do rosto em ambos os lados.
	for limb in [left_lower_arm,right_lower_arm]:
		for part in limb.get_children():
			if part is MeshInstance3D and part!=muzzle_flash_3d:
				part.material_override=_make_mat(skin,.8)
				if part.mesh is CylinderMesh:
					part.mesh=part.mesh.duplicate()
					part.mesh.height=.20
					part.mesh.top_radius=.052
					part.mesh.bottom_radius=.045
					part.position.y=-.10
	model_root.rotation.y = PI
	_pose(false)
func _pose(aiming: bool) -> void:
	get_node("NPCCombatRig").aim_override = aiming
func _shoot_at_target(target_pos: Vector2) -> void:
	if not uses_shotgun:
		super._shoot_at_target(target_pos)
		return
	weapon_reload.equip(String(dropped_weapon))
	if not weapon_reload.consume(): return
	fire_cooldown=1.55
	for pellet in 6: _fire_single_bullet(target_pos,4,880,.16)
	_play_audio(ProceduralAudio.get_gunshot_shotgun_stream(),-5)
func _physics_process(delta: float) -> void:
	if is_dead or is_flying:
		super._physics_process(delta)
		return
	if not is_instance_valid(room) or not room.actor_inside():
		velocity=Vector2.ZERO
		_pose(false)
		return
	target=room.actor
	# Exibir uma arma provoca advertência, sem perseguição/prisão automática.
	if not room.shots_fired:
		velocity=Vector2.ZERO
		security_alert=0
		response_aggression=0
		if room.armed_warning:
			var direction := global_position.direction_to(target.global_position)
			model_root.rotation.y=lerp_angle(model_root.rotation.y,-direction.angle()-PI*.5,minf(1,delta*10))
		_pose(room.armed_warning)
		return
	security_alert=3
	response_aggression=12
	super._physics_process(delta)
	_pose(true)

func take_damage(amount: int, is_player_attacker: bool = false) -> void:
	if amount>0 and not is_dead and is_player_attacker and is_instance_valid(room): room._on_shot()
	# This custom uniform replaces the torso material. The inherited red flash
	# only tinted the remaining trousers, falsely suggesting every hit was a leg hit.
	var trousers := mat_uniform
	mat_uniform=null
	super.take_damage(amount,is_player_attacker)
	mat_uniform=trousers
	if is_dead and is_instance_valid(room): room.on_guard_down(self)

func _dispatch_emergency_coroner() -> void:
	# A área interna fica isolada da malha viária. Não mandar o rabecão
	# perseguir as coordenadas técnicas do corpo durante o assalto.
	pass

func _drop_loot() -> void:
	if death_presented: return
	death_presented=true
	var rig := get_node("NPCCombatRig")
	var camera := viewport_3d.get_camera_3d()
	var hand_pixel := camera.unproject_position(rig.weapon_mount_node.global_position)-Vector2(viewport_3d.size)*.5
	var hand_point := sprite_3d_display.to_global(hand_pixel)
	if has_meta("interior_actor_presentation"):
		hand_point = get_meta("interior_actor_presentation").project_node(rig.weapon_mount_node)
	rig.current_gun_mesh.hide()
	muzzle_flash_3d.hide()
	for eye in eyes:
		eye.mesh=eye.mesh.duplicate()
		eye.mesh.size=Vector3(.052,.006,.012)
		eye.position.z=-.146
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_ONCE
	var pickup := preload("res://world/harbor/events/BankGuardWeaponPickup.gd").new()
	pickup.weapon_id=dropped_weapon
	pickup.ammo_amount=8 if uses_shotgun else 12
	pickup.room=room
	# Aterrissa na circulação, separado do corpo e do cartão de segurança.
	var landing := preload("res://world/harbor/events/BankFloorItem.gd").clear_drop(room,global_position,Vector2(44 if uses_shotgun else -44,26))
	pickup.position=get_parent().to_local(landing)
	pickup.drop_origin=hand_point
	get_parent().call_deferred("add_child",pickup)
	# Mantém a chance de colete; a arma já foi solta exatamente uma vez.
	police_loot.weapon_drop_chance=0.0
	police_loot.weapon_pickup_scene=null
	if randf()<=police_loot.armor_drop_chance:
		var armor:=preload("res://world/harbor/events/BankArmorPickup.gd").new()
		armor.room=room
		armor.position=get_parent().to_local(preload("res://world/harbor/events/BankFloorItem.gd").clear_drop(room,global_position,Vector2(0,36)))
		get_parent().call_deferred("add_child",armor)
	police_loot.armor_drop_chance=0.0
	super._drop_loot()

func _create_3d_blood_puddle() -> void:
	var pool := preload("res://world/harbor/events/BankGuardBloodPool.gd").new()
	pool.guard=self
	get_parent().add_child(pool)

func _start_fall(impact := Vector2.ZERO) -> void:
	fall_presentation=preload("res://world/harbor/events/BankFloorFall.gd").new()
	fall_presentation.start(self,model_root,viewport_3d,impact)
	# Deita atravessado na circulação; nunca em direção ao tampo do balcão.
	fall_presentation.yaw=PI*.5 if uses_shotgun else -PI*.5
