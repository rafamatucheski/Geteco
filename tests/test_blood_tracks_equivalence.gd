extends SceneTree
## Rode sem mudanças contra os scripts canônicos original/candidato. Os tempos de método na CPU
## usam entradas fixas; não certificam tempos de quadro de jogo nem a conclusão na GPU.
const BLOOD := preload("res://gameplay/street_physics/GroundBlood3D.gd")
const TRACKS := preload("res://gameplay/street_physics/BloodTracks3D.gd")
var checks := 0
var failures: Array[String] = []
var fixture_world: Node3D

class Director extends Node:
	var blood: Node3D
	var members: Array[Node3D] = []
	func people() -> Array[Node3D]: return members

class Car extends Node3D:
	var horizontal_velocity := Vector3.ZERO
	var half_length := 2.0
	var half_width := 1.0

class Person extends Node3D:
	var dead := false
	var visual: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func make_stain(blood: Node3D, point: Vector3, radius: float, scale_x: float) -> Node3D:
	var marker := Node3D.new()
	fixture_world.add_child(marker)
	marker.scale = Vector3(scale_x, 1.0, 1.0)
	blood.stains.append({"node":marker, "point":point, "radius":radius})
	return marker

func contact_exists(blood: Node3D, point: Vector3, radius: float) -> bool:
	if blood.has_method("has_stain_near"): return blood.has_stain_near(point, radius)
	return not blood.stains_near(point, radius).is_empty()

func query_contract(blood: Node3D) -> void:
	check(not contact_exists(blood, Vector3.ZERO, 1.0), "empty stains have no contact")
	var marker := make_stain(blood, Vector3.ZERO, .5, 2.0)
	check(contact_exists(blood, Vector3(1.249, 30.0, 0.0), .25), "scaled radius and planar distance allow contact")
	check(not contact_exists(blood, Vector3(1.25, 0.0, 0.0), .25), "touching radius boundary is excluded")
	check(not contact_exists(blood, Vector3(1.251, 0.0, 0.0), .25), "outside radius is excluded")
	check(contact_exists(blood, Vector3.ZERO, 0.0), "point probe inside stain contacts")
	marker.scale.x = .1
	check(not contact_exists(blood, Vector3(.4, 0.0, 0.0), .25), "live stain growth scale changes contact")
	marker.free()
	check(not contact_exists(blood, Vector3.ZERO, 2.0), "removed stain node is ignored")
	for index in 64:
		make_stain(blood, Vector3(index % 8, 0.0, floori(index / 8.0)), .15 + .04 * (index % 5), .3 + .2 * (index % 7))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261002
	for index in 384:
		var point := Vector3(rng.randf_range(-2.0, 10.0), rng.randf_range(-5.0, 5.0), rng.randf_range(-2.0, 10.0))
		var radius := rng.randf_range(-.1, 2.0)
		var expected: bool = not blood.stains_near(point, radius).is_empty()
		check(contact_exists(blood, point, radius) == expected, "query agrees with list consumer %d" % index)
	blood.stains.clear()

func color_after_draw(mesh: MultiMesh, expected: Color, label: String) -> void:
	var before := mesh.get_instance_color(0)
	# Esta fixture escreve fora da física enquanto o MultiMesh de produção mantém
	# a interpolação ligada. Deixa os dois buffers de física chegarem ao estado pedido;
	# uma leitura depois de um desenho só observa em vez disso a mistura transicional válida.
	for step in 2: await physics_frame
	await RenderingServer.frame_post_draw
	var actual := mesh.get_instance_color(0)
	print("BLOOD_COLOR_READBACK ", JSON.stringify({"check":label, "before_draw":str(before),
		"after_draw":str(actual), "expected":str(expected)}))
	check(actual.is_equal_approx(expected), label)

func fade_contract(tracks: Node3D) -> void:
	tracks._clock = 100.0
	tracks._emit(Vector3(1, 2, 3), .7, Vector2(.2, 1.1), .8)
	var mesh: MultiMesh = tracks._multimesh
	var fresh := Color("420c10")
	fresh.a = .8
	await color_after_draw(mesh, fresh, "new slot has original tint and alpha")
	var original_transform := mesh.get_instance_transform(0)
	tracks._clock = 109.75
	tracks._fade()
	await color_after_draw(mesh, fresh, "mark stays unchanged before its fade window")
	var faded := Color("420c10").lerp(Color("2e1012"), .6)
	faded.a = .4
	tracks._clock = 112.0
	tracks._fade()
	await color_after_draw(mesh, faded, "halfway through fade preserves tint and half alpha")
	check(mesh.get_instance_transform(0).is_equal_approx(original_transform), "fading does not change world transform")
	tracks._clock = 114.0
	tracks._fade()
	faded.a = 0.0
	await color_after_draw(mesh, faded, "lifetime boundary clears alpha while preserving faded tint")
	for index in 20:
		tracks._clock += .25
		tracks._fade()
	await color_after_draw(mesh, faded, "expired mark remains transparent after repeated updates")
	# Preenche o resto do anel e depois exercita o reuso do primeiro slot expirado.
	for index in range(1, tracks.MAX_MARKS):
		tracks._emit(Vector3(index, 0, 0), 0.0, Vector2(.2, .5), .7)
	tracks._emit(Vector3(7, 1, 9), -.2, Vector2(.3, .8), .6)
	check(mesh.visible_instance_count == tracks.MAX_MARKS, "ring remains bounded after reuse")
	fresh.a = .6
	await color_after_draw(mesh, fresh, "reused expired slot becomes visible with fresh tint")
	var reused_origin := mesh.get_instance_transform(0).origin
	print("BLOOD_TRANSFORM_READBACK actual=", reused_origin, " expected=", Vector3(7, 1.048, 9))
	check(reused_origin.distance_to(Vector3(7, 1.048, 9)) < .00001, "reused slot receives the new geometry")
	tracks._clock += 12.0
	tracks._fade()
	faded.a = .3
	await color_after_draw(mesh, faded, "reused slot independently completes the same fade cycle")

