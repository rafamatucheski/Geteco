extends RefCounted

const BULLET := preload("res://Bullet.tscn")
var cooldown := 1.2
var aim_time := 0.0
var burst := 0
var weapon_reload := preload("res://world/shared/combat/WeaponReload.gd").new()

func tick(unit: CharacterBody2D, delta: float) -> void:
	weapon_reload.equip("pistol")
	weapon_reload.tick(delta)
	cooldown = maxf(0.0, cooldown - delta)
	var wanted := unit.get_node_or_null("/root/WantedManager")
	var suspect: Node2D = unit.target
	if wanted == null or wanted.current_stars < 2 or unit.is_acting or unit.is_returning_to_base or unit.is_broken or unit.police_variant == "motorcycle" or unit._police_available_seats < 2:
		aim_time = 0.0
		return
	if not is_instance_valid(suspect) or suspect.get("is_driven_by_player") != true or suspect.global_position.distance_to(unit.global_position) > 300:
		aim_time = 0.0
		return
	var side := signf(unit.to_local(suspect.global_position).y)
	if side == 0: side = 1
	var hull := unit.get_node("CollisionShape2D") as CollisionShape2D
	var muzzle := unit.to_global(Vector2(12, side * ((hull.shape as RectangleShape2D).size.y * .5 + 6)))
	var sight := PhysicsRayQueryParameters2D.create(muzzle, suspect.global_position, 3, [unit.get_rid()])
	var hit := unit.get_world_2d().direct_space_state.intersect_ray(sight)
	if not hit.is_empty() and hit.collider != suspect:
		aim_time = 0.0
		return
	aim_time += delta
	if aim_time < .9 or cooldown > 0: return
	if not weapon_reload.consume(): return
	var bullet := BULLET.instantiate()
	unit.get_tree().current_scene.add_child(bullet)
	bullet.owner_body = unit
	bullet.global_position = muzzle
	bullet.direction = muzzle.direction_to(suspect.global_position).rotated(randf_range(-.13, .13))
	bullet.speed = 1100
	bullet.configure_range(WeaponCatalog.get_weapon("pistol"))
	bullet.damage = 5
	burst += 1
	cooldown = .8 if burst < 2 else 3.0
	if burst >= 2: burst = 0
	if weapon_reload.remaining > 0.0: cooldown = 0.0
	var shot := AudioStreamPlayer2D.new()
	shot.stream = ProceduralAudio.get_gunshot_pistol_stream()
	shot.bus = "SFX"
	shot.volume_db = -14
	shot.max_distance = 600
	unit.add_child(shot)
	shot.position = unit.to_local(muzzle)
	shot.finished.connect(shot.queue_free)
	shot.play()
