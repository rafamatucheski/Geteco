extends SceneTree
## Contratos de horário, carga protegida e persistência; não substitui gameplay renderizado.
const STATE := preload("res://gameplay/desert_heist/DesertHeistState.gd")
const GAME_STATE := preload("res://runtime/GameState.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	for entry in [[0.0,true],[1.0/24.0,true],[4.999/24.0,true],[5.0/24.0,false],[12.0/24.0,false],[23.999/24.0,false],[-.01,false],[NAN,false],[INF,false]]:
		check(STATE.is_departure_time(entry[0]) == entry[1],"Janela de saída respeita madrugada: " + str(entry[0]))
	var first := STATE.initial(12,0)
	check(STATE.valid(first),"Carga inicial válida")
	check(first.guards.size() == 2,"Exatamente dois ocupantes protegidos")
	for guard in first.guards:
		check(guard.armor > 0 and guard.health > 0 and not guard.dead,"Ocupante inicia vivo e de colete")
	check(STATE.reward(first) > 0,"Carga tem valor para recompensa")
	check(STATE.receipt(first) != STATE.receipt(STATE.initial(12,1)),"Cargas distintas possuem recibos próprios")
	check(STATE.receipt(first) != STATE.receipt(STATE.initial(13,0)),"Nova madrugada possui recibo independente")
	var serialized: Variant = JSON.parse_string(JSON.stringify(first))
	check(STATE.valid(serialized),"Estado aceita roundtrip JSON sem perder coletes")
	for key in ["day","slot","health","distance","yaw"]:
		for invalid in [true,"1",NAN,INF]:
			var bad := first.duplicate(true)
			bad[key] = invalid
			check(not STATE.valid(bad),"Snapshot rejeita " + key + " inválido: " + str(invalid))
	for mutation in [
		{"day":-1},{"slot":2},{"phase":"open"},{"health":-1.0},{"health":901.0},
		{"position":[0,0]},{"position":[0,NAN,0]},{"distance":-1.0},{"guards":[]},
		{"guards":[first.guards[0]]},{"guards":[first.guards[0],first.guards[1],first.guards[0]]}]:
		var bad := first.duplicate(true)
		bad.merge(mutation,true)
		check(not STATE.valid(bad),"Snapshot corrupto rejeitado: " + str(mutation.keys()))
	for mutation in [{"armor":-1},{"armor":101},{"health":0,"dead":false},{"health":80,"dead":true},{"dead":"false"}]:
		var bad := first.duplicate(true)
		bad.guards[0].merge(mutation,true)
		check(not STATE.valid(bad),"Guarda corrupto rejeitado: " + str(mutation))
	var economy := ECONOMY.new()
	check(economy.grant_reward(STATE.receipt(first),STATE.reward(first)),"Carteira aceita recibo da carga")
	var balance: int = economy.balance
	check(not economy.grant_reward(STATE.receipt(first),STATE.reward(first)) and economy.balance == balance,"Repetição do recibo não duplica dinheiro")
	var restored := ECONOMY.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(economy.snapshot()))),"Carteira com recibo restaura do JSON")
	check(not restored.grant_reward(STATE.receipt(first),STATE.reward(first)) and restored.balance == balance,"Recibo continua único depois de carregar")
	# A validação da sessão precisa realmente enxergar a extensão do mundo.
	var snapshot: Dictionary = GAME_STATE.new().snapshot()
	snapshot.world[STATE.KEY] = first
	check(GAME_STATE.new().restore_snapshot(snapshot),"Sessão aceita carga válida")
	snapshot.world[STATE.KEY] = {"phase":"looted"}
	check(not GAME_STATE.new().restore_snapshot(snapshot),"Sessão rejeita carga sem dados obrigatórios")
	print("DESERT_CARGO_CONTRACT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
