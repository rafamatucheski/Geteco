extends SceneTree
const ACTOR = preload("res://scripts/Actor.gd")
const SKATE = preload("res://activities/skate/Skate.gd")
class Street extends Node3D:
	var people: Array[CharacterBody3D] = []
	var player: Node3D
var failures := 0
var checks := 0
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print("SKATE_STREET ", "PASS " if ok else "FAIL ", label)
func run():
	var street = Street.new()
	root.add_child(street)
	var floor_body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(400, -.5, 400)
	street.add_child(floor_body)
	street.player = Node3D.new()
	# O diretor de produção cria pedestres a pelo menos 45 m de distância.
	street.player.position = Vector3(400, 0, 460)
	street.add_child(street.player)
	for i in 4:
		var actor = ACTOR.new()
		actor.identity = i * 5
		actor.position = Vector3(400 + i * 3, .05, 400)
		actor.route = PackedVector3Array([actor.position + Vector3.FORWARD * 15, actor.position + Vector3.BACK * 15])
		street.add_child(actor)
		street.people.append(actor)
	for i in 30: await physics_frame
	var skate = SKATE.new()
	street.add_child(skate)
	skate.set_physics_process(false)
	skate.session = {"world": street, "state": {"region_id": "harbor", "place_id": ""}, "modal": false}
	for i in 4: skate._update_population()
	check(skate.ambient.size() == 3, "three street riders far beyond the park, bounded population")
	var colors := {}
	var paces := {}
	for row in skate.ambient:
		colors[row.board.color] = true
		paces[row.pace] = true
	check(colors.size() == 3 and paces.size() == 3, "different boards and riding speeds")
	var row = skate.ambient[0]
	var start: Vector3 = row.actor.position
	for i in 90:
		await physics_frame
		skate._update_ambient(1.0 / 60)
	check(row.actor.position.distance_to(start) > 1, "street riders move on the existing pedestrian route")
	skate._update_population()
	check(skate.ambient.size() == 3 and row.board.riding, "population refresh outside park preserves active riders")
	row.board.bail(0)
	check(row.board.former_rider.get_ref() == row.actor, "fallen board remembers its living owner")
	skate._escape(row.actor)
	for i in 75:
		await physics_frame
		skate._update_fallen(1.0 / 60)
	check(is_instance_valid(row.actor) and not row.actor.dead and row.actor.is_physics_processing() and not row.actor.input_locked, "living fallen rider recovers walking control within 1.25 seconds")
	check(not row.actor.has_meta("destroyed_cleanup"), "nonfatal fall never schedules corpse disposal")
	var escape_start: Vector3 = row.actor.position
	for i in 90:
		await physics_frame
		skate._update_escaping(1.0 / 60)
	check(row.actor.position.distance_to(escape_start) > 3 and row.actor.speed > 4, "robbed owner runs away after recovering")
	skate._update_escaping(6)
	check(is_equal_approx(row.actor.speed, 1.6) and skate._escaping.is_empty(), "escape releases normal walking speed")
	street.player.position += Vector3(200, 0, 200)
	skate._update_population()
	check(skate.ambient.is_empty(), "distant riders release their boards")
	for actor in street.people:
		check(actor.is_physics_processing(), "retired pedestrian resumes movement")
	street.free()
	print("SKATE_STREET_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
