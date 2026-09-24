extends SceneTree
## Validador isolado da paridade policial comprovada no V1: arma, dano,
## rajada, pente/recarga e autoria real de atropelamento.

const POLICE := preload("res://gameplay/PoliceAgent.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")

class FakeController extends Node3D:
	var stars := 0
	var health := 100.0
	var last_known_valid := false
	var last_known := Vector3.ZERO
	var player: Node3D
	var shots: Array[Dictionary] = []
	var reloads: Array[Dictionary] = []
	var vehicle_reports: Array[Dictionary] = []
	var drops := 0

	func pursuit_target() -> Node3D: return player
	func police_shoot(officer: CharacterBody3D, amount: float, weapon_id: String = "pistol") -> void:
		shots.append({"officer": officer, "amount": amount, "weapon": weapon_id})
	func police_reload(officer: Node3D, weapon_id: String) -> void:
		reloads.append({"officer": officer, "weapon": weapon_id})
	func report_vehicle_assault(victim: Node3D, source: Node) -> void:
		vehicle_reports.append({"victim": victim, "source": source, "dead": victim.get("dead") == true})
	func drop_ammo(_point: Vector3, _weapon_id: String) -> void: drops += 1
	func police_can_see(_officer: CharacterBody3D) -> bool: return false
	func report_contact(_point: Vector3) -> void: pass
	func find_path(_start: Vector3, _finish: Vector3) -> PackedVector3Array: return PackedVector3Array()

class FakeVehicle extends Node:
	var player_owned := false
	func is_player_damage_source() -> bool: return player_owned

var checks := 0
var failures: Array[String] = []
var controller: FakeController

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	print(("CASE PASS " if ok else "CASE FAIL ") + label + ((" | " + detail) if detail != "" else ""))
	if not ok: failures.append(label)

func make_officer(tier: int) -> CharacterBody3D:
	var officer := POLICE.new()
	officer.tier = tier
	officer.controller = controller
	root.add_child(officer)
	officer.set_physics_process(false)
	return officer

func _run() -> void:
	controller = FakeController.new()
	controller.player = Node3D.new()
	root.add_child(controller)
	controller.add_child(controller.player)

	var expected_weapons := ["pistol", "smg", "m4a1", "m4a1", "m4a1"]
	var expected_health := [50.0, 75.0, 95.0, 110.0, 130.0]
	var expected_damage := [6.0, 6.0, 8.0, 8.0, 8.0]
	for tier in 5:
		controller.shots.clear()
		var officer = make_officer(tier)
		officer._rng.seed = 100 + tier
		check(officer.weapon_id == expected_weapons[tier], "patamar %d usa arma V1" % tier, officer.weapon_id)
		check(is_equal_approx(officer.health, expected_health[tier]), "patamar %d usa vida V1" % tier, str(officer.health))
		check(officer.magazine == int(CATALOG.get_weapon(expected_weapons[tier]).magazine_size), "patamar %d inicia com pente cheio" % tier, str(officer.magazine))
		check(officer._try_fire() and controller.shots.size() == 1
			and is_equal_approx(float(controller.shots[0].amount), expected_damage[tier])
			and controller.shots[0].weapon == expected_weapons[tier],
			"patamar %d dispara dano e som da arma corretos" % tier, str(controller.shots))

	controller.shots.clear()
	var patrol = make_officer(0)
	patrol._rng.seed = 7
	check(patrol._try_fire(), "patrulha dispara o primeiro tiro da rajada")
	patrol.cooldown = 0.0
	check(patrol._try_fire() and patrol.burst_pause >= 1.7 and patrol.burst_pause <= 2.5,
		"patrulha pausa após rajada de dois", "pausa=%.3f" % patrol.burst_pause)
	check(not patrol._try_fire() and controller.shots.size() == 2, "pausa de rajada bloqueia tiro adicional")

	controller.reloads.clear()
	patrol.burst_pause = 0.0
	patrol.magazine = 1
	check(patrol._try_fire() and patrol.magazine == 0 and patrol.reload_timer >= 0.5
		and controller.reloads.size() == 1, "último cartucho inicia uma única recarga",
		"pente=%d recarga=%.3f eventos=%d" % [patrol.magazine, patrol.reload_timer, controller.reloads.size()])
	check(not patrol._try_fire() and controller.reloads.size() == 1, "recarga bloqueia tiro e não reinicia áudio")
	patrol.set_physics_process(true)
	patrol._physics_process(patrol.reload_timer + 0.01)
	patrol.set_physics_process(false)
	check(patrol.reload_timer == 0.0 and patrol.magazine == int(CATALOG.get_weapon("pistol").magazine_size),
		"fim da recarga repõe o pente", "pente=%d" % patrol.magazine)

	controller.vehicle_reports.clear()
	var run_over = make_officer(0)
	run_over.health = 1.0
	var player_vehicle := FakeVehicle.new()
	player_vehicle.player_owned = true
	root.add_child(player_vehicle)
	run_over.receive_damage(2.0, player_vehicle)
	check(run_over.dead and controller.vehicle_reports.size() == 1
		and controller.vehicle_reports[0].source == player_vehicle
		and controller.vehicle_reports[0].dead == true,
		"atropelamento encaminha veículo real após estado fatal", str(controller.vehicle_reports))
	run_over.receive_damage(2.0, player_vehicle)
	check(controller.vehicle_reports.size() == 1, "policial morto não duplica denúncia")

	var traffic_hit = make_officer(0)
	var traffic_vehicle := FakeVehicle.new()
	root.add_child(traffic_vehicle)
	traffic_hit.receive_damage(1.0, traffic_vehicle)
	check(controller.vehicle_reports.size() == 1, "tráfego sem jogador não é atribuído ao jogador")
	traffic_hit.receive_damage(1.0, null)
	check(controller.vehicle_reports.size() == 1, "origem desconhecida não é atribuída ao jogador")

	print("POLICE_COMBAT_CLOSURE checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
