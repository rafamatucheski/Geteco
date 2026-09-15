extends SceneTree
var failures := 0
var world: Node2D
var contacts: Array[Dictionary] = []
class ProtectedPerson extends CharacterBody2D:
	var health := 100
	func take_damage(_amount: int, _player := false) -> void: pass
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("SHOT_CHECK ", label, " ", ok)
	if not ok: failures += 1; push_error(label)
func fire(at: Vector2, facing: Vector2, amount := 5) -> Node2D:
	var bullet = preload("res://guns/Bullet.tscn").instantiate()
	bullet.position = at
	bullet.direction = facing
	bullet.damage = amount
	bullet.speed = 1200
	bullet.impact_resolved.connect(func(target, point, material, accepted): contacts.append({"target":target, "point":point, "material":material, "accepted":accepted}))
	world.add_child(bullet)
	return bullet
func run() -> void:
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var medic = preload("res://emergency/Paramedic.gd").new()
	medic.position = Vector2(100, 0)
	world.add_child(medic)
	medic.set_physics_process(false)
	var zone := preload("res://emergency/MedicalRescueWorkZone.gd").new()
	world.add_child(zone)
	zone.set_physics_process(false)
	zone.collision_layer = 2
	zone._shields[0].position = medic.position
	zone._shields[0].shape.radius = 27
	zone._shields[0].disabled = false
	await physics_frame
	await physics_frame
	var query := PhysicsRayQueryParameters2D.create(Vector2.ZERO, Vector2(130, 0), 7)
	var raw := world.get_world_2d().direct_space_state.intersect_ray(query)
	print("DIAGNOSIS first raw collider=", raw.get("collider"), " zone=", raw.get("collider") == zone)
	var initial: int = medic.health
	fire(Vector2.ZERO, Vector2.RIGHT)
	for i in 12: await physics_frame
	check(medic.health == initial - 5, "vehicle-only clearance does not absorb bullets")
	check(medic.has_node("WoundedPose"), "confirmed injury has a body pose")
	check(contacts.size() == 1 and contacts[0].target == medic and contacts[0].accepted, "contact reports actual damaged actor once")
	medic.health -= 25
	for i in 20: await physics_frame
	await process_frame
	check(medic.torso_node.rotation.x > .10, "serious wound retains a guarded posture after brief flinch")
	var health_after: int = medic.health
	fire(Vector2(0, 70), Vector2.RIGHT)
	for i in 12: await physics_frame
	check(medic.health == health_after, "miss does not damage nearby medic")
	check(contacts.size() == 1, "miss emits no contact confirmation")
	var wall := StaticBody2D.new()
	wall.position = Vector2(50, 0)
	wall.collision_layer = 1
	var collision := CollisionShape2D.new()
	collision.shape = RectangleShape2D.new()
	collision.shape.size = Vector2(6, 40)
	wall.add_child(collision)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	fire(Vector2.ZERO, Vector2.RIGHT)
	for i in 12: await physics_frame
	check(medic.health == health_after, "real solid stops shot before medic")
	check(contacts.size() == 2 and contacts[-1].target == wall and absf(contacts[-1].point.x - 47) < .1 and not contacts[-1].accepted, "impact lies on the real obstacle surface")
	var protected := ProtectedPerson.new()
	protected.position = Vector2(100, 140)
	protected.add_to_group("pedestrian")
	world.add_child(protected)
	var protected_shape := CollisionShape2D.new()
	protected_shape.shape = CircleShape2D.new()
	protected_shape.shape.radius = 8
	protected.add_child(protected_shape)
	await physics_frame
	await physics_frame
	fire(Vector2(0, 140), Vector2.RIGHT)
	for i in 12: await physics_frame
	check(protected.health == 100 and not protected.has_node("WoundedPose") and not protected.has_node("BulletReaction"), "intentional damage rejection keeps protection and creates no injury reaction")
	check(contacts[-1].target == protected and not contacts[-1].accepted, "protected contact is distinct from confirmed damage")
	medic.health = medic.max_health
	for i in 3: await physics_frame
	await process_frame
	check(not medic.has_node("WoundedPose") and is_zero_approx(medic.torso_node.rotation.x), "healing restores the additive pose cleanly")
	wall.collision_layer = 2
	wall.position = medic.position + Vector2(9,0)
	await physics_frame
	await physics_frame
	var before_recoil: Vector2 = medic.position
	var before_mask: int = medic.collision_mask
	var recoil_shot = fire(medic.position,Vector2.RIGHT,1)
	recoil_shot._hit(medic,medic.position,Vector2.LEFT)
	for i in 20: await physics_frame
	check(medic.position.x < before_recoil.x + 2 and medic.collision_mask == before_mask, "whole-body recoil stops at vehicle solids and restores the actor mask")
	world.queue_free()
	await process_frame
	print("SHOT FEEDBACK: ", failures, " failures")
	quit(1 if failures else 0)
