extends SceneTree
## Contratos centrais sem carregar o mundo (segundos, não minutos): recuperação de save,
## achados das cavernas do deserto e a tabela de vítimas do crime. É o primeiro passo de
## tools/run_core_suite.sh; quebrou aqui, o resto da suíte nem precisa rodar.
## Uso: "$GODOT" --headless --path . --script res://tests/test_core_contracts.gd
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const WILDS := preload("res://runtime/desert/wilds/DesertWilds.gd")
const VICTIMS := preload("res://gameplay/police_response/CrimeVictims.gd")

class IsolatedLaunch extends "res://runtime/SessionLaunch.gd":
	var folder := ""
	func slot_path(id: String) -> String:
		return folder.path_join(id + ".json") if id in ["progress"] + SLOT_IDS else ""

class RecordingGameplay extends "res://gameplay/Gameplay.gd":
	var reported: Array = []
	func report_observed_crime(points: int, _point: Vector3, kind: String = "theft", _victim: Node3D = null) -> bool:
		reported.append("%s:%d" % [kind, points])
		return true

class FakeState extends RefCounted:
	var place_id := ""
	func weapons_allowed() -> bool: return true

class FakePerson extends CharacterBody3D:
	var health := 100.0
	var dead := false
	func _init(role: String) -> void:
		if not role.is_empty(): set_meta("gameplay_role", role)
	func receive_damage(amount: float, _source: Node = null) -> void:
		if dead or amount <= 0.0: return
		health = maxf(0.0, health - amount)
		dead = health <= 0.0

class FakeVehicle extends Node:
	func is_player_damage_source() -> bool: return true

var checks := 0
var failures: Array[String] = []
var folder := ""

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): failures.append("watchdog 60 s"); finish())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CORE_CONTRACTS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func run() -> void:
	folder = "user://tests/core_contracts_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	save_recovery()
	slot_recovery()
	desert_caves()
	await crime_victims()
	finish()

# --- Save que um bloco quebrado não pode mais tornar inabrível -------------------------------

func save_recovery() -> void:
	var base: Dictionary = STATE.new().snapshot()
	base.economy.balance = 1234
	var clean: Dictionary = STORE.recover_snapshot(base)
	check(not clean.is_empty() and clean.dropped.is_empty(), "save válido não perde nada")
	var one := base.duplicate(true)
	one.world.ashbend_secret_car_claimed = "sim"
	check(not STATE.new().restore_snapshot(one), "fixture: bloco inválido derruba a validação estrita")
	var plan: Dictionary = STORE.recover_snapshot(one)
	check(not plan.is_empty() and plan.dropped == ["ashbend_secret_car_claimed"], "um bloco quebrado: só ele volta ao padrão")
	check(not plan.is_empty() and int(plan.data.economy.balance) == 1234, "carteira sobrevive à recuperação")
	check(not plan.is_empty() and STATE.new().restore_snapshot(plan.data), "snapshot recuperado passa na validação estrita")
	var two := one.duplicate(true)
	two.world.remote_coal_secret_revealed = 7
	plan = STORE.recover_snapshot(two)
	var dropped: Array = plan.get("dropped", [])
	dropped.sort()
	check(dropped == ["ashbend_secret_car_claimed", "remote_coal_secret_revealed"], "dois blocos quebrados: só os dois saem (%s)" % [dropped])
	var moved := base.duplicate(true)
	moved.place_id = "lugar_que_nao_existe_mais"
	plan = STORE.recover_snapshot(moved)
	check(plan.get("dropped", []) == [STORE.RECOVERY_LOCATION] and str(plan.data.place_id).is_empty(), "lugar removido do catálogo: volta ao ponto de retorno")
	var core := base.duplicate(true)
	core.economy = {"version": 1}
	check(STORE.recover_snapshot(core).is_empty(), "carteira corrompida não é 'recuperada' por descarte")

	var path := folder.path_join("slot.json")
	var broken_text := JSON.stringify(one)
	write(path, broken_text)
	var store = STORE.new()
	store.path = path
	check(not store.load_into(STATE.new()).get("ok", false), "fixture: slot quebrado não carrega sem recuperação")
	plan = STORE.recovery_plan(path)
	check(not plan.is_empty() and plan.source == path, "plano lê o arquivo principal")
	check(store.publish_recovery(plan) == OK, "recuperação publica o save")
	var restored = STATE.new()
	check(store.load_into(restored).get("ok", false) and restored.economy.balance == 1234, "slot recuperado carrega com a carteira")
	var originals: Array[String] = []
	for name_value in DirAccess.get_files_at(folder):
		if name_value.begins_with("slot.json.pre-recovery."): originals.append(name_value)
	check(originals.size() == 1 and FileAccess.get_file_as_string(folder.path_join(originals[0])) == broken_text, "bytes originais guardados ao lado (.pre-recovery)")

