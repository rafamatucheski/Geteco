extends SceneTree
## M06-C "Turno da noite" sem carregar o mundo (segundos): contrato do estado salvo, save
## antigo, cofre casado com o recibo, máquina do alarme (tiro → reforço → polícia → fogo),
## bloqueio de salvar, livro, cofre e a ligação final. Sessão, Vértice e combate são falsos.
## Uso: tools/run_godot_locked.sh --headless --path . --script res://tests/test_vertice_night_contract.gd
const NIGHT := preload("res://gameplay/urban_v1/vertice_night/VerticeNightState.gd")
const SHIFT := preload("res://gameplay/urban_v1/vertice_night/VerticeNightShift.gd")
const GUARD := preload("res://gameplay/urban_v1/vertice_night/VerticeNightGuard.gd")
const GAME_STATE := preload("res://runtime/GameState.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var failures: Array[String] = []
var checks := 0

class FakeGameplay extends Node3D:
	signal weapon_fired(weapon_id: String, origin: Vector3)
	var player: Node3D
	var stars := 0
	var health := 100.0
	var crimes: Array = []
	var emergency := FakeEmergency.new()
	func pursuit_target() -> Node3D: return player
	func _play_stream(_s, _p, _v, _pitch := 1.0, _r := 0.0) -> void: pass
	func register_crime(points: int, _point: Vector3, kind := "reported", _t := {}) -> void:
		crimes.append(points)
		stars = 2

class FakeEmergency extends RefCounted:
	var fires := 0
	func ignite(_p: Vector3, _s = null, _i := 1.0) -> Node3D:
		fires += 1
		return null

class FakePlayer extends Node3D:
	var dead := false
	var input_locked := false

class FakeDriving extends RefCounted:
	var occupied := false

class FakeWorld extends RefCounted:
	var player: Node3D
	var gameplay: FakeGameplay
	var driving := FakeDriving.new()

class FakeWeather extends RefCounted:
	var time_of_day := 23.0/24.0
	var day := 7
	func moon_day() -> int: return day

class FakeController extends RefCounted:
	var regions := {}
	var save_invalid := false

class FakeSession extends Node:
	var state = preload("res://runtime/GameState.gd").new()
	var world := FakeWorld.new()
	var weather := FakeWeather.new()
	var controller := FakeController.new()
	var ready_for_play := true
	var modal := false
	var rescue_pending := false
	var arrest_pending := false
	var messages: Array = []
	var saves := 0
	var dialogue_done := Callable()
	var shift: Node
	func is_transition_blocked() -> bool: return false
	func position_clear(_p: Vector3) -> bool: return true
	func show_message(text: String) -> void: messages.append(text)
	func show_dialogue(lines: Array, done := Callable()) -> void:
		assert(not lines.is_empty())
		dialogue_done = done
	func finish_dialogue() -> void:
		var done := dialogue_done
		dialogue_done = Callable()
		if done.is_valid(): done.call()
	func save_block_reason() -> String:
		if world.gameplay.stars > 0: return "estrelas"
		return shift.save_block_reason() if is_instance_valid(shift) else ""
	func save_game(_manual := false) -> bool:
		if not save_block_reason().is_empty(): return false
		saves += 1
		return true
	func enter_place(_id: String, _a := true, _b := "") -> bool: return true

class FakeCompany extends Node3D:
	var night_hold := false
	var night_gate_open := false
	var night_office_access := false
	var night_alarm := false
	func box(id: String, at: Vector3, _size: Vector3, _color: String, _solid := false, parent: Node3D = self) -> MeshInstance3D:
		var mesh := MeshInstance3D.new()
		mesh.name = id
		mesh.position = at
		parent.add_child(mesh)
		return mesh
	func set_night_hold(value: bool) -> void: night_hold = value
	func set_night_alarm(value: bool) -> void: night_alarm = value

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("VERTICE_NIGHT ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	_state_contract()
	_save_contract()
	_guard_contract()
	await _alarm_flow()
	await _stealth_flow()
	print("VERTICE_NIGHT %s (%d verificações)" % ["OK" if failures.is_empty() else "FALHOU: " + ", ".join(failures), checks])
	quit(0 if failures.is_empty() else 1)

func _state_contract() -> void:
	check(NIGHT.valid(NIGHT.defaults()), "padrão válido")
	var bad := NIGHT.defaults()
	bad.stage = "infiltrando"
	check(not NIGHT.valid(bad), "etapa desconhecida recusada")
	bad = NIGHT.defaults()
	bad.route = "stealth"
	check(not NIGHT.valid(bad), "rota antes do livro recusada")
	bad = {"version":1, "stage":"offered", "route":"", "safe":true, "closed_until":0}
	check(not NIGHT.valid(bad), "cofre antes do livro recusado")
	bad = {"version":1, "stage":"done", "route":"stealth", "safe":false, "closed_until":9}
	check(not NIGHT.valid(bad), "fita da polícia sem tiroteio recusada")
	var extra := NIGHT.defaults()
	extra.extra = 1
	check(not NIGHT.valid(extra), "chave a mais recusada")
	check(NIGHT.valid({"version":1, "stage":"done", "route":"loud", "safe":false, "closed_until":12}), "fim no tiro com fita é válido")

func _save_contract() -> void:
	var game = GAME_STATE.new()
	var old: Dictionary = game.snapshot()
	old.world.erase(NIGHT.KEY)
	check(GAME_STATE.new().restore_snapshot(old.duplicate(true)), "save antigo sem a chave continua válido")
	var offered: Dictionary = old.duplicate(true)
	offered.world[NIGHT.KEY] = {"version":1, "stage":"offered", "route":"", "safe":false, "closed_until":0}
	check(not GAME_STATE.new().restore_snapshot(offered), "missão oferecida sem Cortar o abastecimento é recusada")
	var wallet = ECONOMY.new()
	var receipt: Dictionary = wallet.grant_world_reward({"id":NIGHT.SAFE_RECEIPT, "kind":"cash", "amount":NIGHT.SAFE_CASH})
	check(receipt.ok, "recibo do cofre concedido")
	var progress := ["cobra_supply"]
	var stealth := {NIGHT.KEY: {"version":1, "stage":"done", "route":"stealth", "safe":true, "closed_until":0}}
	check(NIGHT.valid_world(stealth, wallet.snapshot(), progress), "cofre levado casa com o recibo")
	check(not NIGHT.valid_world({NIGHT.KEY: {"version":1, "stage":"done", "route":"stealth", "safe":false, "closed_until":0}}, wallet.snapshot(), progress), "recibo sem cofre recusado")
	check(not NIGHT.valid_world({}, wallet.snapshot(), progress), "recibo sem estado recusado")
	check(not NIGHT.valid_world(stealth, ECONOMY.new().snapshot(), progress), "cofre sem recibo recusado")
	check(NIGHT.valid_world({}, ECONOMY.new().snapshot(), []), "carteira e mundo sem a missão são válidos")

func _guard_contract() -> void:
	var guard = GUARD.new()
	root.add_child(guard)
	guard.set_physics_process(false)
	check(guard.mode == GUARD.CALM, "vigia começa calmo")
	guard.global_position = Vector3.ZERO
	var alerted := false
	for i in 3: alerted = guard.perceive(true, Vector3(0,0,-10), .15) or alerted
	check(guard.mode == GUARD.SUSPICIOUS and not alerted, "vigia longe desconfia antes de alertar")
	for i in 40: alerted = guard.perceive(true, Vector3(0,0,-10), .15) or alerted
	check(alerted, "vigia que continua vendo dá o alerta")
	guard.calm_down()
	guard.search(Vector3(3,0,3))
	for i in 100: guard.perceive(false, Vector3.ZERO, .15)
	check(guard.mode == GUARD.SEARCHING and guard.suspicion >= .5, "busca não esfria sozinha")
	guard.free()

func _make() -> Array:
	var session := FakeSession.new()
	var player := FakePlayer.new()
	root.add_child(session)
	session.add_child(player)
	var gameplay := FakeGameplay.new()
	gameplay.player = player
	session.add_child(gameplay)
	session.world.player = player
	session.world.gameplay = gameplay
	session.state.region_id = "harbor"
	session.state.intro._state.phase = "complete"
	var company := FakeCompany.new()
	company.position = SHIFT.ORIGIN
	session.add_child(company)
	var shift = SHIFT.new()
	shift.configure(session, company)
	company.add_child(shift)
	session.shift = shift
	shift.set_process(false)
	session.state.world_state[NIGHT.KEY] = {"version":1, "stage":"offered", "route":"", "safe":false, "closed_until":0}
	player.position = SHIFT.ORIGIN + Vector3(0,0,10)
	return [session, shift, company, gameplay]

func _alarm_flow() -> void:
	var made := _make()
	var session: FakeSession = made[0]
	var shift = made[1]
	var company: FakeCompany = made[2]
	var gameplay: FakeGameplay = made[3]
	await process_frame
	shift._begin()
	check(shift.running and company.night_hold and company.night_office_access, "operação noturna segura a equipe do dia e abre o escritório")
	check(shift.save_block_reason() != "", "salvar bloqueado dentro da Vértice")
	gameplay.weapon_fired.emit("pistol", SHIFT.ORIGIN + Vector3(0,0,200))
	check(not shift.alarm, "tiro longe não liga o alarme")
	gameplay.weapon_fired.emit("pistol", SHIFT.ORIGIN + Vector3(10,0,30))
	check(shift.alarm and company.night_alarm, "primeiro tiro liga o alarme e as luzes")
	check(shift.save_block_reason().contains("alarme"), "salvar bloqueado no alarme")
	shift._tick_alarm(SHIFT.REINFORCEMENT_SECONDS)
	check(shift.van_phase == "driving" and company.night_gate_open, "van do reforço chega com o portão aberto")
	shift._drive_van(SHIFT.VAN_SECONDS + .1)
	check(shift.van_phase == "parked" and shift._pending.slice(-SHIFT.REINFORCEMENTS.size()) == SHIFT.REINFORCEMENTS, "van estaciona e desce o reforço")
	check(gameplay.crimes.is_empty(), "polícia ainda não veio")
	shift._tick_alarm(SHIFT.POLICE_SECONDS - SHIFT.REINFORCEMENT_SECONDS)
	check(gameplay.crimes.size() == 1 and gameplay.stars > 0, "polícia vem depois do reforço (procurado)")
	check(shift.fire_seconds_left() > 0.0, "tempo do arquivo na tela")
	shift._tick_alarm(SHIFT.FIRE_SECONDS)
	check(gameplay.emergency.fires == SHIFT.ARCHIVE_FIRES.size() and shift.book_burned, "briga longa queima o arquivo e o livro")
	check(shift.nearest_action().get("target","") != "vertice_night_book", "livro queimado some das ações")
	shift._end()
	check(not shift.running and not company.night_hold and not company.night_alarm, "fim da operação devolve a Vértice")
	check(shift.stage() == "offered" and shift.objective().contains("outra noite"), "fracasso espera outra noite")
	# Caminho no tiro com o livro: fita da polícia e Vértice fechada.
	gameplay.stars = 0
	shift._failed_night = -999
	shift._begin()
	shift.raise_alarm("gate")
	shift._book_done()
	check(shift.data().stage == "escaping" and shift.data().route == "loud", "livro no tiro marca rota no tiro")
	check(not shift._open_safe(), "cofre não abre no tiro")
	check(shift.nearest_action().get("target","") != "vertice_night_safe", "cofre queimado fora das ações")
	shift._release()
	shift._maciota_call_done()
	check(shift.data().stage == "done" and shift.data().closed_until == session.weather.day + NIGHT.CLOSED_DAYS, "tiro fecha a Vértice uns dias")
	check(NIGHT.closed_by_police(session.state.world_state, session.weather.day + 1) and not NIGHT.closed_by_police(session.state.world_state, session.weather.day + NIGHT.CLOSED_DAYS), "fita some depois dos dias")
	check(session.saves == 1, "ligação do Maciota salva")
	session.queue_free()
	await process_frame

func _stealth_flow() -> void:
	var made := _make()
	var session: FakeSession = made[0]
	var shift = made[1]
	session.state.world_state[NIGHT.KEY] = NIGHT.defaults()
	session.state.campaign._data.completed.append("cobra_supply")
	await process_frame
	shift._try_neco_call()
	check(shift._in_dialogue and session.dialogue_done.is_valid(), "Neco liga à noite depois de Cortar o abastecimento")
	session.finish_dialogue()
	check(shift.stage() == "offered" and session.saves == 1, "ligação do Neco abre a missão e salva")
	shift._begin()
	shift._book_done()
	check(shift.data().route == "stealth" and not shift.alarm, "livro escondido marca rota escondida")
	var balance: int = session.state.economy.balance
	check(shift._open_safe() and session.state.economy.balance == balance + NIGHT.SAFE_CASH, "cofre paga uma vez")
	check(not shift._open_safe(), "cofre não paga duas vezes")
	shift._release()
	shift._maciota_call_done()
	var final: Dictionary = shift.data()
	check(final.stage == "done" and final.closed_until == 0 and final.safe, "fim escondido sem fita e com o cofre")
	check(NIGHT.valid_world(session.state.world_state, session.state.economy.snapshot(), ["cobra_supply"]), "estado final escondido passa no contrato do save")
	session.queue_free()
	await process_frame
