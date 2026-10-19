extends SceneTree
## Limpeza por evento da sessão (morte, prisão, resgate, carregar, menu, transição, viagem).
## Roda as funções de verdade de FullSession.gd com sistemas falsos que só anotam a chamada e
## o estado em volta (saúde, trava de entrada, resgate, prisão, texto do prompt). As listas
## esperadas abaixo são o comportamento das listas escritas à mão antes do registro
## (FullSession.CANCEL_STEPS, docs/session-cleanup-registry.md): mudar a ordem, esquecer um
## sistema ou mover um passo para o outro lado de um guarda quebra aqui.
## Sem Main.tscn, segundos.
## Uso: tools/run_godot_locked.sh --headless --path . --script res://tests/test_session_cleanup_registry.gd
const SESSION_PATH := "res://runtime/FullSession.gd"
const WORLD_PATH := "res://runtime/ProductionWorld.gd"
const LOAD_PLACEHOLDER := "res://tests/__session_cleanup_load_placeholder.tscn"
const MENU_SCENE := "res://ui/MainMenu.tscn"

var checks := 0
var failures: Array[String] = []
var session: TestSession
var systems: Dictionary = {}
var stubs: Array[PackedScene] = []

## A sessão real sem _ready (que montaria o mundo inteiro) e com a apresentação, o save e o
## menu trocados por anotações.
class TestSession extends "res://runtime/FullSession.gd":
	var journal: Array[String] = []
	var real_respawn := false
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _input(_event: InputEvent) -> void: pass
	func flags() -> String:
		var result := ""
		if world.gameplay.health <= 0: result += "D"
		if world.player.input_locked: result += "L"
		if rescue_pending: result += "R"
		if arrest_pending: result += "A"
		if not prompt.text.is_empty(): result += "T"
		return result if not result.is_empty() else "-"
	func note(entry: String) -> void: journal.append(entry + " @" + flags())
	func show_message(text: String) -> void: note("session.show_message(%s)" % text)
	func interrupt_dialogue() -> void: note("session.interrupt_dialogue()")
	func close_menu() -> void: note("session.close_menu()")
	func save_game(_manual := false) -> bool:
		note("session.save_game()")
		return true
	func position_clear(_point: Vector3) -> bool: return true
	func _show_v1_death_presentation() -> void: note("session.death_presentation")
	func _show_v1_arrest_presentation() -> void: note("session.arrest_presentation")
	func _respawn() -> void:
		if real_respawn:
			await super()
			return
		note("session.respawn")

## Um sistema qualquer: anota os comandos, responde às perguntas com as próprias bandeiras.
class Recorder extends Node:
	var id := ""
	var session
	var riding := false
	var active := false
	var stay_active := false
	var busy_flag := false
	var _released := false
	var landing := false
	var _boarding := false
	var unlock_on_cancel := false
	var player_position_override := Vector3.INF
	var spawn_position := Vector3.ZERO
	func _init(system_id: String, owner_session) -> void:
		id = system_id
		session = owner_session
	func _note(method: String, args: Array = []) -> void:
		var parts: Array[String] = []
		for value in args:
			if value == null: continue
			parts.append("v" if value is Vector3 else str(value))
		session.note("%s.%s(%s)" % [id, method, ", ".join(parts)])
	func busy() -> bool: return busy_flag
	func controls_locked() -> bool: return false
	func cancel(reason: Variant = null, restore: Variant = null) -> void: _note("cancel", [reason, restore])
	func cancel_attempt(reason: Variant = null) -> bool:
		_note("cancel_attempt", [reason])
		# Desmontar missão pode devolver uma trava de entrada antiga (comentário de _on_arrest).
		if unlock_on_cancel: session.world.player.input_locked = false
		return true
	func leave() -> void:
		_note("leave")
		if not stay_active: active = false
	func cancel_for_transition() -> void: _note("cancel_for_transition")
	func cancel_auto_service(reason: Variant = null) -> void: _note("cancel_auto_service", [reason])
	func cancel_transition(reason: Variant = null) -> void: _note("cancel_transition", [reason])
	func _brake() -> void: _note("_brake")
	func cancel_press_delivery() -> void: _note("cancel_press_delivery")
	func player_died() -> int:
		_note("player_died")
		return 0
	func close() -> void: _note("close")
	func release_all(reason: Variant = null) -> void: _note("release_all", [reason])
	func dismiss_all(reason: Variant = null) -> void: _note("dismiss_all", [reason])
	func reset() -> void: _note("reset")
	func clear(all: Variant = null) -> void: _note("clear", [all])
	func recover_after_rescue() -> void: _note("recover_after_rescue")
	func recover() -> void: _note("recover")
	func prepare_collision_at(point: Variant = null) -> void: _note("prepare_collision_at", [point])
	func suspend_for_travel() -> void: _note("suspend_for_travel")
	func set_focus(point: Variant = null, force: Variant = null) -> void: _note("set_focus", [point, force])
	func prepare_connection_at(point: Variant = null) -> void: _note("prepare_connection_at", [point])
	func set_location(region_id: Variant = null) -> void: _note("set_location", [region_id])

