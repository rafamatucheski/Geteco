extends "res://PoliceOfficer.gd"
var room: Node2D
var uses_shotgun := false
const PART = preload("res://world/shared/pedestrians/CitizenDetails.gd")
var arms: Array[MeshInstance3D] = []
var hands: Array[MeshInstance3D] = []
var weapon: Node3D
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
	PART.piece(head_node,Vector3(.29,.30,.27),Vector3(0,-.025,0),skin,true)
	PART.piece(head_node,Vector3(.055,.07,.06),Vector3(0,-.03,-.14),skin)
	for side in [-1,1]:
		PART.piece(head_node,Vector3(.035,.018,.02),Vector3(side*.065,.005,-.13),Color("22252b"))
		PART.piece(head_node,Vector3(.045,.07,.05),Vector3(side*.145,-.025,0),skin,true)
	# Solid crown covers the scalp; the brim is entirely above the face.
	PART.piece(head_node,Vector3(.33,.11,.30),Vector3(0,.145,0),cloth)
	PART.piece(head_node,Vector3(.34,.035,.20),Vector3(0,.105,-.16),cloth.darkened(.2))
	PART.piece(head_node,Vector3(.06,.05,.018),Vector3(0,.15,-.157),Color("dabd72"))
	for limb in [left_upper_leg,right_upper_leg,left_lower_leg,right_lower_leg]:
		for child in limb.get_children():
			if child is MeshInstance3D and child.mesh is CylinderMesh:
				var shape=BoxMesh.new()
				shape.size=Vector3(.135,child.mesh.height,.15)
				child.mesh=shape
	left_upper_arm.hide()
	right_upper_arm.hide()
	for i in 4:
		arms.append(PART.piece(model_root,Vector3(.095,1,.10),Vector3.ZERO,cloth if i%2==0 else skin))
	for i in 2: hands.append(PART.piece(model_root,Vector3(.085,.08,.09),Vector3.ZERO,skin,true))
	weapon=Node3D.new()
	model_root.add_child(weapon)
	var metal=Color("272d33")
	PART.piece(weapon,Vector3(.065,.085,.28 if uses_shotgun else .19),Vector3(0,0,-.08),metal)
	PART.piece(weapon,Vector3(.055,.12,.065),Vector3(0,-.07,0),Color("393330"))
	if uses_shotgun:
		PART.piece(weapon,Vector3(.06,.055,.38),Vector3(0,.015,-.38),metal)
		PART.piece(weapon,Vector3(.085,.07,.16),Vector3(0,-.035,-.28),Color("785638"))
		PART.piece(weapon,Vector3(.085,.10,.22),Vector3(0,-.025,.15),Color("785638"))
	muzzle_flash_3d.reparent(weapon)
	muzzle_flash_3d.position=Vector3(0,0,-.59 if uses_shotgun else -.19)
	model_root.rotation.y=PI
	_pose(false)
func _segment(part: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	part.position=(a+b)*.5
	part.scale.y=a.distance_to(b)
	part.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
func _pose(aiming: bool) -> void:
	if not is_instance_valid(weapon): return
	weapon.position=Vector3(.10,1.04 if aiming else .86,-.35 if aiming else -.22)
	weapon.rotation.x=0 if aiming else -.40
	var right=weapon.position+Vector3(0,-.075,0)
	var left=weapon.position+Vector3(-.025,-.035,-.27 if uses_shotgun else -.035)
	_segment(arms[0],Vector3(.23,1.05,0),Vector3(.28,.86,-.13))
	_segment(arms[1],Vector3(.28,.86,-.13),right)
	_segment(arms[2],Vector3(-.23,1.05,0),Vector3(-.25,.85,-.14))
	_segment(arms[3],Vector3(-.25,.85,-.14),left)
	hands[0].position=right
	hands[1].position=left
func _shoot_at_target(target_pos: Vector2) -> void:
	if not uses_shotgun:
		super._shoot_at_target(target_pos)
		return
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
	super.take_damage(amount,is_player_attacker)
	if is_dead and is_instance_valid(room): room.on_guard_down(self)

func _dispatch_emergency_coroner() -> void:
	# A área interna fica isolada da malha viária. Não mandar o rabecão
	# perseguir as coordenadas técnicas do corpo durante o assalto.
	pass
