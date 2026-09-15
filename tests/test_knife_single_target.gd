extends SceneTree
var failures := 0
class Target extends Node2D:
 var health := 100
 func take_damage(amount, _melee): health -= amount
func _init(): call_deferred("run")
func check(ok, label):
 print("PASS " if ok else "FAIL ", label)
 if not ok: failures += 1
func run():
 var scene := Node2D.new()
 root.add_child(scene)
 current_scene = scene
 var player = load("res://characters/Player.gd").new()
 var camera := Camera2D.new()
 camera.name = "Camera"
 player.add_child(camera)
 scene.add_child(player)
 player.set_physics_process(false)
 player.active_weapon_id = "knife"
 var targets: Array = []
 for i in 5:
  var target := Target.new()
  target.position = Vector2(25 + i * 3, 0)
  scene.add_child(target)
  target.add_to_group("damageable")
  targets.append(target)
 await physics_frame
 var data := WeaponCatalog.get_weapon("knife")
 player._perform_melee_attack(Vector2.RIGHT, data)
 check(targets[0].health == 75, "nearest target takes one knife hit")
 check(targets.slice(1).all(func(t): return t.health == 100), "four bystanders remain unharmed")
 targets[0].health = 0
 player._perform_melee_attack(Vector2.RIGHT, data)
 check(targets[1].health == 75, "dead target does not absorb next attack")
 for target in targets: target.position = Vector2(0, 30)
 player._perform_melee_attack(Vector2.RIGHT, data)
 check(targets[2].health == 100, "side targets outside narrow strike")
 targets[2].position = Vector2(41, 0)
 player._perform_melee_attack(Vector2.RIGHT, data)
 check(targets[2].health == 100, "knife cannot reach 41 pixels")
 var wall := StaticBody2D.new()
 var shape := CollisionShape2D.new()
 shape.shape = RectangleShape2D.new()
 shape.shape.size = Vector2(5, 60)
 wall.position = Vector2(15, 0)
 wall.add_child(shape)
 scene.add_child(wall)
 targets[2].position = Vector2(30, 0)
 await physics_frame
 player._perform_melee_attack(Vector2.RIGHT, data)
 check(targets[2].health == 100, "wall blocks knife")
 var pose = load("res://characters/PlayerCombatPose.gd").new()
 for i in 6:
  pose.on_attack("knife")
  check(pose.knife_variant == i % 3, "three motions cycle")
 var bank = load("res://audio/combat/KnifeAudio.gd")
 check(bank.impact(0) != bank.swing() and bank.impact(0) == bank.impact(0), "impact distinct from air and cached")
 scene.queue_free()
 await process_frame
 quit(0 if failures == 0 else 1)
