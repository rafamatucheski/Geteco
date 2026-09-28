extends SceneTree
## Contrato criminal central. PoliceAgent continua dono de reação/vida; este
## teste garante que Gameplay não duplica crime e só aceita autoria real.

const POLICE := preload("res://gameplay/PoliceAgent.gd")

class FakeState extends RefCounted:
	var place_id := ""
	func weapons_allowed() -> bool: return true

class FakePlayer extends CharacterBody3D:
	pass

class FakePolice extends CharacterBody3D:
	var health := 100.0
	var dead := false
	func _init() -> void:
		set_meta("gameplay_role", "police")
		collision_layer = 2
		var collision := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.3
		shape.height = 1.7
		collision.shape = shape
		collision.position.y = 0.86
		add_child(collision)
	func receive_damage(amount: float, _source: Node = null) -> void:
		if dead or amount <= 0.0: return
		health = maxf(0.0, health - amount)
		dead = health <= 0.0

class FakeVehicle extends Node:
	var player_owned := false
	func is_player_damage_source() -> bool: return player_owned

var failures: Array[String] = []
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	print(("CASE PASS " if ok else "CASE FAIL ") + label + ((" | " + detail) if detail != "" else ""))
	if not ok: failures.append(label)

func reset_crime(gameplay: Node) -> void:
	gameplay.crime_points = 0
	gameplay.stars = 0
	gameplay._clear_combat_registers()

func _run() -> void:
	var gameplay := preload("res://gameplay/Gameplay.gd").new()
	var world := Node3D.new()
	var player := FakePlayer.new()
	var state := FakeState.new()
	root.add_child(world)
	world.add_child(player)
	gameplay.configure(world, player, null, state)
	gameplay.set_physics_process(false)
	world.add_child(gameplay)
	gameplay.set_physics_process(false)

	var officer := FakePolice.new()
	root.add_child(officer)
	gameplay._damage(officer, 1.0, player)
	check(gameplay.crime_points == 30 and gameplay.stars == 2, "ferir policial garante o piso de duas estrelas", "crime=%d stars=%d" % [gameplay.crime_points, gameplay.stars])
	gameplay._damage(officer, 200.0, player)
	check(officer.dead and gameplay.crime_points == 60 and gameplay.stars == 3, "matar após agressão chega ao piso de três estrelas", "crime=%d stars=%d" % [gameplay.crime_points, gameplay.stars])
	gameplay._report_police_killed(officer)
	check(gameplay.crime_points == 60, "morte policial é registrada uma única vez")

	reset_crime(gameplay)
	var unauthored := FakePolice.new()
	var invalid_source := Node3D.new()
	root.add_child(unauthored)
	root.add_child(invalid_source)
	gameplay._damage(unauthored, 10.0, invalid_source)
	check(gameplay.crime_points == 0 and gameplay.stars == 0, "fonte sem autoria do jogador não cria crime")

	reset_crime(gameplay)
	var blast_target := FakePolice.new()
	blast_target.position = Vector3(5.0, 0.0, 0.0)
	root.add_child(blast_target)
	await physics_frame
	gameplay.explode(blast_target.global_position + Vector3.UP, 3.0, 200.0, player)
	check(blast_target.dead and gameplay.crime_points == 60 and gameplay.stars == 3, "explosão preserva autoria e regra fatal policial", "crime=%d stars=%d" % [gameplay.crime_points, gameplay.stars])

	reset_crime(gameplay)
	var run_over := FakePolice.new()
	var player_vehicle := FakeVehicle.new()
	player_vehicle.player_owned = true
	root.add_child(run_over)
	root.add_child(player_vehicle)
	gameplay.report_vehicle_assault(run_over, player_vehicle)
	check(gameplay.crime_points == 30 and gameplay.stars == 2, "atropelamento autorado garante duas estrelas uma vez")
	run_over.dead = true
	gameplay.report_vehicle_assault(run_over, player_vehicle)
	gameplay.report_vehicle_assault(run_over, player_vehicle)
	check(gameplay.crime_points == 60 and gameplay.stars == 3, "morte no mesmo contato soma a regra fatal sem duplicar", "crime=%d" % gameplay.crime_points)

	reset_crime(gameplay)
	var actual_officer := POLICE.new()
	actual_officer.controller = gameplay
	root.add_child(actual_officer)
	actual_officer.set_physics_process(false)
	actual_officer.health = 1.0
	actual_officer.receive_damage(2.0, player_vehicle)
	check(actual_officer.dead and gameplay.crime_points == 60 and gameplay.stars == 3,
		"PoliceAgent encaminha atropelamento fatal depois de atualizar a morte", "crime=%d dead=%s" % [gameplay.crime_points, actual_officer.dead])
	actual_officer.receive_damage(2.0, player_vehicle)
	check(gameplay.crime_points == 60, "PoliceAgent não duplica denúncia após a morte")

	reset_crime(gameplay)
	var dispatch_vehicle := FakeVehicle.new()
	var safe_officer := FakePolice.new()
	root.add_child(dispatch_vehicle)
	root.add_child(safe_officer)
	gameplay.report_vehicle_assault(safe_officer, dispatch_vehicle)
	check(gameplay.crime_points == 0, "viatura/tráfego sem jogador não atribui crime")

	print("POLICE_CRIME_CONTRACT checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
