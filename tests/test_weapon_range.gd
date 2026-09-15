extends SceneTree
var failures := 0
var world: Node2D
class Target extends StaticBody2D:
 var health := 1000
 func take_damage(amount: int, _player := false): health -= amount
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
 print(("PASS " if ok else "FAIL ") + label)
 if not ok: failures += 1
func target_at(x: float) -> Target:
 var target := Target.new()
 target.position = Vector2(x,0)
 target.collision_layer = 4
 var shape := CollisionShape2D.new()
 var box := RectangleShape2D.new()
 box.size = Vector2(2,20)
 shape.shape = box
 target.add_child(shape)
 world.add_child(target)
 return target
func shot(weapon: String, distance: float) -> int:
 var target := target_at(distance)
 var b = load("res://Bullet.tscn").instantiate()
 var data := WeaponCatalog.get_weapon(weapon)
 b.damage = int(data.damage)
 b.speed = float(data.projectile_speed)
 b.configure_range(data)
 b.direction = Vector2.RIGHT
 world.add_child(b)
 b.set_physics_process(false)
 await physics_frame
 await physics_frame
 # One deliberately long frame must still stop at the range boundary.
 b._physics_process(2.0)
 var dealt := 1000-target.health
 target.queue_free()
 if is_instance_valid(b): b.queue_free()
 await process_frame
 return dealt
func run():
 create_timer(30).timeout.connect(func(): quit(2))
 root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/weapon-range/test-saves/"
 world = Node2D.new()
 root.add_child(world)
 current_scene = world
 for weapon in ["pistol","magnum","smg","shotgun","sawed_off","ak47","m4a1","hunting_rifle"]:
  var data := WeaponCatalog.get_weapon(weapon)
  var near: int = await shot(weapon, 40)
  var far: int = await shot(weapon, float(data.max_range)-5)
  var beyond: int = await shot(weapon, float(data.max_range)+5)
  check(near == int(data.damage), weapon+" retains close damage")
  check(far > 0 and far < near, weapon+" loses damage far away")
  check(beyond == 0, weapon+" cannot hit beyond limit even in long frame")
  var previous := int(data.damage)
  var monotonic := true
  for d in range(0,int(data.max_range)+1,5):
   var amount := WeaponCatalog.distance_damage(int(data.damage),d,float(data.falloff_start),float(data.max_range),float(data.min_damage_ratio))
   monotonic = monotonic and amount <= previous and amount > 0
   previous = amount
  check(monotonic, weapon+" damage decreases monotonically")
 var front := target_at(80)
 var behind := target_at(160)
 var b = load("res://Bullet.tscn").instantiate()
 b.direction = Vector2.RIGHT
 world.add_child(b)
 b.set_physics_process(false)
 await physics_frame
 await physics_frame
 b._physics_process(1.0)
 check(front.health < 1000 and behind.health == 1000,"first body blocks farther target")
 front.queue_free()
 behind.queue_free()
 await process_frame
 var flame = load("res://FlameJet.tscn").instantiate()
 flame.configure_range(WeaponCatalog.get_weapon("flamethrower"))
 world.add_child(flame)
 flame.set_physics_process(false)
 var close := target_at(30)
 var distant := target_at(135)
 var outside := target_at(150)
 flame._apply_fire_damage(close)
 flame._apply_fire_damage(distant)
 flame._apply_fire_damage(outside)
 check(close.health == 997 and distant.health == 999 and outside.health == 1000,"flame applies 3/1/0 near/far/outside")
 for node in [flame,close,distant,outside]: node.queue_free()
 await process_frame
 for weapon in ["fists","knuckles","knife","bat","axe"]:
  var data := WeaponCatalog.get_weapon(weapon)
  check(WeaponCatalog.distance_damage(int(data.damage),float(data.melee_range),float(data.falloff_start),float(data.max_range),float(data.min_damage_ratio)) < int(data.damage),weapon+" edge contact weaker")
 var rocket = load("res://Bullet.tscn").instantiate()
 rocket.configure_range(WeaponCatalog.get_weapon("rpg"))
 rocket.damage = 95
 check(rocket.max_range == 650 and rocket.damage_at_distance(600) == 95,"rocket limits flight but retains explosive charge")
 rocket.free()
 var grenade = load("res://GrenadeProjectile.tscn").instantiate()
 world.add_child(grenade)
 grenade.setup(Vector2.ZERO,Vector2.RIGHT,10000,null)
 grenade.set_physics_process(false)
 grenade._physics_process(.1)
 check(grenade.global_position.length() <= 320.01 and grenade.velocity.is_zero_approx(),"grenade travel capped while fuse remains active")
 grenade.queue_free()
 var player = load("res://Player.gd").new()
 var camera := Camera2D.new()
 camera.name = "Camera"
 player.add_child(camera)
 world.add_child(player)
 player.set_physics_process(false)
 for weapon in ["pistol","magnum","smg","shotgun","sawed_off","ak47","m4a1","hunting_rifle","rpg","flamethrower","grenade"]:
  player.active_weapon_id = weapon
  player.weapon_ammo[weapon] = {"clip":10,"reserve":20}
  var before := world.get_children()
  player._shoot_towards(Vector2(1000,0))
  var spawned := 0
  var data := WeaponCatalog.get_weapon(weapon)
  for child in world.get_children():
   if child in before: continue
   if child.get_script() == load("res://Bullet.gd"):
    spawned += 1
    check(child.max_range == float(data.max_range) and child.falloff_start == float(data.falloff_start), weapon+" player wires projectile profile")
    child.queue_free()
   elif child is FlameJet:
    spawned += 1
    check(child.flame_range == 140 and child.damage_per_tick == 3,"player wires flame profile before geometry")
    child.queue_free()
   elif child is GrenadeProjectile:
    spawned += 1
    check(child.max_throw_range == 320 and child.damage == 80 and child.blast_radius == 120,"player wires grenade damage, radius and throw cap")
    child.queue_free()
  check(spawned == int(data.get("pellets",1)),weapon+" spawns expected projectiles")
  await process_frame
 for weapon in ["fists","knuckles","knife","bat","axe"]:
  var data := WeaponCatalog.get_weapon(weapon)
  player.active_weapon_id = weapon
  var victim := target_at(float(data.melee_range)-1)
  victim.add_to_group("damageable")
  await physics_frame
  await player._perform_melee_attack(Vector2.RIGHT,data)
  check(victim.health < 1000 and victim.health > 1000-int(data.damage),weapon+" real edge strike uses reduced damage")
  victim.queue_free()
  await process_frame
 await create_timer(2.1).timeout
 world.queue_free()
 await process_frame
 await process_frame
 print("WEAPON RANGE failures=",failures)
 quit(1 if failures else 0)
