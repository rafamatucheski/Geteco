extends SceneTree
var failures := 0
class TestZone extends Node2D:
	var locked := false
	func contains_point(_point: Vector2) -> bool: return locked
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func count_grenades(world: Node) -> int:
	var count := 0
	for n in world.get_children():
		if n is GrenadeProjectile: count += 1
	return count
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://Player.gd").new()
	player.use_meshy_dante = true
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	var zone := TestZone.new()
	world.add_child(zone)
	zone.add_to_group("weapon_free_zone")
	player.weapon_inventory["grenade"] = true
	player.weapon_ammo["grenade"] = {"clip":3,"reserve":0}
	player.equip_weapon("grenade")
	# Initialize the presentation before the native attack, as physics does.
	player.combat_pose.update(player,0.016,false,false,0)
	player._shoot_towards(player.global_position+Vector2(100,0))
	check(count_grenades(world) == 0,"No projectile before hand release")
	await create_timer(0.10).timeout
	check(count_grenades(world) == 0,"Windup does not release early")
	await create_timer(0.15).timeout
	check(count_grenades(world) == 1,"Exactly one projectile after release")
	check(player.weapon_ammo.grenade.clip == 2,"Throw consumes one grenade")
	for n in world.get_children():
		if n is GrenadeProjectile: n.queue_free()
	await process_frame
	player.fire_cooldown = 0
	player._shoot_towards(player.global_position+Vector2(100,0))
	zone.locked = true
	await create_timer(0.25).timeout
	check(count_grenades(world) == 0,"Entering weapon-free zone cancels queued release")
	check(player.weapon_ammo.grenade.clip == 2,"Cancelled throw restores ammunition")
	zone.locked = false
	player.fire_cooldown = 0
	player._shoot_towards(player.global_position+Vector2(100,0))
	player.equip_weapon("fists")
	await create_timer(0.25).timeout
	check(count_grenades(world) == 0,"Switching weapons cancels queued throw")
	check(player.weapon_ammo.grenade.clip == 2,"Switching weapons refunds the queued grenade")
	print("MESHY_GRENADE_RELEASE failures=",failures)
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