class FakePlayer extends Node3D:
	var recorder: Recorder
	var input_locked := false
	var collision_layer := 2
	var collision_mask := 7
	func on_player_death() -> void: recorder._note("on_player_death")
	func respawn_player() -> void: recorder._note("respawn_player")
	func teleport(point: Vector3) -> void: recorder._note("teleport", [point])

class FakeGameplay extends Node:
	signal changed
	var recorder: Recorder
	var health := 100.0
	func respawn() -> void:
		recorder._note("respawn")
		health = 100.0
	func _update_visual() -> void: recorder._note("_update_visual")

class FakeHud extends Node:
	var recorder: Recorder
	func refresh_from_state() -> void: recorder._note("refresh_from_state")

class FakeDriving extends Recorder:
	var occupied := false
	var car = null

class FakeCamera extends Node:
	var heading := 0.0
	var target_size := 28.0
	var size := 28.0
	var target = null
	var offset := Vector3.ZERO
	var EXTERIOR_OFFSET := Vector3(0, 10, 10)
	var locked := false
	var initialized := true
	func _process(_delta: float) -> void: pass

class FakeWorld extends Node3D:
	var player: FakePlayer
	var gameplay: FakeGameplay
	var driving: FakeDriving
	var camera: FakeCamera
	var hud: FakeHud
	var traffic_yield: Recorder
	var dispatch: Recorder
	var maciota_place = null
	var people: Array = []

class FakeController extends Recorder:
	var region: Recorder
	var travel_busy := false
	var state

class FakeCampaign extends RefCounted:
	var active_id := ""

class FakeEconomy extends Recorder:
	var cheat_infinite_money := true
	var balance := 0
	func confiscate_carried_ammo() -> int:
		_note("confiscate_carried_ammo")
		return 0

