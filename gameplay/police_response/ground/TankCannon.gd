extends Node3D
## One weapon for player and police tanks. Only awake during recoil, reload or
## flight; each shell sweeps its entire step. BlastQuery visits every overlapping body.
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const BLAST_QUERY := preload("res://gameplay/BlastQuery.gd")
const STREET := preload("res://gameplay/street_physics/StreetPhysics.gd")
const AUDIO := preload("res://audio/tank/TankAudio.gd")
const COOLDOWN := 3.0
const SPEED := 80.0
const RANGE := 120.0
const DIRECT_DAMAGE := 180.0
const BLAST_DAMAGE := 100.0
const BLAST_RADIUS := 5.0
const MAX_SHELLS := 2
const TURN_RATE := 2.1
const PITCH_RATE := 1.1
static var _shell_mesh: SphereMesh
static var _shell_material: StandardMaterial3D
var vehicle: CharacterBody3D
var turret: Node3D
var barrel: Node3D
var recoil: Node3D
var muzzle: Node3D
var cooldown := 0.0
var shot_count := 0
var impact_count := 0
var shells: Array[Dictionary] = []
var _recoil_left := 0.0

func configure(car: CharacterBody3D) -> void:
	vehicle = car
	turret = car.visual.get_node_or_null("TankTurret")
	if turret == null: return
	barrel = turret.get_node_or_null("TankBarrel")
	recoil = turret.get_node_or_null("TankBarrel/BarrelRecoil")
	muzzle = turret.get_node_or_null("TankBarrel/BarrelRecoil/Muzzle")
	set_physics_process(false)

func aim_at(point: Vector3, delta: float) -> void:
	if not point.is_finite() or not is_instance_valid(turret) or not is_instance_valid(barrel) or not turret.is_inside_tree(): return
	# Derive yaw from the parent's current world transform: the hull can turn
	# beneath the turret while the gun keeps tracking the same world point.
	var local_point: Vector3 = turret.get_parent().to_local(point)-turret.position
	if Vector2(local_point.x,local_point.z).length_squared() < .01: return
	var yaw := atan2(-local_point.x,-local_point.z)
	turret.rotation.y = rotate_toward(turret.rotation.y,yaw,maxf(delta,0.0)*TURN_RATE)
	var relative := point-barrel.global_position
	var pitch := clampf(atan2(relative.y,Vector2(relative.x,relative.z).length()),deg_to_rad(-12.0),deg_to_rad(24.0))
	barrel.rotation.x = rotate_toward(barrel.rotation.x,pitch,maxf(delta,0.0)*PITCH_RATE)

func muzzle_position() -> Vector3:
	return muzzle.global_position if is_instance_valid(muzzle) and muzzle.is_inside_tree() else Vector3.ZERO

func is_aligned(point: Vector3, tolerance: float = .06) -> bool:
	if not is_instance_valid(muzzle) or not muzzle.is_inside_tree() or not point.is_finite(): return false
	var direction := muzzle_position().direction_to(point)
	return direction.length_squared() > .5 and (-muzzle.global_basis.z).normalized().dot(direction) >= cos(tolerance)

func fire(gameplay: Node3D, police_control: bool = false) -> bool:
	if cooldown > 0.0 or shells.size() >= MAX_SHELLS or not _can_fire(gameplay,police_control): return false
	var source: Node3D = vehicle if police_control else gameplay.player
	var excluded: Array[RID] = [vehicle.get_rid()]
	if not police_control and source is CollisionObject3D: excluded.append(source.get_rid())
	var origin := muzzle_position()
	# Prevent the long barrel from placing a round beyond a wall. The hull is
	# excluded only from its own launch, never from other tanks' sweeps.
	var bridge := PhysicsRayQueryParameters3D.create(turret.global_position+Vector3.UP*.28,origin,7,excluded)
	if not get_world_3d().direct_space_state.intersect_ray(bridge).is_empty(): return false
	var direction := (-muzzle.global_basis.z).normalized()
	var visual := _make_shell(origin)
	shells.append({"point":origin,"direction":direction,"remaining":RANGE,"source":weakref(source),"gameplay":weakref(gameplay),"police":police_control,"excluded":excluded,"visual":visual})
	cooldown = COOLDOWN
	shot_count += 1
	_recoil_left = .30
	recoil.position.z = .22
	set_physics_process(true)
	gameplay._play_stream(AUDIO.fire_stream(),origin,0.0,1.0,180.0)
	if is_instance_valid(gameplay.effects): gameplay.effects.backblast(origin,direction)
	if not police_control:
		gameplay._kick_camera(.16)
		gameplay.report_observed_crime(4,vehicle.global_position,"explosion",vehicle)
	return true

func _can_fire(gameplay: Node3D, police_control: bool) -> bool:
	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree() or vehicle.health <= 0 or not is_instance_valid(muzzle): return false
	if not _combat_allowed(gameplay) or gameplay.health <= 0 or gameplay.police_surrendering(): return false
	if police_control:
		return vehicle.external_input and vehicle.controlled and gameplay.police_force_authorized()
	return vehicle.controlled and not vehicle.external_input and not vehicle.input_locked and not vehicle.engine_disabled and is_instance_valid(gameplay.player) and not gameplay.player.input_locked

func _combat_allowed(gameplay: Node3D) -> bool:
	return is_instance_valid(gameplay) and gameplay.is_inside_tree() and gameplay.enabled and gameplay.state != null and gameplay.state.weapons_allowed() and not get_tree().paused

