extends CharacterBody3D

signal died
const MODELS := [preload("res://assets/gameplay/cobra_0.scn"), preload("res://assets/gameplay/cobra_1.scn"), preload("res://assets/gameplay/cobra_2.scn")]
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
var gameplay: Node3D
var tier := 0
var health := 80.0
var max_health := 80.0
var dead := false
var visual: Node3D
var weapon_id := "pistol"
var cooldown := 2.0
var sensor := 0.0
var sees_target := false
var last_known := Vector3.ZERO
var path := PackedVector3Array()
var waypoint := 0
var repath := 0.0
var gait := 0.0
var left_leg: Node3D
var right_leg: Node3D
var engaged := true
var burst := 0
var retreated := false
var retreat := Vector3.ZERO
var retreat_time := 0.0
## Desvio local (passo lateral ao encostar em alguém, troca de lado se travar). O roteador não enxerga corpos
## em movimento, então sem isto dois agentes no mesmo corredor se empurravam até o replano, que dava a mesma rota.
var _steering := preload("res://gameplay/crowd/PedestrianSteering.gd").new()
var alerted := false

func configure(p_gameplay: Node3D, p_tier: int = 0) -> void:
	gameplay = p_gameplay
	tier = clampi(p_tier, 0, 2)
	weapon_id = ["pistol", "shotgun", "smg"][tier]
	max_health = 110 if tier == 2 else 80
	health = max_health

func _ready() -> void:
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = 0.3
	set_meta("gameplay_role", "cobra")
	set_meta("character_name", ["Ren", "Haruka", "Takeshi"][tier])
	add_to_group("iron_cobras")
	add_to_group("v2_damageable")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.86
	add_child(shape)
	visual = MODELS[tier].instantiate()
	visual.scale *= 1.28
	add_child(visual)
	left_leg = visual.find_child("left_upper_leg", true, false)
	right_leg = visual.find_child("right_upper_leg", true, false)
	var right_arm := visual.find_child("right_upper_arm", true, false) as Node3D
	var left_arm := visual.find_child("left_upper_arm", true, false) as Node3D
	if right_arm: right_arm.rotation.x = -1.4
	if left_arm: left_arm.rotation.x = -1.15
	last_known = global_position

func _physics_process(delta: float) -> void:
	if dead or not engaged or gameplay == null: return
	if gameplay.player.input_locked or gameplay.health <= 0: return
	cooldown = maxf(0, cooldown - delta)
	sensor -= delta
	repath -= delta
	if sensor <= 0:
		sensor = 0.15
		sees_target = gameplay.police_can_see(self)
		if sees_target:
			last_known = gameplay.pursuit_target().global_position
			alerted = true
	if not alerted: last_known = global_position
	var target: Node3D = gameplay.pursuit_target()
	var direction := last_known - global_position
	direction.y = 0
	var distance := direction.length()
	if tier == 2 and health <= max_health * 0.55 and not retreated:
		retreated = true
		retreat_time = 5.0
		var away := -direction.normalized()
		for angle in [0.0, PI / 2, -PI / 2, PI]:
			var candidate := global_position + away.rotated(Vector3.UP, angle) * 4
			if gameplay._clear_at(candidate):
				retreat = candidate
				break
	if sees_target and distance < float(CATALOG.get_weapon(weapon_id).max_range) / 16.0 and cooldown <= 0:
		_shoot(target)
	if direction.length_squared() > 0.01: visual.rotation.y = atan2(-direction.x, -direction.z)
	var destination := last_known
	if retreat_time > 0:
		retreat_time -= delta
		destination = retreat
	if repath <= 0:
		repath = 1.2
		path = gameplay.find_path(global_position, destination)
		waypoint = 0
	if waypoint < path.size():
		destination = path[waypoint]
		if global_position.distance_to(destination) < 0.6: waypoint += 1
	var movement := destination - global_position
	movement.y = 0
	if (distance < (4.0 if tier == 1 else 7.0) and sees_target and retreat_time <= 0) or movement.length() < 0.4:
		movement = Vector3.ZERO
	else:
		movement = _steering.steer(self, movement.normalized(), delta) * (38.0 + tier * 3) / 16.0
	velocity.x = movement.x
	velocity.z = movement.z
	velocity.y = -1 if is_on_floor() else velocity.y - 20 * delta
	move_and_slide()
	gait += Vector2(velocity.x, velocity.z).length() * delta * 3.4
	if left_leg: left_leg.rotation.x = sin(gait) * 0.55
	if right_leg: right_leg.rotation.x = -sin(gait) * 0.55

func _shoot(target: Node3D) -> void:
	var data: Dictionary = CATALOG.get_weapon(weapon_id)
	var origin := global_position + Vector3.UP * 1.1
	var direction := (target.global_position + Vector3.UP - origin).normalized()
	for pellet in int(data.pellets):
		var spread: Vector3 = direction.rotated(Vector3.UP, randf_range(-float(data.spread), float(data.spread)))
		var ray := PhysicsRayQueryParameters3D.create(origin, origin + spread * float(data.max_range) / 16.0, 7, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		var end: Vector3 = hit.get("position", ray.to)
		gameplay._trace(origin, end, 0.065, 0.014)
		if not hit.is_empty(): gameplay._damage(hit.collider, float(data.damage), self)
	gameplay._sound(weapon_id, origin)
	gameplay.npc_gunfire.emit(origin, direction, self)
	if weapon_id == "smg":
		burst = (burst + 1) % 3
		cooldown = float(data.fire_interval) if burst != 0 else 1.35
	else:
		cooldown = maxf(0.8, float(data.fire_interval))

func receive_damage(amount: float, _source: Node = null) -> void:
	if dead or amount <= 0: return
	alerted = true
	if _source is Node3D: last_known = _source.global_position
	health = maxf(0, health - amount)
	cooldown = minf(cooldown, 0.4)
	if health > 0:
		var impact_dir: Vector3 = (global_position - (_source as Node3D).global_position).normalized() if _source is Node3D else Vector3.ZERO
		preload("res://gameplay/CharacterFallPresentation3D.gd").apply_hit(self, visual, impact_dir, amount)
		return
	dead = true
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	var impact_dir: Vector3 = (global_position - (_source as Node3D).global_position).normalized() if _source is Node3D else Vector3.ZERO
	preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(self, visual, impact_dir)
	gameplay.drop_ammo(global_position, weapon_id)
	died.emit()