class FakeState extends Recorder:
	var place_id := ""
	var region_id := "harbor"
	var campaign := FakeCampaign.new()
	var economy: FakeEconomy

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): failures.append("watchdog 60 s"); finish())
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("CLEANUP_REGISTRY ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

## Compara a sequência anotada com a esperada e, se diferir, mostra as duas lado a lado.
func check_sequence(label: String, expected: Array) -> bool:
	var got: Array = session.journal.duplicate()
	var ok := got == expected
	if not ok:
		for i in maxi(got.size(), expected.size()):
			var want: String = expected[i] if i < expected.size() else "—"
			var seen: String = got[i] if i < got.size() else "—"
			print("  %s %2d esperado %-60s anotado %s" % ["  " if want == seen else "!!", i + 1, want, seen])
	session.journal.clear()
	return check(ok, label)

func build_session() -> void:
	session = TestSession.new()
	var world := FakeWorld.new()
	world.name = "FakeWorld"
	session.world = world
	world.player = FakePlayer.new()
	world.player.recorder = Recorder.new("player", session)
	world.gameplay = FakeGameplay.new()
	world.gameplay.recorder = Recorder.new("gameplay", session)
	world.gameplay.changed.connect(func(): session.note("gameplay.changed"))
	world.hud = FakeHud.new()
	world.hud.recorder = Recorder.new("hud", session)
	world.driving = FakeDriving.new("driving", session)
	world.camera = FakeCamera.new()
	world.traffic_yield = Recorder.new("traffic_yield", session)
	world.dispatch = Recorder.new("dispatch", session)
	var state := FakeState.new("state", session)
	state.economy = FakeEconomy.new("economy", session)
	session.state = state
	var controller := FakeController.new("controller", session)
	controller.region = Recorder.new("region", session)
	controller.state = state
	session.controller = controller
	session.prompt = Label.new()
	for id in ["upside_world", "fishing", "coastal_lookout", "amusement_park", "regional_coach", "railway",
			"robberies", "desert", "mining", "jessica", "services", "passenger_transport", "garage_rewards",
			"activities", "mountain_progression", "mountain_activities", "mission_world", "arcade",
			"building_entrance", "service_roofs", "cold", "wine", "armored_transport"]:
		var system := Recorder.new(id, session)
		systems[id] = system
		session.set(id, system)
	systems.mission_world.unlock_on_cancel = true
	root.add_child(world)
	root.add_child(session)

## Todo cenário parte do mesmo estado: vivo, livre, sem resgate e com um prompt na tela.
func reset_state() -> void:
	session.journal.clear()
	session.rescue_pending = false
	session.arrest_pending = false
	session.respawn_busy = false
	session.transition_kind = ""
	session.vehicle_transition_busy = false
	session.bank_death_loss = 0
	session.real_respawn = false
	session.prompt.text = "Entrar"
	session.world.gameplay.health = 100.0
	session.world.player.input_locked = false
	session.world.driving.occupied = false
	session.controller.travel_busy = false
	session.state.campaign.active_id = ""
	session.state.place_id = ""
	for system: Recorder in systems.values():
		system.riding = false
		system.active = false
		system.stay_active = false
		system.busy_flag = false
		system._released = false
	if session.jessica == null: session.jessica = systems.jessica

func run() -> void:
	build_session()
	await process_frame
	check_death()
	check_arrest()
	await check_rescue()
	check_transition()
	check_load_refusals()
	check_menu_refusals()
	check_registry()
	check_travel()
	await check_load_and_menu_commit()
	finish()

func check_death() -> void:
	reset_state()
	# Morte durante a prisão: _on_death tira a prisão antes de desmontar embarques.
	session.arrest_pending = true
	systems.passenger_transport.riding = true
	session._on_death()
	check_sequence("morte: mesmos sistemas, mesma ordem, mesmo estado em volta", [
		"upside_world.cancel(death, false) @AT",
		"fishing.cancel_attempt(Pesca interrompida.) @AT",
		"coastal_lookout.leave() @AT",
		"amusement_park.leave() @AT",
		"regional_coach.cancel_for_transition() @AT",
		"railway.cancel_for_transition() @AT",
		"robberies.player_died() @AT",
		"desert.cancel_attempt() @DT",
		"mining.cancel_attempt() @DT",
		"jessica.cancel_for_transition() @DT",
		"services.cancel_auto_service(player_death) @DT",
		"driving.cancel_transition(player_death) @DT",
		"player.on_player_death() @DLT",
		"gameplay.changed @DLT",
		"hud.refresh_from_state() @DLR",
		"passenger_transport._brake() @DLR",
		"session.interrupt_dialogue() @DLR",
		"garage_rewards.cancel_press_delivery() @DLR",
		"activities.cancel_attempt() @DLR",
		"mountain_progression.cancel_attempt() @DLR",
		"mountain_activities.cancel_attempt() @DLR",
		"mission_world.cancel_attempt(player_death) @DLR",
		# Diferença mantida: a morte não volta a travar a entrada depois da desmontagem.
		"session.death_presentation @DR",
		"session.respawn @DR",
	])
	# Segunda morte com o resgate em curso: só a ilusão é cancelada (antes do guarda).
	session.world.player.input_locked = true
	session._on_death()
	check_sequence("morte repetida no resgate só cancela a ilusão", ["upside_world.cancel(death, false) @DLR"])
	# Sem passageiro embarcado o freio não é chamado.
	reset_state()
	session._on_death()
	var braked := session.journal.any(func(entry: String): return entry.begins_with("passenger_transport."))
	session.journal.clear()
	check(not braked, "morte a pé não freia o transporte de passageiros")

func check_arrest() -> void:
	reset_state()
	systems.passenger_transport.riding = true
	session._on_arrest()
	check_sequence("prisão: mesmos sistemas, mesma ordem, mesmo estado em volta", [
		"upside_world.cancel(arrest) @T",
		"amusement_park.leave() @LAT",
		"regional_coach.cancel_for_transition() @LAT",
		"railway.cancel_for_transition() @LAT",
		"session.interrupt_dialogue() @LAT",
		"desert.cancel_attempt() @LAT",
		"mining.cancel_attempt() @LAT",
		"services.cancel_auto_service(player_arrest) @LA",
		"driving.cancel_transition(player_arrest) @LA",
		"passenger_transport._brake() @LA",
		"jessica.cancel_for_transition() @LA",
		"garage_rewards.cancel_press_delivery() @LA",
		"activities.cancel_attempt() @LA",
		"mountain_progression.cancel_attempt() @LA",
		"mountain_activities.cancel_attempt() @LA",
		"mission_world.cancel_attempt(player_arrest) @LA",
		# A custódia volta a travar a entrada que a desmontagem da missão soltou.
		"session.arrest_presentation @LA",
		"session.respawn @LA",
	])
	session._on_arrest()
	check_sequence("prisão repetida não cancela nada", [])
	reset_state()
	session.rescue_pending = true
	session._on_arrest()
	check_sequence("prisão durante o resgate não cancela nada", [])

func check_rescue() -> void:
	reset_state()
	session.rescue_pending = true
	session.world.gameplay.health = 0
	session.world.player.input_locked = true
	session.real_respawn = true
	await session._respawn()
	check_sequence("resgate: mesmos sistemas, mesma ordem, mesmo estado em volta", [
		"upside_world.cancel(rescue, false) @DLRT",
		# _begin_transition("rescue")
		"arcade.close() @DLRT",
		"fishing.cancel_attempt(Pesca encerrada.) @DLRT",
		"coastal_lookout.leave() @DLRT",
		"amusement_park.leave() @DLRT",
		"mountain_activities.cancel_attempt() @DLRT",
		"region.set_focus(v) @DLRT",
		"controller.prepare_connection_at(v) @DLRT",
		"cold.prepare_collision_at(v) @DLRT",
		"passenger_transport.cancel_for_transition() @DLRT",
		"building_entrance.reset() @DLRT",
		"service_roofs.clear(true) @DLRT",
		"state.set_location(harbor) @DLRT",
		"gameplay.respawn() @DLRT",
		"player.respawn_player() @LRT",
		"traffic_yield.release_all(rescue) @LRT",
		"dispatch.dismiss_all(rescue) @LRT",
		"cold.recover_after_rescue() @LRT",
		"wine.recover() @LRT",
		"player.teleport(v) @LRT",
		"gameplay._update_visual() @LR",
		"hud.refresh_from_state() @LR",
		"session.close_menu() @L",
		"session.save_game() @L",
	])
	check(session.transition_kind.is_empty() and not session.respawn_busy, "resgate devolve a transição")
	reset_state()
	session.respawn_busy = true
	session.real_respawn = true
	await session._respawn()
	check_sequence("resgate em curso só cancela a ilusão", ["upside_world.cancel(rescue, false) @T"])

func check_transition() -> void:
	reset_state()
	var generation: int = session.transition_generation
	var token: int = session._begin_transition("test")
	check_sequence("transição: fliperama, pesca, mirante, parque e serra", [
		"arcade.close() @T",
		"fishing.cancel_attempt(Pesca encerrada.) @T",
		"coastal_lookout.leave() @T",
		"amusement_park.leave() @T",
		"mountain_activities.cancel_attempt() @T",
	])
	check(token == generation + 1 and session.transition_kind == "test", "transição aceita ganha a vez")
	session._finish_transition(token)
	reset_state()
	systems.amusement_park.active = true
	systems.amusement_park.stay_active = true
	generation = session.transition_generation
	token = session._begin_transition("test")
	check_sequence("parque que não solta o jogador recusa antes da serra", [
		"arcade.close() @T",
		"fishing.cancel_attempt(Pesca encerrada.) @T",
		"coastal_lookout.leave() @T",
		"amusement_park.leave() @T",
	])
	check(token == -1 and session.transition_generation == generation and session.transition_kind.is_empty(), "parque preso não consome a geração")
	reset_state()
	session.transition_kind = "other"
	check(session._begin_transition("test") == -1, "transição ocupada é recusada")
	check_sequence("transição ocupada não cancela nada", [])
	reset_state()
	session.controller.travel_busy = true
	check(session._begin_transition("test") == -1, "viagem em curso recusa a transição")
	check_sequence("viagem em curso não cancela nada", [])

## Cada recusa do carregar vem depois de pesca, mirante e parque: um carregar recusado já
## encerrou os três (diferença mantida, ver docs/session-cleanup-registry.md).
func check_load_refusals() -> void:
	var load_first := [
		"upside_world.cancel(load) @T",
		"fishing.cancel_attempt(Pesca encerrada.) @T",
		"coastal_lookout.leave() @T",
		"amusement_park.leave() @T",
	]
	reset_state()
	systems.upside_world.busy_flag = true
	systems.upside_world._released = true
	session.load_game()
	check_sequence("carregar com a ilusão soltando só avisa", ["session.show_message(Aguarde a conclusão da transição para carregar.) @T"])
	var refusals := [
		["desert", "Encerre a prova para carregar."],
		["jessica", "Aguarde Jessica estacionar para carregar."],
		["transition", "Aguarde a conclusão da transição para carregar."],
		["passenger_transport", "Aguarde o desembarque para carregar."],
		["driving", "Saia do veículo para carregar."],
	]
	for refusal: Array in refusals:
		reset_state()
		match refusal[0]:
			"desert": systems.desert.busy_flag = true
			"jessica": systems.jessica.riding = true
			"transition": session.transition_kind = "other"
			"passenger_transport": systems.passenger_transport.riding = true
			"driving": session.world.driving.occupied = true
		session.load_game()
		check_sequence("carregar recusado por %s" % refusal[0], load_first + ["session.show_message(%s) @T" % refusal[1]])

func check_menu_refusals() -> void:
	reset_state()
	systems.upside_world.busy_flag = true
	systems.upside_world._released = true
	session.return_to_main_menu()
	check_sequence("menu com a ilusão soltando só avisa", ["session.show_message(Aguarde a conclusão da transição.) @T"])
	for blocker in ["transition", "passenger_transport"]:
		reset_state()
		if blocker == "transition": session.transition_kind = "other"
		else: systems.passenger_transport.riding = true
		session.return_to_main_menu()
		# Deserto e mineração já foram cancelados quando o menu recusa (diferença mantida).
		check_sequence("menu recusado por %s" % blocker, [
			"upside_world.cancel(main_menu) @T",
			"amusement_park.leave() @T",
			"desert.cancel_attempt() @T",
			"mining.cancel_attempt() @T",
			"session.show_message(Aguarde a conclusão da chegada, do resgate ou da transição.) @T",
		])

## Carregar e menu aceitos trocam a cena: as duas cenas viram marcadores vazios no cache para
## que nenhum jogo ou menu de verdade monte aqui.
func check_load_and_menu_commit() -> void:
	var holder_scene := stub_scene(LOAD_PLACEHOLDER, "LoadPlaceholder")
	stub_scene(MENU_SCENE, "MenuPlaceholder")
	var holder := holder_scene.instantiate()
	holder.scene_file_path = LOAD_PLACEHOLDER
	root.add_child(holder)
	current_scene = holder
	reset_state()
	session.load_game()
	check_sequence("carregar aceito: pesca, mirante, parque, depois prensa, trânsito e despacho", [
		"upside_world.cancel(load) @T",
		"fishing.cancel_attempt(Pesca encerrada.) @T",
		"coastal_lookout.leave() @T",
		"amusement_park.leave() @T",
		"garage_rewards.cancel_press_delivery() @T",
		"traffic_yield.release_all(load) @T",
		"dispatch.dismiss_all(load) @T",
	])
	await process_frame
	await process_frame
	reset_state()
	session.return_to_main_menu()
	check_sequence("menu aceito: parque, deserto, mineração, depois prensa, trânsito e despacho", [
		"upside_world.cancel(main_menu) @T",
		"amusement_park.leave() @T",
		"desert.cancel_attempt() @T",
		"mining.cancel_attempt() @T",
		"garage_rewards.cancel_press_delivery() @T",
		"traffic_yield.release_all(main_menu) @T",
		"dispatch.dismiss_all(main_menu) @T",
	])
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.name == "MenuPlaceholder", "a troca de cena caiu no marcador, não no menu de verdade")

