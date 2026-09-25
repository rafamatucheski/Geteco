extends CharacterBody3D
signal injured(actor, amount: float)
var guard := false
var shotgun := false
var female := false
var fuel := false
var health := 80.0
var dead := false
var visual: Node3D
var weapon: Node3D
var heist
var cooldown := 0.0
func _ready() -> void:
	collision_layer=2
	collision_mask=7
	set_meta("gameplay_role","police" if guard else "civilian")
	set_meta("interior_actor",true)
	add_to_group("v2_damageable")
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius=.28
	shape.height=1.75
	collider.shape=shape
	collider.position.y=.875
	add_child(collider)
	if guard:
		visual=preload("res://runtime/BankGuardModel.gd").new()
		visual.uses_shotgun=shotgun
	elif fuel: visual=preload("res://runtime/FuelCashierModel.gd").new()
	else:
		visual=preload("res://assets/regions/source/world/harbor/events/BankClerkModel.gd").new()
		visual.appearance_female=female
	add_child(visual)
	if guard:
		# Share the native barrel basis, grip targets and muzzle with the guard rig.
		# Parenting a gun to the legacy forearm pointed it away from its target.
		visual.equip("shotgun" if shotgun else "pistol")
		weapon=visual.weapon
	if health<=0: _fall()
	elif not guard and heist != null:
		var reaction := preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd").install(self, visual, heist.session.world.gameplay)
		if reaction != null and heist.session.has_method("_on_workplace_threat_started"):
			reaction.threat_started.connect(Callable(heist.session, "_on_workplace_threat_started"))
func receive_damage(amount: float, _source: Node = null) -> void:
	if dead or amount<=0: return
	health=maxf(0,health-amount)
	if health<=0: _fall()
	injured.emit(self,amount)
func _fall() -> void:
	dead=true
	collision_layer=0
	collision_mask=0
	if is_instance_valid(visual): visual.rotation.x=-PI*.5
	if is_instance_valid(weapon): weapon.hide()
func _physics_process(delta: float) -> void:
	if dead or not guard or heist==null or not heist.inside("harbor_bank"): return
	var gameplay = heist.session.world.gameplay
	var player: Node3D = heist.session.world.player
	var direction := player.global_position-global_position
	direction.y=0
	var armed: bool = heist.session.state.equipped_weapon not in ["","fists"]
	var aiming: bool = armed or heist.data.bank_shots
	if aiming:
		visual.rotation.y=atan2(-direction.x,-direction.z)
	visual.update_pose(delta,aiming,false,0.0,0.0)
	if not heist.data.bank_shots or gameplay.health<=0: return
	cooldown=maxf(0,cooldown-delta)
	if cooldown>0 or direction.length()>18: return
	var origin: Vector3 = visual.muzzle_position()
	var end := player.global_position+Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(origin,end,3,[get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider!=player: return
	cooldown=1.55 if shotgun else .8
	visual.attack()
	gameplay._trace(origin,end,.08,.012)
	gameplay._sound("shotgun" if shotgun else "pistol",origin)
	gameplay.npc_gunfire.emit(origin, (end - origin).normalized(), self)
	gameplay.damage_player(24 if shotgun else 8)
