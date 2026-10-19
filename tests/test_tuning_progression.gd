extends SceneTree
## Peças, desbloqueio por vitórias e efeito real nos carros civis.
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const STREET := preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const PERF := preload("res://data/catalogs/VehiclePerformance.gd")
const WINS := preload("res://systems/campaign/RaceWins.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const FULL := {"ecu":"ecu_3","engine":"race_cam","turbo":"turbo_large","nitro":"nitro_pro","suspension":"suspension_sport","weight":"lightweight","exhaust":"race_exhaust"}
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)

func _run() -> void:
	# Catálogo de peças coerente com a oficina e com as vitórias possíveis.
	for id in TUNING.PARTS:
		var p: Dictionary = TUNING.PARTS[id]
		_check(str(p.slot) in TUNING.SLOTS,"Espaço desconhecido na peça "+str(id))
		_check(int(p.wins) <= WINS.maximum(),"Peça %s pede %d vitórias; o máximo é %d" % [id,int(p.wins),WINS.maximum()])
		if p.has("rival_reward"):
			_check(int(p.cost)==0 and str(p.rival_reward) in preload("res://activities/desert_drag/DragRivalChallengeCatalog.gd").IDS,"Prêmio de rival sem procedência: "+str(id))
			_check(not TUNING.purchase_check({},[],str(id),WINS.maximum(),1000000).ok,"Dinheiro não pode substituir a conquista do rival: "+str(id))
		else: _check(int(p.cost)>0,"Peça de loja sem preço: "+str(id))
		_check(not str(p.effect).is_empty(),"Peça sem efeito explicado: "+str(id))
	for slot in TUNING.SLOTS:
		_check(TUNING.PARTS.values().any(func(p): return str(p.slot) == str(slot)),"Espaço vazio: "+str(slot))
	# Seis rivais, duas corridas da campanha e um mérito da Noite; missão pulada não conta.
	_check(WINS.maximum() == 9,"Máximo de vitórias inesperado: %d" % WINS.maximum())
	_check(WINS.count({},{}) == 0,"Sem vitórias deve contar zero")
	var drag := {"desert_drag":{"version":1,"finishes":2,"wins":["digo","livia"],"completed_rivals":["digo","livia"],"best":{"digo":20.0,"livia":21.0},"last_rival":"livia","last_won":true}}
	_check(WINS.count(drag,{"completed":["cobra_race","cobra_finale","primeiro_giro"]}) == 4,"Contagem de vitórias misturadas errada")
	_check(WINS.count({},{"completed":[],"legacy_skipped":["cobra_race"]}) == 0,"Missão pulada não pode contar como vitória")
	# Efeitos de cada peça na ficha.
	var stock := TUNING.tuned_spec("sedan_classic")
	for id in TUNING.PARTS:
		var p: Dictionary = TUNING.PARTS[id]
		var s := TUNING.tuned_spec("sedan_classic",{str(p.slot):str(id)})
		if p.has("torque"): _check(float(s.torque_nm) > float(stock.torque_nm),"Torque não subiu: "+str(id))
		if p.has("redline_add"):
			if float(p.redline_add)<0: _check(float(s.redline)<float(stock.redline),"Trade-off de giro não foi aplicado: "+str(id))
			else: _check(float(s.redline)>float(stock.redline),"Giro máximo não subiu: "+str(id))
		if p.has("cap"): _check(float(s.street_cap_mps) > float(stock.street_cap_mps),"Teto de rua não subiu: "+str(id))
		if p.has("neon"): _check(str(s.neon_color) == str(p.neon) and float(s.neon_strength) == 1.0,"Neon não aplicado: "+str(id))
		if p.has("nitro_force"): _check(float(s.nitro_seconds) > 0.0,"Nitro sem duração: "+str(id))
	# Todos os civis: a preparação completa melhora, nunca piora, e o teto de rua fica em +20%.
	var reached_s := 0
	for id in STREET.ids():
		var before := PERF.measure(str(id))
		var after := PERF.measure(str(id),FULL)
		_check(float(after.score) > float(before.score)+1.0,"Preparação completa não melhora %s: %.1f -> %.1f" % [id,before.score,after.score])
		_check(float(after.quarter) < float(before.quarter),"400 m não melhorou em "+str(id))
		var legacy_top: float = float(TUNING.tuned_spec(str(id)).street_cap_mps)*3.6
		_check(float(after.top_kmh) <= legacy_top*1.2+1.0,"%s passou do teto +20%%: %.0f km/h (base %.0f)" % [id,after.top_kmh,legacy_top])
		if after["class"] == "S": reached_s += 1
	_check(reached_s >= 1,"Nenhum carro alcança a classe S preparado; a meta de classe não existe")
	print("TUNING_PROGRESSION carros_classe_S_preparados=",reached_s)
	# Salvamento aceita as peças novas e rejeita lixo.
	var record := {"archetype":"sedan_classic","parts":{"ecu":"ecu_2","neon":"neon_cyan"},"owned":["ecu_2","neon_cyan"],"presets":{}}
	_check(GARAGE.valid({"version":1,"vehicles":{"v1":record},"purchased":{}}),"Save com peças novas foi rejeitado")
	var bad := record.duplicate(true)
	bad.parts = {"ecu":"neon_cyan"}
	_check(not GARAGE.valid({"version":1,"vehicles":{"v1":bad},"purchased":{}}),"Save com peça no espaço errado foi aceito")
	# Neon no carro: instala, troca de cor sem duplicar e some ao remover.
	var car := VEHICLE.new()
	car.archetype = "sedan_classic"
	car.vehicle_id = "neon_test"
	root.add_child(car)
	car.set_physics_process(false)
	_check(car.get_node_or_null("DesertCarNeon") == null,"Carro de fábrica não deve ter neon")
	ADAPTER.attach(car,{"neon":"neon_magenta"})
	var kit := car.get_node_or_null("DesertCarNeon")
	_check(kit != null and kit.color == Color("ff3fa8"),"Neon magenta não instalou")
	ADAPTER.attach(car,{"neon":"neon_cyan"})
	_check(car.find_children("DesertCarNeon","",false,false).size() == 1,"Trocar o neon empilhou kits")
	_check(car.get_node("DesertCarNeon").color == Color("73edc3"),"Neon não mudou de cor")
	ADAPTER.attach(car,{})
	await process_frame
	_check(car.get_node_or_null("DesertCarNeon") == null,"Neon não saiu ao remover a peça")
	car.free()
	await process_frame
	print("TUNING_PROGRESSION ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