func slot_recovery() -> void:
	var launch := IsolatedLaunch.new()
	launch.folder = folder.path_join("slots")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(launch.folder))
	var broken: Dictionary = STATE.new().snapshot()
	broken.world.ashbend_secret_car_claimed = "sim"
	write(launch.slot_path("slot_01"), JSON.stringify(broken))
	write(launch.slot_path("slot_02"), "{ não é JSON")
	var row := {}
	for item in launch.list_slots():
		if item.id == "slot_01": row = item
	check(row.get("valid", false) and row.get("recoverable", false), "menu oferece o slot como recuperável")
	var label := str(row.get("label", ""))
	check(row.get("recovery_dropped", []) == ["ashbend_secret_car_claimed"] and (label.contains("Recuperável") or label.contains("Recoverable")), "rótulo diz o que volta ao padrão (%s)" % label.replace("\n", " "))
	check(launch.latest_slot().is_empty(), "Continuar não recupera às cegas")
	check(launch.prepare("slot_02", false) == ERR_FILE_CORRUPT, "arquivo ilegível continua recusado")
	check(launch.prepare("slot_01", false) == OK, "escolher o slot recupera")
	check(not STORE.read_valid(launch.slot_path("slot_01")).is_empty(), "slot vira um save estritamente válido")
	check(not launch.recovery_notice.is_empty(), "sessão recebe o aviso do que foi redefinido")
	launch.free()

# --- Cavernas do deserto: recibo na carteira, sem teto de dinheiro solto ---------------------

func site(id: String) -> Dictionary:
	for candidate in WILDS.SITES:
		if candidate.id == id: return candidate
	return {}

func desert_caves() -> void:
	var cash := site("cave_vulture")
	var wallet = ECONOMY.new()
	check(int(cash.amount) > 300 and not wallet.collect_loose_cash(int(cash.amount)), "fixture: R$ %d não cabe no dinheiro solto" % int(cash.amount))
	var first: Dictionary = WILDS.claim_cave(wallet, cash)
	check(first.ok and wallet.balance == int(cash.amount), "lata da caverna paga R$ %d inteiros" % int(cash.amount))
	var again: Dictionary = WILDS.claim_cave(wallet, cash)
	check(again.ok and not again.changed and wallet.balance == int(cash.amount), "segunda visita não paga de novo")
	var reloaded = ECONOMY.new()
	check(reloaded.restore_snapshot(wallet.snapshot()) and WILDS.cave_claimed(reloaded, cash), "achado continua pego depois de salvar e carregar")
	var weapon := site("cave_coyote")
	var armed: Dictionary = WILDS.claim_cave(wallet, weapon)
	check(armed.ok and wallet.owns_weapon(str(weapon.weapon)), "caverna entrega a arma")
	check(WILDS.claim_cave(wallet, weapon).ok and not WILDS.claim_cave(wallet, weapon).changed, "arma não sai duas vezes")
	var veteran = ECONOMY.new()
	var repeated := site("cave_sun")
	veteran.grant_weapon(str(repeated.weapon))
	var before := int(veteran.get_ammo(str(repeated.weapon)).reserve)
	var ammo: Dictionary = WILDS.claim_cave(veteran, repeated)
	check(ammo.ok and ammo.reason == "ammo" and int(veteran.get_ammo(str(repeated.weapon)).reserve) == before + WILDS.CAVE_AMMO, "arma repetida vira munição")
	check(WILDS.cave_claimed(veteran, repeated), "munição também marca o achado")
	var state = STATE.new()
	state.economy = wallet
	check(STATE.new().restore_snapshot(state.snapshot()), "recibos das cavernas passam na validação do save")