func _physics_process(delta: float) -> void:
	cooldown = maxf(0.0,cooldown-delta)
	_recoil_left = maxf(0.0,_recoil_left-delta)
	if is_instance_valid(recoil): recoil.position.z = .22*pow(_recoil_left/.30,2.0)
	for index in range(shells.size()-1,-1,-1):
		var shell: Dictionary = shells[index]
		var gameplay: Node3D = shell.gameplay.get_ref()
		var source: Node3D = shell.source.get_ref()
		# Transition/garage and surrender cancel airborne police shells too.
		if not _combat_allowed(gameplay) or source == null or (shell.police and (gameplay.police_surrendering() or not gameplay.police_force_authorized())):
			_remove_shell(index)
			continue
		var distance := minf(SPEED*maxf(delta,0.0),shell.remaining)
		var end: Vector3 = shell.point+shell.direction*distance
		var ray := PhysicsRayQueryParameters3D.create(shell.point,end,7,shell.excluded)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			_detonate(gameplay,source,hit,shell.direction,shell.police)
			_remove_shell(index)
			continue
		shell.remaining -= distance
		shell.point = end
		if is_instance_valid(shell.visual): shell.visual.global_position = end
		if shell.remaining <= .001: _remove_shell(index)
	if cooldown <= 0.0 and _recoil_left <= 0.0 and shells.is_empty(): set_physics_process(false)

func _remove_shell(index: int) -> void:
	var visual: Node3D = shells[index].visual
	if is_instance_valid(visual): visual.queue_free()
	shells.remove_at(index)

func _detonate(gameplay: Node3D, source: Node3D, hit: Dictionary, direction: Vector3, police_control: bool) -> void:
	if not _combat_allowed(gameplay): return
	impact_count += 1
	var point: Vector3 = hit.position
	var direct: Object = hit.collider
	var seen: Dictionary = {}
	if direct is Node3D:
		seen[direct.get_instance_id()] = true
		if _damage_allowed(direct,source,police_control):
			var amount := 55.0 if direct == gameplay.player else DIRECT_DAMAGE
			gameplay._damage(direct,amount,source)
			gameplay._hit_effect(hit,amount,direction)
			_impulse(direct,direction,1.0)
	# Offset toward the incoming side so the blocking wall also blocks splash.
	var blast_origin: Vector3 = point+hit.normal*.06
	var sphere := SphereShape3D.new()
	sphere.radius = BLAST_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform.origin = blast_origin
	query.collision_mask = 6
	for result in BLAST_QUERY.intersect_bodies(get_world_3d().direct_space_state,query):
		var actor := result.collider as Node3D
		if actor == null or seen.has(actor.get_instance_id()): continue
		seen[actor.get_instance_id()] = true
		if not _damage_allowed(actor,source,police_control): continue
		var target := actor.global_position+Vector3.UP
		var ray := PhysicsRayQueryParameters3D.create(blast_origin,target,1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		var falloff := clampf(1.0-blast_origin.distance_to(target)/BLAST_RADIUS,0.0,1.0)
		if falloff <= 0.0: continue
		var amount := minf(BLAST_DAMAGE*falloff,45.0) if actor == gameplay.player else BLAST_DAMAGE*falloff
		gameplay._damage(actor,amount,source)
		gameplay._hit_effect({"collider":actor,"position":target,"normal":Vector3.UP},amount,blast_origin.direction_to(target))
		_impulse(actor,blast_origin.direction_to(target),falloff)
	gameplay._play_stream(AUDIO.impact_stream(),point,-2.0,1.0,160.0)
	if is_instance_valid(gameplay.effects): gameplay.effects.explosion(point,BLAST_RADIUS)
	if is_instance_valid(gameplay.player): gameplay._kick_camera(.28*clampf(1.0-gameplay.player.global_position.distance_to(point)/(BLAST_RADIUS*4.0),0.0,1.0))
	gameplay.explosion_occurred.emit(point,BLAST_RADIUS,source)

func _damage_allowed(actor: Node3D, source: Node3D, police_control: bool) -> bool:
	if actor == vehicle or actor == source or vehicle.is_ancestor_of(actor) or source.is_ancestor_of(actor) or PROTECTION.is_protected(actor): return false
	# The police gun cannot injure its own dismounted crew in the blast.
	return not (police_control and (actor.get_meta("gameplay_role","") == "police" or actor.has_meta("dispatch_unit")))

func _impulse(actor: Node3D, direction: Vector3, strength: float) -> void:
	if PROTECTION.is_protected(actor): return
	var push := direction*8.0*strength
	if actor is RigidBody3D:
		actor.apply_central_impulse(push*minf(actor.mass,8.0))
	elif actor is CharacterBody3D and "horizontal_velocity" in actor:
		push.y = 0.0
		if is_instance_valid(STREET.instance): STREET.instance._add_slide(actor,push,.25*strength)
		else: actor.horizontal_velocity += push

func _make_shell(point: Vector3) -> MeshInstance3D:
	if _shell_mesh == null:
		_shell_mesh = SphereMesh.new()
		_shell_mesh.radius = .085
		_shell_mesh.height = .17
		_shell_mesh.radial_segments = 8
		_shell_mesh.rings = 4
		_shell_material = StandardMaterial3D.new()
		_shell_material.albedo_color = Color("ffc879")
		_shell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shell := MeshInstance3D.new()
	shell.mesh = _shell_mesh
	shell.material_override = _shell_material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	shell.top_level = true
	shell.global_position = point
	return shell
