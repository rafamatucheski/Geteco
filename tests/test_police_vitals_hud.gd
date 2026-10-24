extends SceneTree
## Functional visibility and real physics occlusion, without loading/saving a campaign.
const VITALS := preload("res://ui/hud/PoliceVitalsHUD.gd")
var failures: Array[String] = []

class Officer:
	extends Node3D
	var max_armor := 80.0
	var armor := 80.0
	# Health belongs to combat; a shield-only HUD must never inspect either value.
	var health_reads := 0
	var max_health: float:
		get:
			health_reads += 1
			return 95.0
	var health: float:
		get:
			health_reads += 1
			return 95.0
	var dead := false
	var controller: Node
	var sees_player := true
	var response_aggression := 0.0
	var last_damage_time := -INF
	var matching_context := true
	func _shares_player_context() -> bool: return matching_context

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var controller := Node.new()
	scene.add_child(controller)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	scene.add_child(camera)
	camera.position = Vector3(0,4,10)
	camera.look_at(Vector3(0,1,0))
	camera.make_current()
	var heavy := Officer.new()
	heavy.controller = controller
	scene.add_child(heavy)
	heavy.add_to_group("v2_police_officers")
	var ordinary := Officer.new()
	ordinary.controller = controller
	ordinary.max_armor = 0.0
	ordinary.armor = 0.0
	scene.add_child(ordinary)
	ordinary.add_to_group("v2_police_officers")
	var hud := VITALS.new()
	root.add_child(hud)
	hud.set_process(false)
	await physics_frame
	hud._refresh_officers()
	check(hud._officers.size() == 1 and hud._officers[0].actor == heavy, "Only shield-equipped officers enter the shield HUD")
	check(hud._eligible(heavy,camera), "A visible heavy officer engaged in combat is eligible")
	hud._update_occlusion(camera)
	check(hud._officers[0].clear, "Unobstructed real camera ray allows the heavy officer HUD")
	hud.queue_redraw()
	await process_frame
	await process_frame
	check(heavy.health_reads == 0 and ordinary.health_reads == 0, "The shield HUD does not inspect health or maximum health")
	heavy.armor = 0.0
	check(not hud._eligible(heavy,camera), "The shield vanishes immediately when armor reaches zero, before cache refresh")
	hud._refresh_officers()
	check(not hud._eligible(heavy,camera), "Depleted shields remain hidden after cache refresh")
	check(not hud._eligible(ordinary,camera), "An ordinary officer never receives a false armor track")
	heavy.armor = 80.0
	hud._refresh_officers()
	check(hud._officers.size() == 1 and hud._eligible(heavy,camera), "Restoring a shield makes the equipped officer eligible again")
	heavy.sees_player = false
	check(not hud._eligible(heavy,camera), "Idle unhurt heavy officers do not clutter the screen")
	heavy.last_damage_time = Time.get_ticks_msec() * 0.001
	check(hud._eligible(heavy,camera), "A recent impact reveals the remaining heavy officer shield")
	heavy.last_damage_time -= 5.0
	check(not hud._eligible(heavy,camera), "The impact-only visibility expires")
	heavy.sees_player = true
	heavy.matching_context = false
	check(not hud._eligible(heavy,camera), "Different interior contexts cannot leak shield HUD")
	heavy.matching_context = true
	heavy.dead = true
	check(not hud._eligible(heavy,camera), "Dead officers do not retain floating bars")
	heavy.dead = false
	heavy.hide()
	check(not hud._eligible(heavy,camera), "Hidden officers do not retain floating bars")
	heavy.show()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5,6,0.5)
	collider.shape = box
	wall.add_child(collider)
	scene.add_child(wall)
	wall.position = Vector3(0,2,5)
	await physics_frame
	await physics_frame
	hud._update_occlusion(camera)
	check(not hud._officers[0].clear, "A real solid wall blocks the screen-space shield bar")
	wall.queue_free()
	await physics_frame
	await physics_frame
	hud._update_occlusion(camera)
	check(hud._officers[0].clear, "Removing the obstruction restores the same HUD entry")
	heavy.queue_free()
	await process_frame
	hud._refresh_officers()
	check(hud._officers.is_empty(), "Removing the officer removes its cached HUD entry")
	print("POLICE_VITALS_HUD failures=", failures)
	quit(0 if failures.is_empty() else 1)
