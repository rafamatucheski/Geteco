extends SceneTree
## Contact/timing regressions use real physics bodies. Not an audio listening
## test or a rendered performance certificate.
const SURFACE := preload("res://gameplay/WeaponSurface.gd")
const FX := preload("res://gameplay/CombatEffects.gd")
const AUDIO := preload("res://gameplay/CombatAudio.gd")
var failures: Array[String] = []
var checks := 0
var contacts: Array[Dictionary] = []

class ReloadState extends RefCounted:
	var magazine := 0
	func get_ammo(_id: String) -> Dictionary: return {"magazine": magazine, "reserve": 12}

class FeedbackController extends Node3D:
	var id := "sawed_off"
	var allowed := true
	var gun: Node3D
	var reload_timer := 0.0
	var _reload_total := 2.0
	var state := ReloadState.new()
	func equipped() -> String: return id
	func attack_allowed() -> bool: return allowed

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("CONTACT ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func body(parent: Node3D, point: Vector3, size: Vector3, material := "") -> StaticBody3D:
	var solid := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	solid.add_child(collider)
	parent.add_child(solid)
	solid.position = point
	if not material.is_empty(): solid.set_meta("impact_material", material)
	return solid

func active_count(fx: Node3D) -> int:
	var result := 0
	for state in fx._shell_state:
		if float(state.life) > 0.0: result += 1
	return result

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var car := body(scene, Vector3(30, 0, 0), Vector3.ONE)
	car.set_meta("gameplay_role", "vehicle")
	check(SURFACE.resolve(car) == "metal", "vehicle role resolves metal, never blood")
	var person := CharacterBody3D.new()
	person.set_meta("gameplay_role", "civilian")
	scene.add_child(person)
	check(SURFACE.resolve(person) == "flesh", "characters retain flesh feedback")
	var unknown := Node3D.new()
	unknown.set_meta("gameplay_role", "sign")
	scene.add_child(unknown)
	check(SURFACE.resolve(unknown) == "concrete", "unknown role is not flesh")
	check(SURFACE.resolve(unknown, Vector3(260, 100, -500), Vector3.UP) == "concrete", "elevated room/prop is not geographic snow")
	var soil := body(scene, Vector3.ZERO, Vector3(20, .2, 20), "dirt")
	check(SURFACE.resolve(soil) == "dirt", "authored earth recognized")
	soil.set_meta("impact_material", "wood")
	check(SURFACE.resolve(soil) == "wood", "authored wood takes priority")
	soil.set_meta("impact_material", "dirt")
	var fx := FX.new()
	scene.add_child(fx)
	fx.set_physics_process(false)
	fx.casing_contact.connect(func(point, material, speed, shotgun): contacts.append({"point":point,"material":material,"speed":speed,"shotgun":shotgun}))
	await physics_frame
	await physics_frame
	fx.shell(Vector3(0, 1, 0), Vector3.FORWARD, 20.0)
	fx.set_physics_process(false)
	for step in 100: fx._physics_process(1.0/60.0)
	check(not contacts.is_empty() and contacts[0].material == "dirt", "case contacts actual earth, ignores supplied shooter floor")
	check(fx._shells[0].position.y > .1 and fx._shells[0].position.y < .15, "case rests on physical floor")
	check(bool(fx._shell_state[0].resting) and int(fx._shell_state[0].bounces) == 1, "soft earth absorbs first contact")
	fx.clear(); contacts.clear()
	var wall := body(scene, Vector3(.5, 1.2, 0), Vector3(.1, 3, 6), "metal")
	wall.collision_layer = 4
	await physics_frame
	await physics_frame
	fx.shell(Vector3(0, 1, 0), Vector3.FORWARD, 0.0)
	fx.set_physics_process(false)
	for step in 35: fx._physics_process(1.0/60.0)
	check(not contacts.is_empty() and contacts[0].material == "metal", "swept case strikes metal body on vehicle layer 4")
	check(fx._shells[1].global_position.x < .46, "case does not pass through wall")
	wall.queue_free()
	fx.clear()
	var controller := FeedbackController.new()
	scene.add_child(controller)
	controller.gun = Node3D.new()
	controller.add_child(controller.gun)
	controller.gun.position = Vector3(0, 1, 0)
	for id in ["sawed_off", "magnum"]:
		fx.clear()
		controller.id = id
		controller.reload_timer = 0.0
		fx.weapon_shot(id, Vector3.UP, Vector3.FORWARD, 1 if id == "sawed_off" else 5)
		check(active_count(fx) == 0, id + " retains casing after discharge")
		controller.reload_timer = 1.7
		fx.update_weapon_feedback(controller, .01)
		check(active_count(fx) == 0, id + " does not eject before opening")
		controller.reload_timer = 1.4
		fx.update_weapon_feedback(controller, .01)
		check(active_count(fx) == 1, id + " ejects only one spent case during opening")
		fx.update_weapon_feedback(controller, .01)
		check(active_count(fx) == 1, id + " reload does not duplicate cases")
		controller.reload_timer = 0.0
		fx.update_weapon_feedback(controller, .01)
		controller.reload_timer = 1.4
		fx.update_weapon_feedback(controller, .01)
		check(active_count(fx) == 1, id + " cancel/retry does not eject same case again")
	fx.clear()
	controller.id = "shotgun"
	controller.reload_timer = 0.0
	fx.weapon_shot("shotgun", Vector3.UP, Vector3.FORWARD, 5)
	check(active_count(fx) == 0, "pump waits for action cycle")
	fx.update_weapon_feedback(controller, .3)
	check(active_count(fx) == 1, "pump ejects after cycle delay")
	fx.weapon_shot("shotgun", Vector3.UP, Vector3.FORWARD, 4)
	controller.allowed = false
	fx.update_weapon_feedback(controller, .3)
	check(active_count(fx) == 1 and fx._pending_ejections.is_empty(), "weapon restriction cancels pending ejection")
	fx.clear()
	check(active_count(fx) == 0 and fx._pending_ejections.is_empty(), "transition clears feedback")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for family in AUDIO.CONTACT_FAMILIES:
		var first := AUDIO.contact_take(family, rng)
		var next := AUDIO.contact_take(family, rng)
		check(first != null and next != null and first != next and first.get_length() <= .25, family + " imported short varied Foley")
	for material in ["dirt", "sand", "grass", "snow", "metal", "wood", "concrete"]:
		check(AUDIO.impact_take(material, rng) != null, material + " bullet impact has audio")
	for index in 100: fx.shell(Vector3.UP, Vector3.FORWARD, 0.0)
	check(active_count(fx) == FX.MAX_SHELLS, "sustained fire remains bounded to existing case pool")
	fx.clear()
	scene.queue_free()
	await process_frame
	print("WEAPON_CONTACTS checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