func time_queries(blood: Node3D, point: Vector3, iterations: int) -> Dictionary:
	var hits := 0
	var began := Time.get_ticks_usec()
	if blood.has_method("has_stain_near"):
		for iteration in iterations:
			if blood.has_stain_near(point, .25): hits += 1
	else:
		for iteration in iterations:
			if not blood.stains_near(point, .25).is_empty(): hits += 1
	return {"elapsed_usec":Time.get_ticks_usec()-began, "calls":iterations, "hits":hits}

func microbenchmark(blood: Node3D, tracks: Node3D) -> void:
	for index in 64: make_stain(blood, Vector3(index * 5.0, 0, 0), .5, 1.0)
	var queries := {}
	for entry in [{"name":"first_hit", "point":Vector3.ZERO, "hits":2000},
		{"name":"last_hit", "point":Vector3(315, 0, 0), "hits":2000},
		{"name":"miss", "point":Vector3(10000, 0, 0), "hits":0}]:
		time_queries(blood, entry.point, 100)
		var result := time_queries(blood, entry.point, 2000)
		check(int(result.hits) == int(entry.hits), "fixed query workload returns expected hits: " + str(entry.name))
		queries[entry.name] = result
	blood.stains.clear()
	tracks._clock = 500.0
	for index in tracks.MAX_MARKS: tracks._emit(Vector3(index, 0, 0), 0.0, Vector2(.2, .6), .8)
	var fades := {}
	for entry in [{"name":"fading_700", "clock":512.0}, {"name":"expired_700", "clock":515.0}]:
		tracks._clock = float(entry.clock)
		for iteration in 10: tracks._fade()
		var began := Time.get_ticks_usec()
		for iteration in 100: tracks._fade()
		fades[entry.name] = {"elapsed_usec":Time.get_ticks_usec()-began, "calls":100, "marks":700}
	print("BLOOD_TRACKS_CPU ", JSON.stringify({"queries":queries, "fades":fades,
		"scope":"Fixed-input CPU method microbenchmark, 100 query/10 fade warmups; not gameplay FPS or GPU completion"}))

func contact_contract(blood: Node3D) -> void:
	var director := Director.new()
	director.blood = blood
	fixture_world.add_child(director)
	var tracks := TRACKS.new()
	tracks.director = director
	fixture_world.add_child(tracks)
	var car := Car.new()
	fixture_world.add_child(car)
	car.add_to_group("drivable")
	var person := Person.new()
	fixture_world.add_child(person)
	person.visual = Node3D.new()
	person.add_child(person.visual)
	director.members.append(person)
	make_stain(blood, Vector3.ZERO, .5, 1.0)
	# A integração usa os callbacks normais do motor, não um laço acionado à mão.
	for step in 4: await physics_frame
	tracks.set_physics_process(false)
	check(tracks._tracks.has(car.get_instance_id()), "vehicle contact acquires tire residue")
	check(tracks._tracks.has(person.get_instance_id()), "person contact acquires foot residue")
	if tracks._tracks.has(car.get_instance_id()):
		check(is_equal_approx(float(tracks._tracks[car.get_instance_id()].residue), tracks.TIRE_DISTANCE), "vehicle residue preserves its distance budget")
	if tracks._tracks.has(person.get_instance_id()):
		check(is_equal_approx(float(tracks._tracks[person.get_instance_id()].residue), tracks.FOOT_DISTANCE), "foot residue preserves its distance budget")
	blood.stains.clear()
	person.position.x += .8
	tracks.set_physics_process(true)
	for step in 4: await physics_frame
	tracks.set_physics_process(false)
	check(tracks._multimesh.visible_instance_count == 1, "walking away emits one foot mark without renewing contact")
	if tracks._tracks.has(person.get_instance_id()):
		check(absf(float(tracks._tracks[person.get_instance_id()].residue)-(tracks.FOOT_DISTANCE-.8)) < .00001, "travel spends residue by distance")

func run() -> void:
	fixture_world = Node3D.new()
	root.add_child(fixture_world)
	var blood := BLOOD.new()
	fixture_world.add_child(blood)
	blood.set_process(false)
	query_contract(blood)
	var tracks := TRACKS.new()
	fixture_world.add_child(tracks)
	tracks.set_physics_process(false)
	await fade_contract(tracks)
	microbenchmark(blood, tracks)
	await contact_contract(blood)
	fixture_world.queue_free()
	await process_frame
	await process_frame
	print("BLOOD_TRACKS_EQUIVALENCE checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