func stub_scene(path: String, node_name: String) -> PackedScene:
	var node := Node.new()
	node.name = node_name
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	packed.take_over_path(path)
	# O cache de recursos guarda referência fraca: o teste segura a cena até o fim.
	stubs.append(packed)
	return packed

## O registro em si: etapas conhecidas, sistemas que existem na sessão e métodos que existem
## na classe de verdade de cada sistema (renomear um método quebra aqui, não no meio do jogo).
func check_registry() -> void:
	var constants: Dictionary = (load(SESSION_PATH) as Script).get_script_constant_map()
	if not check(session.has_method("_cancel_for") and constants.has("CANCEL_STEPS"), "registro de limpeza existe na sessão"): return
	var steps: Dictionary = constants.CANCEL_STEPS
	var stages: Array = steps.keys().map(func(stage): return String(stage))
	stages.sort()
	check(stages == ["arrest_1", "arrest_2", "arrest_3", "death_1", "death_2", "death_3", "death_4", "load_1", "load_2", "menu_1", "menu_2", "rescue_1", "rescue_2", "rescue_3", "transition", "travel"], "etapas do registro: %s" % ", ".join(stages))
	var scripts := system_scripts()
	var properties: Array = session.get_property_list().map(func(item): return item.name)
	var missing: Array[String] = []
	for stage in steps:
		for step: Array in steps[stage]:
			var path: String = step[0]
			var method: String = step[1]
			var rule: String = step[3] if step.size() > 3 else ""
			if rule not in ["", "if_method", "if_riding", "if_jessica_bank", "abort_if_active"]: missing.append("%s: regra %s" % [stage, rule])
			if path.is_empty():
				if not session.has_method(method): missing.append("%s: sessão.%s" % [stage, method])
				continue
			var root_name := path.get_slice(".", 0)
			if root_name not in properties: missing.append("%s: propriedade %s" % [stage, root_name])
			if path.contains("."): continue
			if not scripts.has(path):
				missing.append("%s: %s sem script conhecido" % [stage, path])
				continue
			if not script_has_method(scripts[path], method): missing.append("%s: %s.%s" % [stage, path, method])
	check(missing.is_empty(), "todo passo aponta para sistema e método reais%s" % ("" if missing.is_empty() else ": " + ", ".join(missing)))

