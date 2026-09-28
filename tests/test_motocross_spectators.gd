extends SceneTree
## The standard civilian rig, real combat signals, solid furniture and boat edge.
const SPECTATOR := preload("res://activities/motocross/MotocrossSpectator.gd")
const MODEL := preload("res://assets/CivilianModel.gd")
class CombatFixture extends Node:
	signal weapon_fired(weapon_id: String, origin: Vector3)
	signal npc_gunfire(origin: Vector3, direction: Vector3, shooter: Node3D)
	signal explosion_occurred(origin: Vector3, radius: float, source: Node)
	var emergency: Node
	func weapon_data(id: String) -> Dictionary: return {"suppressed": id == "suppressed"}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(condition: bool, label: String) -> void:
	checks += 1
	print("MOTOCROSS_SPECTATORS ", "PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)
func step(frames: int) -> void:
	for _i in frames: await physics_frame
func solid(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body
func spawn(parent: Node3D, position: Vector3, options: Dictionary) -> CharacterBody3D:
	var person := SPECTATOR.new()
	person.configure(options)
	person.position = position
	parent.add_child(person)
	return person

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var combat := CombatFixture.new()
	world.add_child(combat)
	solid(world, Vector3(0,-.1,0), Vector3(12,.2,12))
	solid(world, Vector3(0,.225,.10), Vector3(1.4,.45,.55))
	var sitter := spawn(world, Vector3.ZERO, {"seated": true, "drinking": true})
	sitter.bind_combat(combat)
	sitter.bind_combat(combat)
	await step(3)
	check(sitter.model.get_script() == MODEL and sitter.model.thighs.size() == 2 and sitter.model.forearms.size() == 2, "uses standard articulated civilian mesh kit and IK")
	check(sitter.model.sit_amount == 1.0 and sitter.model.wardrobe.shoe == 1 and sitter.model.wardrobe.bottom == 0, "seated spectator wears ordinary-proportion trousers and boots")
	check(sitter.is_in_group("v2_damageable") and sitter.collision_layer == 2 and not sitter.is_physics_processing(), "idle physical body remains targetable without a physics loop")
	check(combat.weapon_fired.get_connections().size() == 1, "repeated binding does not duplicate gunfire callbacks")
	combat.weapon_fired.emit("suppressed", Vector3(20,0,0))
	check(not sitter.frightened, "suppressed gun outside hearing radius does not alert spectator")
	combat.weapon_fired.emit("pistol", Vector3(0,0,4))
	check(sitter.frightened and not sitter._bottle.visible, "real gunfire interrupts drinking and starts protective reaction")
	await step(90)
	check(not sitter.seated and sitter.position.z < -.6 and sitter.position.y > -.05, "seated actor physically clears solid bench before standing and fleeing")
	var source := Node3D.new()
	source.position = sitter.position + Vector3(0,0,2)
	world.add_child(source)
	sitter.receive_damage(25, source)
	check(sitter.health == 75.0 and not sitter.dead and sitter.model._hit_target.length() > 0, "real injury damages health and drives existing civilian flinch")
	# A solid table immediately ahead makes standing unsafe: shelter in the seat.
	solid(world, Vector3(-3,.225,.1), Vector3(1.4,.45,.55))
	solid(world, Vector3(-3,.65,-.7), Vector3(1.4,.2,.6))
	var trapped := spawn(world, Vector3(-3,0,0), {"seated": true})
	trapped.notice_threat(Vector3(-3,0,3), 30)
	await step(90)
	check(trapped.seated and trapped.position.distance_to(Vector3(-3,0,0)) < .01 and trapped.frightened, "blocked table causes seated shielding without sliding into furniture or air")

	# Deck is above the land fixture, so an edge probe cannot mistake land for deck.
	var boat := Node3D.new()
	boat.position = Vector3(15,2,0)
	world.add_child(boat)
	solid(boat, Vector3(0,-.1,0), Vector3(2.65,.2,5.5))
	solid(boat, Vector3(0,.115,-1.4), Vector3(2.7,.23,.6))
	solid(boat, Vector3(0,.115,1.5), Vector3(2.7,.23,.6))
	var sailor := spawn(boat, Vector3(.6,.02,.15), {"deck": boat, "bounds": Rect2(-1.325,-1.08,2.65,2.28)})
	sailor.bind_combat(combat)
	combat.npc_gunfire.emit(boat.global_position + Vector3(-3,0,0), Vector3.RIGHT, source)
	var stayed_on_deck := true
	for i in 480:
		await physics_frame
		stayed_on_deck = stayed_on_deck and sailor.position.x < 1.05 and sailor.position.x > -1.05 and sailor.position.z > -.81 and sailor.position.z < .93 and sailor.position.y > -.05
	check(stayed_on_deck, "panicked boat spectator never crosses rail, bench or water gap")
	check(not sailor.frightened and not sailor.is_physics_processing(), "quiet spectator settles without persistent pathfinding or physics work")
	check(not trapped.frightened and not trapped.is_physics_processing(), "blocked seated spectator also returns to calm after gunfire stops")
	combat.explosion_occurred.emit(sailor.global_position + Vector3(0,0,5), 4.0, source)
	check(sailor.frightened, "actual explosion signal also causes protective response")
	sailor.receive_damage(1000, source)
	await step(70)
	check(sailor.dead and sailor.health == 0 and sailor.collision_layer == 0 and sailor.state == "dead", "fatal damage uses standard fallen civilian lifecycle")
	sitter.queue_free()
	sailor.queue_free()
	await step(2)
	check(combat.weapon_fired.get_connections().is_empty(), "streamed-out actors release all combat signal subscriptions")
	world.queue_free()
	await step(2)
	print("MOTOCROSS_SPECTATORS_RESULT ", checks - failures.size(), "/", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)