# --- Tabela de vítimas: arma e atropelamento contam igual ------------------------------------

func classify_role(role: String) -> String:
	var person := FakePerson.new(role)
	var result := VICTIMS.classify(person)
	person.free()
	return result

func crime_victims() -> void:
	check(classify_role("urban_routine") == VICTIMS.PERSON, "morador de prédio é pessoa")
	check(classify_role("cobra") == VICTIMS.HOSTILE, "Cobra é gangue em combate")
	check(classify_role("police") == VICTIMS.POLICE, "policial é policial")
	check(classify_role("") == VICTIMS.OTHER, "sem papel continua 'outro'")
	var guard := FakePerson.new("security")
	guard.set_meta("local_security", true)
	check(VICTIMS.classify(guard) == VICTIMS.OWNER_HANDLED, "segurança do comboio: o dono atribui o crime")

	var gameplay := RecordingGameplay.new()
	var world := Node3D.new()
	var player := CharacterBody3D.new()
	root.add_child(world)
	world.add_child(player)
	gameplay.configure(world, player, null, FakeState.new())
	world.add_child(gameplay)
	gameplay.set_physics_process(false)
	await physics_frame
	var resident := FakePerson.new("urban_routine")
	world.add_child(resident)
	gameplay._damage(resident, 10.0, player)
	check(gameplay.reported == ["assault:12"], "ferir morador a tiro é agressão (%s)" % [gameplay.reported])
	gameplay.reported.clear()
	gameplay._damage(resident, 500.0, player)
	check(gameplay.reported == ["civilian_killed:30"], "matar morador a tiro é homicídio, como atropelar (%s)" % [gameplay.reported])
	gameplay.reported.clear()
	var unknown := FakePerson.new("")
	world.add_child(unknown)
	gameplay._damage(unknown, 500.0, player)
	check(not gameplay.reported.has("civilian_killed:30"), "alvo sem papel nunca vira homicídio (%s)" % [gameplay.reported])
	gameplay.reported.clear()
	var car := FakeVehicle.new()
	world.add_child(car)
	var cobra := FakePerson.new("cobra")
	world.add_child(cobra)
	cobra.dead = true
	gameplay.report_vehicle_assault(cobra, car)
	check(gameplay.reported.is_empty(), "atropelar Cobra não é homicídio de civil (%s)" % [gameplay.reported])
	world.add_child(guard)
	guard.dead = true
	gameplay.report_vehicle_assault(guard, car)
	check(gameplay.reported.is_empty(), "atropelar segurança do comboio fica com o comboio (%s)" % [gameplay.reported])
	var walker := FakePerson.new("civilian")
	world.add_child(walker)
	walker.dead = true
	gameplay.report_vehicle_assault(walker, car)
	check(gameplay.reported == ["civilian_killed:30"], "atropelar pedestre continua homicídio (%s)" % [gameplay.reported])
	world.queue_free()
	await process_frame
	await physics_frame

func _remove_tree(path: String) -> void:
	for name_value in DirAccess.get_files_at(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(name_value)))
	for name_value in DirAccess.get_directories_at(path): _remove_tree(path.path_join(name_value))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func finish() -> void:
	# Só apaga a pasta temporária criada por este teste.
	if folder.begins_with("user://tests/core_contracts_") and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)): _remove_tree(folder)
	print("CORE_CONTRACTS checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