## Variável da sessão → script que _ready instancia nela.
func system_scripts() -> Dictionary:
	var source := FileAccess.get_file_as_string(SESSION_PATH)
	var pattern := RegEx.create_from_string("(?m)^\\s*(\\w+) = preload\\(\"(res://[^\"]+)\"\\)\\.new\\(\\)")
	var result := {}
	for found in pattern.search_all(source): result[found.get_string(1)] = load(found.get_string(2))
	return result

func script_has_method(script: Script, method: String) -> bool:
	var current := script
	while current != null:
		for item in current.get_script_method_list():
			if item.name == method: return true
		current = current.get_base_script()
	return false

## ProductionWorld._travel_checked é grande demais para rodar com falsos: a etapa roda direto
## e o código da viagem é conferido no texto (a etapa fica depois do teste de solo, antes da
## troca de região, e nenhuma das chamadas antigas sobrou ali).
func check_travel() -> void:
	if not session.has_method("_cancel_for"): return
	var full := [
		"armored_transport.suspend_for_travel() @T",
		"passenger_transport.cancel_for_transition() @T",
		"activities.cancel_attempt() @T",
		"mountain_progression.cancel_attempt() @T",
		"mountain_activities.cancel_attempt() @T",
		"garage_rewards.cancel_press_delivery() @T",
		"mission_world.cancel_attempt(world_transition) @T",
		"jessica.cancel_for_transition() @T",
		"traffic_yield.release_all(travel) @T",
		"dispatch.dismiss_all(travel) @T",
	]
	reset_state()
	session.state.campaign.active_id = "jessica_bank"
	session.world.player.input_locked = false
	systems.mission_world.unlock_on_cancel = false
	check(session._cancel_for(&"travel"), "viagem não aborta")
	check_sequence("viagem no assalto da Jessica encerra a missão antes dela", full)
	reset_state()
	session._cancel_for(&"travel")
	check_sequence("viagem fora do assalto não mexe na missão", full.filter(func(entry: String): return not entry.begins_with("mission_world.")))
	reset_state()
	session.state.campaign.active_id = "jessica_bank"
	session.jessica = null
	session._cancel_for(&"travel")
	check_sequence("sem Jessica a missão do assalto não é encerrada pela viagem", full.filter(func(entry: String): return not entry.begins_with("mission_world.") and not entry.begins_with("jessica.")))
	session.jessica = systems.jessica
	systems.mission_world.unlock_on_cancel = true
	var source := FileAccess.get_file_as_string(WORLD_PATH)
	var start := source.find("func _travel_checked(")
	var body := source.substr(start, source.find("\nfunc ", start + 1) - start)
	var stage_at := body.find("session._cancel_for(&\"travel\")")
	check(stage_at > body.find("Destino ocupado ou sem solo") and stage_at < body.find("world.gameplay.on_region_changed()"), "viagem chama a etapa depois do teste de solo e antes da troca de região")
	var leftovers: Array[String] = []
	for call in ["suspend_for_travel", "cancel_for_transition", "cancel_attempt", "cancel_press_delivery", "release_all", "dismiss_all"]:
		if body.contains(call): leftovers.append(call)
	check(leftovers.is_empty(), "viagem sem chamadas de limpeza fora do registro%s" % ("" if leftovers.is_empty() else ": " + ", ".join(leftovers)))

## Os falsos ficam fora da árvore: soltá-los aqui evita o aviso de vazamento no fim.
func release_fakes() -> void:
	if session == null: return
	var world = session.world
	var loose: Array = systems.values() + [world.player.recorder, world.player, world.gameplay.recorder, world.gameplay,
		world.hud.recorder, world.hud, world.driving, world.camera, world.traffic_yield, world.dispatch,
		session.controller.region, session.controller, session.state.economy, session.state, session.prompt]
	for node in loose:
		if is_instance_valid(node) and not node.is_inside_tree(): node.free()
	session = null

func finish() -> void:
	release_fakes()
	print("CLEANUP_REGISTRY checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: print("CLEANUP_REGISTRY FAILURE ", failure)
	quit(0 if failures.is_empty() else 1)
