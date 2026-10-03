extends CharacterBody3D
signal injured(actor, amount: float)
var guard := false
var shotgun := false
var female := false
var fuel := false
var generation := 0
var health := 80.0
var dead := false
var visual: Node3D
var weapon: Node3D
var heist
var cooldown := 0.0
var reaction_remaining := 1.25
var entry_remaining := 2.0
var _fall_meshes: Array[Dictionary] = []
var _floor_y := 0.0
var _death_pose
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
		visual.generation=generation
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
	if health<=0: _fall(true)
	elif not guard and heist != null:
		var reaction := preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd").install(self, visual, heist.session.world.gameplay)
		if reaction != null and heist.session.has_method("_on_workplace_threat_started"):
			reaction.threat_started.connect(Callable(heist.session, "_on_workplace_threat_started"))
func receive_damage(amount: float, source: Node = null) -> void:
	if dead or amount<=0: return
	health=maxf(0,health-amount)
	var impact := Vector3.ZERO
	if source is Node3D: impact = global_position - source.global_position
	if health<=0: _fall(false, impact)
	injured.emit(self,amount)
func _fall(restored := false, impact := Vector3.ZERO) -> void:
	dead=true
	collision_layer=0
	collision_mask=0
	velocity=Vector3.ZERO
	# The room owns persistent blood; the generic hit effect must not add a
	# second pool at the feet before the body has finished falling.
	set_meta("v2_blood_pool", true)
	if is_instance_valid(weapon): weapon.hide()
	# Bank/fuel rigs install their articulated body deferred from _ready.
	_present_fall.call_deferred(restored, impact)

func _present_fall(restored: bool, impact: Vector3) -> void:
	if not is_instance_valid(visual) or not is_inside_tree(): return
	preload("res://gameplay/CharacterFallPresentation3D.gd")._cancel_hit(self)
	preload("res://gameplay/CharacterFallPresentation3D.gd")._release_hands(visual)
	visual.set_process(false)
	_death_pose = preload("res://gameplay/street_physics/BodyImpactPose3D.gd").new()
	_death_pose.capture(visual)
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null and mesh.is_visible_in_tree(): _fall_meshes.append({"node":mesh, "box":mesh.get_aabb()})
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * .25, global_position + Vector3.DOWN * 2.0, 1))
	_floor_y = float(floor_hit.position.y) if not floor_hit.is_empty() else global_position.y
	var heading := _fall_direction(impact)
	var initial := visual.transform
	var initial_rotation := initial.basis.orthonormalized().get_rotation_quaternion()
	var target_rotation := (Basis(Vector3.UP.cross(heading).normalized(), PI * .5) * initial.basis.orthonormalized()).get_rotation_quaternion()
	var model_scale := initial.basis.get_scale()
	var pose_step := func(progress: float):
		if not is_instance_valid(visual): return
		var amount := smoothstep(.08, .90, progress)
		visual.basis = Basis(initial_rotation.slerp(target_rotation, amount)) * Basis.from_scale(model_scale)
		visual.position = initial.origin - heading * .38 * amount
		_death_pose.apply(progress, progress >= .9)
		_support_corpse()
	if restored:
		pose_step.call(1.0)
		_death_blood()
	else:
		var tween := create_tween()
		tween.tween_method(pose_step, 0.0, 1.0, .95)
		tween.tween_callback(_death_blood)

func _fall_direction(impact: Vector3) -> Vector3:
	var heading := Vector3(impact.x, 0, impact.z).normalized()
	if heading.is_zero_approx(): heading = Vector3.BACK
	var from := global_position + Vector3.UP * .35
	for turn in [0.0, PI * .5, -PI * .5, PI]:
		var candidate := heading.rotated(Vector3.UP, turn)
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + candidate * 1.6, 1))
		if hit.is_empty(): return candidate
	return heading

func _support_corpse() -> void:
	var bottom := INF
	for entry in _fall_meshes:
		var mesh: MeshInstance3D = entry.node
		if not is_instance_valid(mesh): continue
		var box: AABB = entry.box
		var transform := mesh.global_transform
		for corner in 8: bottom = minf(bottom, (transform * box.get_endpoint(corner)).y)
	if is_finite(bottom): visual.global_position.y += _floor_y + .012 - bottom

func _death_blood() -> void:
	if not is_inside_tree() or not is_instance_valid(visual): return
	var room := get_parent()
	var blood := room.get_node_or_null("RobberyBlood")
	if blood == null:
		blood = preload("res://gameplay/street_physics/GroundBlood3D.gd").new()
		room.add_child(blood)
		blood.name = "RobberyBlood"
	var bounds := AABB()
	var first := true
	for entry in _fall_meshes:
		var mesh: MeshInstance3D = entry.node
		if not is_instance_valid(mesh): continue
		var box: AABB = mesh.global_transform * entry.box
		bounds = box if first else bounds.merge(box)
		first = false
	var center := bounds.get_center() if not first else global_position
	center.y = _floor_y
	# Body ownership stays with Robberies until leaving the room. Registering it
	# in the street corpse budget would fade it and trigger _ensure_actors again.
	blood.spawn_pool(center, true)
	_fall_meshes.clear()
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
	entry_remaining=maxf(0.0,entry_remaining-delta)
	if not heist.data.bank_shots or gameplay.health<=0:
		reaction_remaining=1.25
		return
	# Telegraph the response; persisted hostility never fires on the admission frame.
	reaction_remaining=maxf(0.0,reaction_remaining-delta)
	if entry_remaining>0 or reaction_remaining>0: return
	cooldown=maxf(0,cooldown-delta)
	if cooldown>0 or direction.length()>18: return
	var origin: Vector3 = visual.muzzle_position()
	var end := player.global_position+Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(origin,end,3,[get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider!=player: return
	cooldown=1.8 if shotgun else .95
	visual.attack()
	gameplay._trace(origin,end,.08,.012)
	gameplay._sound("shotgun" if shotgun else "pistol",origin)
	gameplay.npc_gunfire.emit(origin, (end - origin).normalized(), self)
	gameplay.damage_player(18 if shotgun else 8)
