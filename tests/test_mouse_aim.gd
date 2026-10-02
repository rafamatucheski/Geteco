extends SceneTree
## Real camera projection and physics, isolated from city simulation.
var failures: Array[String] = []
class Target extends CharacterBody3D:
	var health := 100.0
	func receive_damage(_amount: float, _source = null) -> void: pass
class AimHarness extends "res://gameplay/Gameplay.gd":
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func attack_allowed() -> bool: return true
	func equipped() -> String: return "pistol"
	func aim_feedback_active() -> bool: return true

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func body(point: Vector3) -> Target:
	var actor := Target.new()
	actor.collision_layer = 2
	actor.collision_mask = 0
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	collider.shape = capsule
	collider.position.y = 0.86
	actor.add_child(collider)
	current_scene.add_child(actor)
	actor.position = point
	return actor
func settle() -> void:
	for frame in 3: await physics_frame
func planar(point: Vector3) -> Vector2: return Vector2(point.x, point.z)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	scene.add_child(camera)
	camera.position = Vector3(8, 12, 12)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var player := body(Vector3(0, 0, 3))
	var first := body(Vector3(-2, 0, 0))
	var second := body(Vector3(2, 0, 0))
	var aim := AimHarness.new()
	aim.player = player
	aim.camera = camera
	scene.add_child(aim)
	await settle()
	for height in [0.25, 1.0, 1.45]:
		var point := aim.aim_from_screen(camera.unproject_position(first.position + Vector3.UP * height))
		check(planar(point).distance_to(planar(first.position)) < 0.02, "Cursor at NPC height %s selects that NPC" % height)
		var origin := aim._muzzle_world_position()
		var direction := point - origin
		direction.y = 0.0
		var shot := scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 8.0, 7, [player.get_rid()]))
		check(shot.get("collider") == first, "Horizontal firing path hits selected NPC at height %s" % height)
	var switched := aim.aim_from_screen(camera.unproject_position(second.position + Vector3.UP * 1.45))
	check(planar(switched).distance_to(planar(second.position)) < 0.02, "Mouse switches NPC immediately")
	var empty := Vector3(0, 1, -4)
	check(aim.aim_from_screen(camera.unproject_position(empty)).distance_to(empty) < 0.02, "Empty space keeps free aiming")
	var reticle := preload("res://ui/AimReticle.gd").new()
	reticle.gameplay = aim
	root.add_child(reticle)
	reticle._process(0.0)
	aim.aim_from_screen(camera.unproject_position(second.position + Vector3.UP))
	reticle._process(0.0)
	check(reticle.world_point.distance_to(aim.aim_feedback().point) < 0.001, "Marker follows new mouse aim without waiting for physics")
	paused = true
	reticle._process(0.0)
	check(not reticle.visible, "Pause hides marker")
	paused = false
	var overlap_screen := camera.unproject_position(first.position + Vector3.UP * 1.45)
	var front := body(first.position - camera.project_ray_normal(overlap_screen) * 0.8)
	await settle()
	check(planar(aim.aim_from_screen(overlap_screen)).distance_to(planar(front.position)) < 0.02, "Overlapping NPCs select the front visible body")
	front.queue_free()
	await settle()
	first.health = 0.0
	var dead_screen := camera.unproject_position(first.position + Vector3.UP * 1.45)
	check(planar(aim.aim_from_screen(dead_screen)).distance_to(planar(first.position)) > 0.1, "Dead NPC is not selected")
	first.health = 100.0
	first.set_meta("invulnerable", true)
	check(planar(aim.aim_from_screen(dead_screen)).distance_to(planar(first.position)) > 0.1, "Protected NPC is not selected")
	first.remove_meta("invulnerable")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	collider.shape = box
	wall.add_child(collider)
	scene.add_child(wall)
	wall.position = first.position + Vector3.UP * 1.45 + (camera.position - first.position).normalized() * 3.0
	await settle()
	check(planar(aim.aim_from_screen(dead_screen)).distance_to(planar(first.position)) > 0.1, "Screen ray cannot select NPC through solid")
	wall.queue_free()
	await settle()
	check(planar(aim.aim_from_screen(dead_screen)).distance_to(planar(first.position)) < 0.02, "Selection recovers when obstruction leaves")
	first.queue_free()
	await settle()
	check(aim.aim_from_screen(dead_screen).is_finite(), "Deleted NPC leaves no stale target")
	aim.camera = null
	check(aim.aim_from_screen(Vector2.ZERO) == aim.aim_point, "Missing camera updates authoritative fallback instead of stale aim")
	reticle._process(0.0)
	check(not reticle.visible, "Missing camera hides marker safely")
	print("MOUSE_AIM failures=", failures)
	quit(0 if failures.is_empty() else 1)
