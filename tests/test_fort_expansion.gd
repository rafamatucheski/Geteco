extends SceneTree
## Lógica da expansão do forte (docs/forte-expansao-20261031.md), sem carregar o mundo:
## ordem das fases, recompensa única (Economy com recibo), save/load no meio da operação,
## validação de save forjado, rádio do operador chamando reforço e parâmetros dos tipos
## novos de soldado. NÃO cobre a geometria das salas (ainda não existe) nem a IA rodando
## na física: isso fica para tests/test_fort_operation.gd quando as salas forem montadas.

const STATE := preload("res://gameplay/urban_v1/fort/FortExpansionState.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const SOLDIER := preload("res://gameplay/urban_v1/fort/FortSoldier.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run()
	print("FORT_EXP %d checks, %d falhas" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check(ok: bool,label: String) -> void:
	checks += 1
	print("FORT_EXP ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1
		push_error("FORT_EXP FAIL "+label)

## Simula o save: world_state passa por JSON (inteiros viram float) e o Economy por
## snapshot/restore.
func save_load(world_state: Dictionary,economy) -> Array:
	var world_copy: Dictionary = JSON.parse_string(JSON.stringify(world_state))
	var economy_copy = ECONOMY.new()
	var restored: bool = economy_copy.restore_snapshot(str_to_var(var_to_str(economy.snapshot())))
	return [world_copy,economy_copy,restored]

func _run() -> void:
	var world := {"rewards":[]}
	var economy = ECONOMY.new()
	var start_balance := int(economy.snapshot().balance)

	# --- Fases ---------------------------------------------------------------
	check(STATE.stage(world) == "locked" and not world.has(STATE.KEY),"sem expansão: fase locked e leitura não grava")
	check(STATE.journal_line(world) == "","diário vazio antes de abrir")
	check(not STATE.complete_area(world,economy,"barracks").ok,"não pula para o alojamento antes da mesa")
	check(STATE.unlock(world) and STATE.stage(world) == "desk","sala de operações limpa abre a mesa")
	check(not STATE.unlock(world),"abrir de novo não muda nada")
	var desk := STATE.complete_area(world,economy,"desk")
	check(desk.ok and desk.reason == "completed" and desk.clues == ["fort_desk_memo"],"mesa entrega o memorando")
	check(STATE.stage(world) == "barracks","fase seguinte: alojamento")
	check(not STATE.journal_line(world).is_empty(),"diário aponta o alojamento")

	var barracks := STATE.complete_area(world,economy,"barracks",true)
	check(barracks.ok and int(barracks.granted) == 4000,"alojamento silencioso paga 2500 + 1500")
	check(int(economy.snapshot().balance) == start_balance+4000,"saldo subiu pelo Economy")
	var again := STATE.complete_area(world,economy,"barracks",true)
	check(again.ok and again.reason == "already_done" and int(again.granted) == 0,"alojamento não paga duas vezes")
	check(int(economy.snapshot().balance) == start_balance+4000,"saldo intacto depois da repetição")

	# --- Save/load no meio da operação ---------------------------------------
	var loaded := save_load(world,economy)
	check(bool(loaded[2]),"Economy restaurado")
	var world2: Dictionary = loaded[0]
	var economy2 = loaded[1]
	check(STATE.validate(world2[STATE.KEY]),"estado passa pelo JSON e continua válido")
	check(STATE.stage(world2) == "armory","fase arsenal sobrevive ao save")
	check(STATE.complete_area(world2,economy2,"barracks").reason == "already_done","recibo local sobrevive ao save")
	# Save caído entre o Economy e o recibo local: o Economy recusa pagar de novo.
	var torn: Dictionary = world2.duplicate(true)
	torn[STATE.KEY].receipts.erase("barracks")
	torn[STATE.KEY].stage = "barracks"
	var torn_economy = save_load(world2,economy2)[1]
	var torn_result := STATE.complete_area(torn,torn_economy,"barracks",true)
	check(torn_result.ok and int(torn_result.granted) == 0,"save rasgado não paga o alojamento de novo")

	var armory := STATE.complete_area(world2,economy2,"armory")
	check(armory.ok and economy2.owns_weapon("hunting_rifle"),"arsenal entrega o fuzil de caça")
	var m4_before := int(economy2.get_ammo("m4a1").get("reserve",0))
	check(STATE.complete_area(world2,economy2,"armory").reason == "already_done","arsenal não repete")
	check(int(economy2.get_ammo("m4a1").get("reserve",0)) == m4_before,"munição do arsenal não duplica")

	check(not STATE.reinforcements_cut(world2),"reforços ativos antes do comando")
	var command := STATE.complete_area(world2,economy2,"command")
	check(command.ok and int(command.granted) == 12000 and command.clues.size() == 3,"cofre do comando: R$ 12.000 e três pistas")
	check(STATE.reinforcements_cut(world2),"comando corta os reforços")
	check(STATE.stage(world2) == "complete" and STATE.journal_line(world2) == "","operação completa some do diário")
	check(STATE.peek(world2).clues.size() == STATE.CLUES.size(),"todas as pistas registradas uma vez")

	# --- Cânone: pistas não fecham o setor lacrado ---------------------------
	var canon_ok := true
	for clue in STATE.CLUES:
		var text := str(STATE.CLUES[clue].text).to_lower()
		for word in ["sobrenatural","demônio","fantasma","maldição","criatura"]:
			if word in text: canon_ok = false
	check(canon_ok,"nenhuma pista confirma origem sobrenatural")

	# --- Save forjado --------------------------------------------------------
	check(not STATE.validate({"version":1,"stage":"barracks","receipts":["command"],"clues":[],"reinforcements_cut":true}),"recusa recibo de fase futura")
	check(not STATE.validate({"version":1,"stage":"desk","receipts":[],"clues":["x"],"reinforcements_cut":false}),"recusa pista desconhecida")
	check(not STATE.validate({"version":2,"stage":"desk","receipts":[],"clues":[],"reinforcements_cut":false}),"recusa versão desconhecida")

	# --- Rádio ---------------------------------------------------------------
	var radio = STATE.RadioCall.new()
	var calls := 0
	for _step in 50:
		if radio.tick(.1,true,true,false): calls += 1
	check(calls == 0 and radio.fraction() < 1.0,"5 s em combate ainda não chamou")
	for _step in 30:
		if radio.tick(.1,true,true,false): calls += 1
	check(calls == 1,"operador vivo por 6 s chama reforço uma vez")
	var quick = STATE.RadioCall.new()
	for _step in 20: quick.tick(.1,true,true,false)
	check(not quick.tick(10.0,false,true,false),"operador abatido não chama")
	var muted = STATE.RadioCall.new()
	var muted_called := false
	for _step in 100: muted_called = muted_called or muted.tick(.1,true,true,true)
	check(not muted_called,"rádio cortado no comando não chama")

	# --- Tipos de soldado ----------------------------------------------------
	var marksman = SOLDIER.new()
	marksman.configure(null,{"id":"t_marksman","role":"marksman"})
	check(marksman.fire_range > SOLDIER.FIRE_RANGE and marksman.burst_size == Vector2i(1,1) and marksman.shot_damage > 7.0,"atirador: alcance maior, tiro único e forte")
	var shield = SOLDIER.new()
	shield.configure(null,{"id":"t_shield","role":"shield"})
	check(shield.front_armor >= .7 and shield.cover_mode == "advance" and shield.speed_scale < 1.0,"escudeiro: blindagem frontal, avança devagar")
	var radioman = SOLDIER.new()
	radioman.configure(null,{"id":"t_radio","role":"radioman"})
	check(radioman.cover_mode == "retreat" and radioman.max_health < 100.0,"operador de rádio: frágil e recua")
	var sleeper = SOLDIER.new()
	sleeper.configure(null,{"id":"t_sleep","role":"sentry","sleeping":true})
	check(sleeper.sleeping and sleeper.max_health == 100.0,"sentinela do alojamento começa dormindo")
	var squads_ok := true
	for area in STATE.SQUADS:
		for spec in STATE.SQUADS[area]:
			var role := str(spec.role)
			if role not in ["sentry","patrol","leader","rifleman","flanker"] and not SOLDIER.ROLE_PARAMS.has(role): squads_ok = false
	check(squads_ok,"todo papel dos esquadrões novos existe no FortSoldier")
	for node in [marksman,shield,radioman,sleeper]: node.free()
